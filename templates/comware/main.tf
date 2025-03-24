terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
    }
    docker = {
      source  = "kreuzwerker/docker"
    }
  }
}

provider "docker" {
}

provider "coder" {
}

data "coder_parameter" "project_base_svn" {
  name          = "project_base_svn"
  display_name  = "Project base SVN URL"
  description   = "Specify a base project SVN url to checkout"
  icon          = "${data.coder_workspace.me.access_url}/emojis/1f3e0.png"
  order         = 1
  type          = "string"
  mutable       = false
  default       = "http://10.153.120.80/cmwcode-open/V9R1/trunk"
}
data "coder_parameter" "project_public_svn" {
  name          = "project_public_svn"
  display_name  = "Project public SVN URL"
  description   = "Specify a public SVN url to ckeckout in the project directory. Leave blank to skip checkout"
  icon          = "${data.coder_workspace.me.access_url}/emojis/1f310.png"
  order         = 2
  type          = "string"
  mutable       = false
  default       = "http://10.153.120.104/cmwcode-public/V9R1/trunk/PUBLIC"
}
data "coder_parameter" "svn_username" {
  name          = "svn_username"
  display_name  = "SVN username"
  order         = 3
  description   = "Specify a SVN username to checkout codes"
  type          = "string"
  mutable       = false
}
data "coder_parameter" "svn_password" {
  name          = "svn_password"
  display_name  = "SVN password"
  order         = 4
  description   = "Specify a SVN password to checkout codes"
  type          = "string"
  mutable       = false
}
data "coder_provisioner" "me" {
}
data "coder_workspace" "me" {
}
data "coder_workspace_owner" "me" {
}

locals {
  assets_url = "https://cmwcoder.h3c.com/coder/assets"
  code_server_dir = "/tmp/code-server"
  marketplace_url = "https://marketplace.cmwcoder.h3c.com"
  username = data.coder_workspace_owner.me.name
  workspace = data.coder_workspace.me.name
}

resource "coder_agent" "main" {
  arch                   = data.coder_provisioner.me.arch
  os                     = "linux"

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, local.username)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, local.username)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
    PROJECT_BASE_DIR    = "/home/${local.username}/project"
  }

  display_apps {
    port_forwarding_helper = true
    ssh_helper = true
    vscode = true
    vscode_insiders = false
    web_terminal = true
  }

  metadata {
    key          = "cpu_usage"
    display_name = "CPU Usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
    order = 1
  }

  metadata {
    key          = "ram_usage"
    display_name = "RAM Usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
    order = 2
  }

  metadata {
    key          = "code_server_version"
    display_name = "Code Server Version"
    script       = <<EOF
      #!/bin/bash
      if [ -f ${local.code_server_dir}/bin/code-server ]; then
        ${local.code_server_dir}/bin/code-server --version | head -n1 | cut -d " " -f1
      else
        echo unknown
      fi
    EOF
    interval     = 30
    order        = 3
  }
}

resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "Code Server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337/?folder=/home/${local.username}/project"
  subdomain    = true
  share        = "public"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "coder_app" "coder_docs" {
  agent_id     = coder_agent.main.id
  slug         = "coder-docs"
  display_name = "Coder Docs"
  icon         = "/emojis/1f4dd.png"
  url          = "https://docs.cmwcoder.h3c.com:8443"
  external     = true
}

resource "coder_env" "extensions_gallery" {
  agent_id = coder_agent.main.id
  name     = "EXTENSIONS_GALLERY"
  value    = "{\"serviceUrl\":\"${local.marketplace_url}/api\", \"itemUrl\":\"${local.marketplace_url}/item\", \"resourceUrlTemplate\": \"${local.marketplace_url}/files/{publisher}/{name}/{version}/{path}\"}"
}

resource "coder_env" "node_extra_ca_certs" {
  agent_id = coder_agent.main.id
  name     = "NODE_EXTRA_CA_CERTS"
  value    = "/etc/ssl/certs/ca-certificates.crt"
}

