# atlas-plan

Shows an implementation plan on the repository's [atlas](https://github.com/bengous/claude-code-plugins/tree/main/atlas)
map. When a plan is written in a repository that holds an atlas map folder, the `plan-map` skill
copies the map into an atlas draft (`drafts/plan-<subject>/`, ignored by git), marks what the plan
adds, changes and removes, serves the draft's page beside the session, and links it from the plan.
The original map is left untouched.

## Requirements

- The atlas plugin installed (`atlas@bengous-plugins`), and `bun`, `jq` and `git` on the `PATH`.
- A map folder tracked in the repository (made by `/atlas:init`).
- In plan mode, Claude Code lets the Edit tool write the plan file alone, so the skill writes its
  draft through `atlas-plan.sh edit`, a Bash command. The model runs it only once a `CLAUDE.md` it
  reads allows it, with a line such as:

  ```markdown
  - In plan mode, the `atlas-plan:plan-map` skill runs in full: it writes its draft (`drafts/plan-*/` in the atlas map folder, ignored by git) through `atlas-plan.sh`, its `edit` command included, and starts the draft's server. The plan map is part of the plan, and the repository's tracked files stay unchanged.
  ```

## Install

```bash
claude plugin marketplace add ~/Developer/atlas-plan
claude plugin install atlas-plan@atlas-plan
```

## What the plan map shows

- Added nodes and links carry the work phase `plan`: the page's phase stepper shows the map before
  the plan, with what the plan adds dimmed and dotted.
- Changed and removed elements carry an open point whose id starts with `plan-`; the header's
  open points list them.
- Removed leaves are drawn dashed (`kind: "off"`).

`scripts/atlas-plan.sh` finds the map folder, runs atlas's CLI, edits a draft's data files
(`scripts/edit-draft.ts`), and starts or stops a draft's server, whose pid and log sit in
`drafts/.serve/`.
