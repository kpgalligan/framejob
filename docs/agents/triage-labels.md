# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

This repo carries a **sixth** label the five roles have no room for: `spec`, for an issue that IS a spec (`docs/agents/issue-tracker.md:30`) or that needs a spec §11 decision before it can be built (#27 is one). An issue labelled `spec` never takes `ready-for-agent` — that label is a work order to a polling agent, and a spec is an input.

Two more labels sit beside the roles: `ai-drafted` on every issue an agent creates, and `low-priority` on every agent-created issue that is not urgent (the test is in `docs/agents/issue-tracker.md`).

Edit the right-hand column to match whatever vocabulary you actually use.
