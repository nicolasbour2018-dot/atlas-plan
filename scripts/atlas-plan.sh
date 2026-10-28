#!/usr/bin/env bash
# The plan map's commands on the atlas plugin installed for this user.
#
#   atlas-plan.sh map                  the atlas map folder of the current git repository
#   atlas-plan.sh cli <args>           atlas's own cli.ts, as atlas's skills run it
#   atlas-plan.sh edit <draft folder> <file> < blocks
#                                      replace text in a draft's data file (edit-draft.ts)
#   atlas-plan.sh serve <draft folder> serve the draft's page in the background, print its address
#   atlas-plan.sh stop <draft folder>  stop the draft's server
set -euo pipefail

INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
SCRIPTS_FOLDER=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# The atlas plugin's folder, read from Claude Code's record of installed plugins.
find_atlas_root() {
  local atlas_root
  atlas_root=$(jq -r '[.plugins | to_entries[] | select(.key | startswith("atlas@")) | .value[0].installPath][0] // empty' "$INSTALLED_PLUGINS")

  if [[ -z "$atlas_root" || ! -f "$atlas_root/src/cli.ts" ]]; then
    echo "atlas-plan: no atlas plugin installed (looked for atlas@* in $INSTALLED_PLUGINS)" >&2
    exit 1
  fi

  echo "$atlas_root"
}

# The repository's map folders: tracked folders holding map.ts, atlas.config.ts and atlas.d.ts.
find_map_folder() {
  local repository_root
  repository_root=$(git rev-parse --show-toplevel)

  local map_folders=()
  local config_file
  while IFS= read -r config_file; do
    local map_folder="$repository_root/$(dirname "$config_file")"
    if [[ -f "$map_folder/map.ts" && -f "$map_folder/atlas.d.ts" ]]; then
      map_folders+=("$map_folder")
    fi
  done < <(git -C "$repository_root" ls-files -- 'atlas.config.ts' '*/atlas.config.ts')

  if [[ ${#map_folders[@]} -eq 0 ]]; then
    echo "atlas-plan: no atlas map folder in $repository_root" >&2
    exit 3
  fi

  if [[ ${#map_folders[@]} -gt 1 ]]; then
    echo "atlas-plan: several atlas map folders in $repository_root:" >&2
    printf '  %s\n' "${map_folders[@]}" >&2
    exit 2
  fi

  echo "${map_folders[0]}"
}

run_atlas_cli() {
  local atlas_root
  atlas_root=$(find_atlas_root)
  bun "--config=$atlas_root/child.bunfig.toml" --no-env-file "$atlas_root/src/cli.ts" "$@"
}

edit_draft_file() {
  local atlas_root
  atlas_root=$(find_atlas_root)
  bun "--config=$atlas_root/child.bunfig.toml" --no-env-file "$SCRIPTS_FOLDER/edit-draft.ts" "$@"
}

# The server's pid and log sit in drafts/.serve/: serve.ts rebuilds on any change in the draft folder.
server_files_of() {
  local draft_folder=$1
  local draft_name
  draft_name=$(basename "$draft_folder")
  local server_folder
  server_folder="$(dirname "$draft_folder")/.serve"
  mkdir -p "$server_folder"
  echo "$server_folder/$draft_name"
}

serve_draft() {
  local draft_folder
  draft_folder=$(cd "$1" && pwd)

  if [[ "$(basename "$(dirname "$draft_folder")")" != "drafts" || ! -f "$draft_folder/map.ts" ]]; then
    echo "atlas-plan: $draft_folder is no atlas draft (drafts/<name>/map.ts)" >&2
    exit 1
  fi

  local server_files
  server_files=$(server_files_of "$draft_folder")
  local pid_file="$server_files.pid"
  local log_file="$server_files.log"

  # A server already up for this draft keeps its address.
  if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    grep -m1 -o 'http://[^ ]*' "$log_file"
    return
  fi

  local atlas_root
  atlas_root=$(find_atlas_root)
  nohup bun "--config=$atlas_root/child.bunfig.toml" --no-env-file "$atlas_root/src/serve.ts" "$draft_folder" 0 >"$log_file" 2>&1 &
  echo $! >"$pid_file"

  # serve.ts prints its address once it listens.
  local attempt
  for attempt in $(seq 1 40); do
    if grep -q 'http://' "$log_file"; then
      grep -m1 -o 'http://[^ ]*' "$log_file"
      return
    fi
    if ! kill -0 "$(cat "$pid_file")" 2>/dev/null; then
      break
    fi
    sleep 0.25
  done

  echo "atlas-plan: the server of $draft_folder printed no address:" >&2
  cat "$log_file" >&2
  exit 1
}

stop_draft_server() {
  local draft_folder=$1
  local server_files
  server_files=$(server_files_of "$draft_folder")
  local pid_file="$server_files.pid"

  if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    kill "$(cat "$pid_file")"
  fi

  rm -f "$pid_file" "$server_files.log"
}

command_name=${1:-}
shift || true

case "$command_name" in
  map) find_map_folder ;;
  cli) run_atlas_cli "$@" ;;
  edit) edit_draft_file "$@" ;;
  serve) serve_draft "${1:?usage: atlas-plan.sh serve <draft folder>}" ;;
  stop) stop_draft_server "${1:?usage: atlas-plan.sh stop <draft folder>}" ;;
  *)
    echo "usage: atlas-plan.sh map | cli <args> | edit <draft folder> <file> | serve <draft folder> | stop <draft folder>" >&2
    exit 64
    ;;
esac
