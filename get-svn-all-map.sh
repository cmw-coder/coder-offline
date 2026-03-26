#!/bin/bash

# Pre-fetch complete SVN directory tree for ALL versions and branches.
# Replaces get-svn-map.sh, get-svn-subtree.sh, and get-svn-list.sh.
#
# Input (stdin JSON from Terraform external data source):
#   {
#     "base_url": "http://.../cmwcode-open/",
#     "svn_username": "...",
#     "svn_password": "...",
#     "code_level_markers": "ACCESS,DEV,IP,NETFWD"
#   }
#
# Output (Terraform external data source format):
#   {"data": "<serialized JSON>"}
#
# The serialized JSON has this structure:
#   {
#     "V9R1": {
#       "branches": ["trunk", "branches_bugfix", "tags"],
#       "trunk": {
#         "depth": 0,
#         "folders": ["ACCESS", "DEV", "IP", "NETFWD"]
#       },
#       "branches_bugfix": {
#         "depth": 2,
#         "level_0": ["fix1", "fix2"],
#         "level_1__fix1": ["sub1", "sub2"],
#         "level_1__fix2": ["sub3"],
#         "folders": ["ACCESS", "DEV", "IP", "NETFWD"]
#       }
#     }
#   }
#
# Design notes:
#   - "branches" key: ordered list of branch names for dropdown options
#   - "depth" key: per-branch, 0 = code is directly under branch (e.g., trunk)
#   - "level_N__X__Y" keys: intermediate directory entries for subdir cascading
#   - "folders" key: sampled from the FIRST leaf path of each branch (not per-path)
#     because code-level directories are the same across all paths within a branch
#   - Aggressive parallelism: one background process per version/branch combo

set -euo pipefail

# Read input from Terraform (stdin)
eval "$(jq -r '@sh "BASE_URL=\(.base_url) SVN_PASSWORD_INPUT=\(.svn_password) SVN_USERNAME_INPUT=\(.svn_username) CODE_LEVEL_MARKERS=\(.code_level_markers)"')"

SVN_PASSWORD=${SVN_PASSWORD_INPUT:-${SVN_PASSWORD:-""}}
SVN_USERNAME=${SVN_USERNAME_INPUT:-${SVN_USERNAME:-""}}

MAX_DEPTH=6

# Diagnostic logging to stderr (visible in Terraform logs, not in JSON output)
log() { echo "[get-svn-all-map] $*" >&2; }
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# =============================================================================
# Helper functions
# =============================================================================

svn_with_auth() {
	if [ -n "$SVN_USERNAME" ] && [ -n "$SVN_PASSWORD" ]; then
		svn "$@" --no-auth-cache --non-interactive --password "$SVN_PASSWORD" --username "$SVN_USERNAME" 2>/dev/null
	else
		svn "$@" --no-auth-cache --non-interactive 2>/dev/null
	fi
}

# Get directory entries from an SVN URL (directories only, trailing / stripped)
get_svn_dirs() {
	local url=$1
	local contents
	contents=$(svn_with_auth ls "${url}") || {
		log "WARN: svn ls failed for ${url}"
		echo ""
		return 0
	}
	# { grep ... || true; } prevents exit code 1 when no directories found
	# (grep returns 1 on no match, which kills the script under set -euo pipefail)
	echo "${contents}" | { grep '/$' || true; } | sed 's/\/$//'
}

# Check if directory listing contains any code-level marker directories
is_code_level() {
	local entries="$1"
	local markers="$2"

	IFS=',' read -ra marker_array <<<"$markers"
	for marker in "${marker_array[@]}"; do
		marker=$(echo "$marker" | xargs)
		[ -z "$marker" ] && continue
		if echo "$entries" | grep -qx "$marker"; then
			return 0
		fi
	done
	return 1
}

# Convert a newline-separated list to a JSON array of strings
list_to_json_array() {
	local input="$1"
	if [ -z "$input" ]; then
		echo "[]"
		return
	fi
	printf '%s\n' "$input" | { grep -v '^$' || true; } | jq -R . | jq -s .
}

# Probe depth for a single branch by sampling the FIRST entry at each level.
# Also outputs the sampled path so we can reuse it for folder listing.
# Returns: "depth first_entry_0/first_entry_1/..."
probe_branch_depth() {
	local url="$1"
	local markers="$2"
	local depth=0
	local probe_url="$url"
	local sampled_path=""

	while [ "$depth" -lt "$MAX_DEPTH" ]; do
		local entries
		entries=$(get_svn_dirs "$probe_url")
		[ -z "$entries" ] && break

		if is_code_level "$entries" "$markers"; then
			break
		fi

		depth=$((depth + 1))
		local first_entry
		first_entry=$(echo "$entries" | head -1)
		[ -z "$first_entry" ] && break

		if [ -n "$sampled_path" ]; then
			sampled_path="${sampled_path}/${first_entry}"
		else
			sampled_path="${first_entry}"
		fi
		probe_url="${url}${sampled_path}/"
	done

	echo "${depth} ${sampled_path}"
}