resource "coder_script" "start_code_server" {
  agent_id     = coder_agent.main.id
  display_name = "Start Code Server"
  icon         = "/icon/code.svg"
  run_on_start = true
  start_blocks_login = true
  script = <<EOF
    #!/bin/bash
    echo -e "\033[36m- 📦 Installing code-server\033[0m"
    mkdir -p ${local.code_server_dir}
    curl -fsSL "${local.assets_url}/code-server-4.98.2-linux-amd64.tar.gz" | tar -C "${local.code_server_dir}" -xz --strip-components 1

    echo -e "\033[36m- ⏳ Installing extensions\033[0m"
    ${local.code_server_dir}/bin/code-server --install-extension "alefragnani.bookmarks"
    ${local.code_server_dir}/bin/code-server --install-extension "beaugust.blamer-vs"
    ${local.code_server_dir}/bin/code-server --install-extension "bierner.markdown-mermaid"
    ${local.code_server_dir}/bin/code-server --install-extension "dbaeumer.vscode-eslint@prerelease"
    ${local.code_server_dir}/bin/code-server --install-extension "esbenp.prettier-vscode@prerelease"
    ${local.code_server_dir}/bin/code-server --install-extension "ms-ceintl.vscode-language-pack-zh-hans"
    ${local.code_server_dir}/bin/code-server --install-extension "ms-python.debugpy@prerelease"
    ${local.code_server_dir}/bin/code-server --install-extension "ms-vscode.cpptools@prerelease"
    ${local.code_server_dir}/bin/code-server --install-extension "timonwong.shellcheck"
    ${local.code_server_dir}/bin/code-server --install-extension "johnstoncode.svn-scm"
    ${local.code_server_dir}/bin/code-server --install-extension "redhat.vscode-xml@prerelease"

    echo -e "\033[36m- ⏳ Starting code-server\033[0m"
    ${local.code_server_dir}/bin/code-server \
      --auth none \
      --disable-telemetry \
      --disable-update-check \
      --disable-workspace-trust \
      --locale zh-CN \
      --port 13337 \
      --trusted-origins *\
      >${local.code_server_dir}/main.log 2>&1 &
    echo -e "\033[32m- ✔️ Code server started!\033[0m"
  EOF
}

resource "coder_script" "checkout_base_svn" {
  agent_id     = coder_agent.main.id
  display_name = "Checkout base SVN project"
  icon         = "/emojis/1f3e0.png"
  run_on_start = true
  start_blocks_login = true
  script = <<EOF
    #!/bin/bash
    if [ ! -d "/home/${local.username}/project" ]; then
      svn-co-progress "${data.coder_parameter.project_base_svn.value}" \
        "/home/${local.username}/project" \
        "${data.coder_parameter.svn_username.value}" \
        "${data.coder_parameter.svn_password.value}"
    fi
  EOF
}

resource "coder_script" "checkout_public_svn" {
  agent_id     = coder_agent.main.id
  display_name = "Checkout public SVN project"
  icon         = "/emojis/1f310.png"
  run_on_start = true
  start_blocks_login = true
  script = <<EOF
    #!/bin/bash
    if [ ! -d "/home/${local.username}/project/PUBLIC" ] && [ -n "${data.coder_parameter.project_public_svn.value}" ]; then
      svn-co-progress "${data.coder_parameter.project_public_svn.value}" \
        "/home/${local.username}/project/PUBLIC" \
        "${data.coder_parameter.svn_username.value}" \
        "${data.coder_parameter.svn_password.value}"
    fi
  EOF
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.name
  name = "coder-${local.username}-${lower(local.workspace)}"
  hostname = lower(local.workspace)
  dns = ["10.72.66.36", "10.72.66.37"]
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/${local.username}"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}

resource "docker_image" "main" {
  name = "coder-${data.coder_workspace.me.id}"
  build {
    context = "./build"
    build_args = {
      USER = local.username
    }
  }
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(path.module, "build/*") : filesha1(f)]))
  }
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
}
