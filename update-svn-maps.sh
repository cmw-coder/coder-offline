#!/bin/bash

# Host-side cron script: periodically refresh SVN directory maps.
# Runs get-svn-all-map.sh for both platform and public SVN repos,
# unwraps the Terraform external format, and writes raw JSON files
# for Caddy to serve to the Coder provisioner via HTTP.
#
# Prerequisites on the Docker host:
#   - bash 4+, jq, svn (subversion client)
#   - get-svn-all-map.sh in the same directory as this script
#
# Usage:
#   ./update-svn-maps.sh [output_dir]
#
# Default output_dir: /opt/coder-svn-maps
#
# Cron example (every 30 minutes):
#   */30 * * * * /opt/coder-svn-maps/update-svn-maps.sh >> /opt/coder-svn-maps/cron.log 2>&1

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-/opt/coder-svn-maps}"
LOG_FILE="${OUTPUT_DIR}/update.log"

mkdir -p "$OUTPUT_DIR"

log() { echo "[update-svn-maps] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"; }

# Refresh a single SVN map.
# Arguments: $1=label, $2=output_filename, $3=JSON query for get-svn-all-map.sh stdin
refresh_map() {
	local label="$1"
	local output_file="$OUTPUT_DIR/$2"
	local query_json="$3"
	local raw_tmp="${output_file}.raw.tmp"
	local parsed_tmp="${output_file}.parsed.tmp"

	log "Refreshing ${label} SVN map..."

	# Run the SVN tree traversal script (reads JSON from stdin, outputs {"data": "<json>"})
	if echo "$query_json" | bash "$SCRIPT_DIR/get-svn-all-map.sh" >"$raw_tmp" 2>>"$LOG_FILE"; then
		# Unwrap from Terraform external format to raw JSON
		if jq '.data | fromjson' "$raw_tmp" >"$parsed_tmp" 2>>"$LOG_FILE"; then
			mv "$parsed_tmp" "$output_file"
			local size
			size=$(stat -c%s "$output_file" 2>/dev/null || wc -c <"$output_file")
			log "${label} map updated successfully (${size} bytes)"
			rm -f "$raw_tmp"
			return 0
		else
			log "ERROR: Failed to parse ${label} map JSON output"
			rm -f "$raw_tmp" "$parsed_tmp"
			return 1
		fi
	else
		log "ERROR: get-svn-all-map.sh failed for ${label}"
		rm -f "$raw_tmp"
		return 1
	fi
}

# ---- Main ----

log "=== Starting SVN map refresh ==="

platform_ok=0
public_ok=0

refresh_map "platform" "platform_map.json" \
	'{"base_url":"http://10.153.120.80/cmwcode-open/","svn_username":"z11187","svn_password":"Zpr758258%","code_level_markers":"ACCESS,DEV,IP,NETFWD"}' &&
	platform_ok=1

refresh_map "public" "public_map.json" \
	'{"base_url":"http://10.153.120.104/cmwcode-public/","svn_username":"z11187","svn_password":"Zpr758258%","code_level_markers":"PUBLIC"}' &&
	public_ok=1

if [ "$platform_ok" -eq 1 ] && [ "$public_ok" -eq 1 ]; then
	log "=== All maps refreshed successfully ==="
else
	log "=== Refresh completed with errors (platform=${platform_ok}, public=${public_ok}) ==="
	exit 1
fi