# Process a single branch: detect depth, collect intermediate dirs, sample folders.
# Writes result JSON to $TMPDIR_BASE/branch_<version>_<branch>
# All JSON accumulation uses files + --slurpfile to avoid ARG_MAX limits.
process_branch() {
	local version="$1"
	local branch="$2"
	local branch_url="$3"
	local markers="$4"
	local outfile="$TMPDIR_BASE/branch_${version}_${branch}"

	# Step 1: Probe depth and get sampled path
	local probe_result
	probe_result=$(probe_branch_depth "$branch_url" "$markers")
	local depth sampled_path
	depth=$(echo "$probe_result" | cut -d' ' -f1)
	sampled_path=$(echo "$probe_result" | cut -d' ' -f2-)

	log "Branch ${version}/${branch}: depth=${depth}, sampled_path='${sampled_path}'"

	# Initialize result file with depth
	jq -n --argjson d "$depth" '{"depth": $d}' >"$outfile"

	# Step 2: Collect intermediate-level entries (only if depth > 0)
	if [ "$depth" -gt 0 ]; then
		# Level 0: entries directly under the branch
		local level_0_entries
		level_0_entries=$(get_svn_dirs "$branch_url")
		local l0_file="$TMPDIR_BASE/l0arr_${version}_${branch}"
		list_to_json_array "$level_0_entries" >"$l0_file"
		jq --slurpfile entries "$l0_file" '. + {"level_0": $entries[0]}' "$outfile" >"${outfile}.tmp"
		mv "${outfile}.tmp" "$outfile"

		# Level 1+: nested entries (parallelized within branch for level 1)
		if [ "$depth" -ge 2 ]; then
			local l1_tmpdir="$TMPDIR_BASE/l1_${version}_${branch}"
			mkdir -p "$l1_tmpdir"

			while IFS= read -r l0_entry; do
				[ -z "$l0_entry" ] && continue
				(
					l1_entries=$(get_svn_dirs "${branch_url}${l0_entry}/")
					list_to_json_array "$l1_entries" >"$l1_tmpdir/${l0_entry}"

					# Level 2 (if depth >= 3)
					if [ "$depth" -ge 3 ] && [ -n "$l1_entries" ]; then
						while IFS= read -r l1_entry; do
							[ -z "$l1_entry" ] && continue
							l2_entries=$(get_svn_dirs "${branch_url}${l0_entry}/${l1_entry}/")
							list_to_json_array "$l2_entries" >"$l1_tmpdir/${l0_entry}__${l1_entry}"

							# Level 3 (if depth >= 4)
							if [ "$depth" -ge 4 ] && [ -n "$l2_entries" ]; then
								while IFS= read -r l2_entry; do
									[ -z "$l2_entry" ] && continue
									l3_entries=$(get_svn_dirs "${branch_url}${l0_entry}/${l1_entry}/${l2_entry}/")
									list_to_json_array "$l3_entries" >"$l1_tmpdir/${l0_entry}__${l1_entry}__${l2_entry}"
								done <<<"$l2_entries"
							fi
						done <<<"$l1_entries"
					fi
				) &
			done <<<"$level_0_entries"

			wait || true

			# Collect level 1+ results from temp files (using --slurpfile, not --argjson)
			for tmpfile in "$l1_tmpdir"/*; do
				[ -f "$tmpfile" ] || continue
				local basename
				basename=$(basename "$tmpfile")

				# Determine the key based on the number of __ separators
				local num_separators
				num_separators=$(echo "$basename" | { grep -o '__' || true; } | wc -l)

				local key
				if [ "$num_separators" -eq 0 ]; then
					key="level_1__${basename}"
				elif [ "$num_separators" -eq 1 ]; then
					key="level_2__${basename}"
				elif [ "$num_separators" -eq 2 ]; then
					key="level_3__${basename}"
				else
					key="level_$((num_separators + 1))__${basename}"
				fi

				jq --arg k "$key" --slurpfile entries "$tmpfile" '. + {($k): $entries[0]}' "$outfile" >"${outfile}.tmp"
				mv "${outfile}.tmp" "$outfile"
			done
		fi
	fi

	# Step 3: Sample folders from the code level
	# Use the sampled path from depth probing to reach the code level
	local folder_url
	if [ -n "$sampled_path" ]; then
		folder_url="${branch_url}${sampled_path}/"
	else
		folder_url="$branch_url"
	fi

	local folder_entries
	folder_entries=$(get_svn_dirs "$folder_url")
	local folder_file="$TMPDIR_BASE/folders_${version}_${branch}"
	list_to_json_array "$folder_entries" >"$folder_file"
	jq --slurpfile folders "$folder_file" '. + {"folders": $folders[0]}' "$outfile" >"${outfile}.tmp"
	mv "${outfile}.tmp" "$outfile"
}

# =============================================================================
# Main execution
# =============================================================================

# Phase 1: List all versions
log "Starting: base_url=${BASE_URL}, markers=${CODE_LEVEL_MARKERS}"
versions=$(get_svn_dirs "$BASE_URL")

if [ -z "$versions" ]; then
	log "WARN: No versions found at ${BASE_URL}, returning empty map"
	jq -n '{"data": "{}"}'
	exit 0
fi

log "Found versions: $(echo "$versions" | tr '\n' ' ')"

# Phase 2: For each version, list branches and process each branch in parallel
# All JSON accumulation uses files + --slurpfile to avoid ARG_MAX limits.
final_file="$TMPDIR_BASE/final_json"
echo '{}' >"$final_file"

while IFS= read -r version; do
	[ -z "$version" ] && continue

	# Filter: only process directories matching version naming pattern (e.g., V7R1_*, V9R1_*)
	# This skips root-level structural dirs like trunk/, branches_bugfix/, tags/, WLANlib/, textfsm/
	if [[ ! "$version" =~ ^V[0-9]+R[0-9] ]]; then
		log "SKIP: '${version}' does not match version pattern V[0-9]R[0-9]*, skipping"
		continue
	fi

	version_url="${BASE_URL}${version}/"

	# List branches for this version
	branches=$(get_svn_dirs "$version_url")
	if [ -z "$branches" ]; then
		log "WARN: No branches found for version ${version}, skipping"
		continue
	fi

	log "Version ${version}: branches=$(echo "$branches" | tr '\n' ' ')"

	# Build branch list JSON (small, safe for --argjson)
	branch_list_json=$(list_to_json_array "$branches")

	# Launch parallel processing for each branch
	while IFS= read -r branch; do
		[ -z "$branch" ] && continue
		branch_url="${version_url}${branch}/"

		if [ "$branch" = "trunk" ]; then
			# trunk is always depth 0, just sample folders directly
			(
				folder_entries=$(get_svn_dirs "$branch_url")
				trunk_folder_file="$TMPDIR_BASE/trunk_folders_${version}"
				list_to_json_array "$folder_entries" >"$trunk_folder_file"
				jq -n --slurpfile folders "$trunk_folder_file" '{"depth": 0, "folders": $folders[0]}' \
					>"$TMPDIR_BASE/branch_${version}_${branch}"
			) &
		else
			process_branch "$version" "$branch" "$branch_url" "$CODE_LEVEL_MARKERS" &
		fi
	done <<<"$branches"

	# Wait for all branches of this version to complete
	wait || true

	# Assemble version JSON using files (avoids ARG_MAX)
	version_file="$TMPDIR_BASE/version_${version}"
	jq -n --argjson branches "$branch_list_json" '{"branches": $branches}' >"$version_file"

	while IFS= read -r branch; do
		[ -z "$branch" ] && continue
		outfile="$TMPDIR_BASE/branch_${version}_${branch}"
		if [ -f "$outfile" ]; then
			# Use --slurpfile to read branch JSON from file (not command-line arg)
			jq --arg k "$branch" --slurpfile v "$outfile" '. + {($k): $v[0]}' "$version_file" >"${version_file}.tmp"
			mv "${version_file}.tmp" "$version_file"
		else
			# Fallback: branch with depth 0 and empty folders
			log "WARN: No output file for ${version}/${branch}, using fallback"
			jq --arg k "$branch" '. + {($k): {"depth": 0, "folders": []}}' "$version_file" >"${version_file}.tmp"
			mv "${version_file}.tmp" "$version_file"
		fi
	done <<<"$branches"

	# Add assembled version to final JSON using --slurpfile
	jq --arg k "$version" --slurpfile v "$version_file" '. + {($k): $v[0]}' "$final_file" >"${final_file}.tmp"
	mv "${final_file}.tmp" "$final_file"
done <<<"$versions"

# Output in Terraform external data source format
log "Done. Outputting final JSON."
jq '{"data": (. | tostring)}' "$final_file"
