#!/usr/bin/env bash
# PreToolUse hook on ExitPlanMode: refuses a plan that carries no plan map line
# (`<!-- atlas-plan: ... -->`) in a git repository that holds an atlas map folder.
# Claude Code injects the plan's text into tool_input.plan before it runs the hook.
set -euo pipefail

SCRIPTS_FOLDER=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLAN_MAP_LINE='<!-- atlas-plan:'

hook_input=$(cat)
session_folder=$(jq -r '.cwd' <<<"$hook_input")
plan_text=$(jq -r '.tool_input.plan // ""' <<<"$hook_input")

# A plan that already carries its plan map line goes through.
if [[ "$plan_text" == *"$PLAN_MAP_LINE"* ]]; then
  exit 0
fi

# Outside a git repository there is no map to draw on.
if ! git -C "$session_folder" rev-parse --show-toplevel >/dev/null 2>&1; then
  exit 0
fi

# Exit 3: the repository has no map. Exit 2: several maps, which the skill asks the user about.
map_status=0
map_output=$(cd "$session_folder" && "$SCRIPTS_FOLDER/atlas-plan.sh" map 2>&1) || map_status=$?

if [[ $map_status -eq 3 ]]; then
  exit 0
fi

if [[ $map_status -ne 0 && $map_status -ne 2 ]]; then
  echo "atlas-plan hook: could not look for an atlas map in $session_folder: $map_output" >&2
  exit 1
fi

refusal_reason="This repository holds an atlas map ($map_output). Run the atlas-plan:plan-map skill on this plan: it adds the plan map section, with its line $PLAN_MAP_LINE <draft folder> -->, to the plan file, or the line $PLAN_MAP_LINE none --> to a plan that touches no element of the map. Then call ExitPlanMode again."

jq -n --arg reason "$refusal_reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
