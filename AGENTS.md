# Repository Instructions

- Treat user-visible behavior changes, UI changes, settings changes, installation changes, and workflow changes as major changes by default.
- For major changes, do the full workflow without waiting for a separate request:
- Update all related documentation in the same change set. This includes README, setup guides, help text, and any user-facing docs affected by the change.
- Verify the change, then commit and push the branch unless the user explicitly says not to or pushing is blocked by a concrete safety issue.
- If pushing cannot be done safely, explain the blocker clearly before finishing.
- If the worktree contains unrelated changes, avoid reverting them and isolate only the relevant changes in your commit.
