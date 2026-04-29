# AGENTS.md

## Project intent

This repository contains a Hermes Agent skill for Actual Budget finance workflows. The primary artifact is `SKILL.md`.

## Review guidelines

- Do not add secrets, credentials, real account IDs, budget sync IDs, or personal finance data.
- Preserve read-only behavior as the default.
- Require explicit user confirmation before any Actual Budget write operation.
- Do not add workflows that initiate real-world bank payments, transfers, trades, retirement withdrawals, or creditor communications.
- Prefer `@actual-app/api` Node.js automation over direct REST calls.
- Keep examples generic and safe.
- If adding scripts, make them dry-run by default and require an explicit `--apply` flag for writes.
- Keep financial guidance framed as educational budgeting support, not professional fiduciary, legal, accounting, bankruptcy, tax, investment, or lending advice.

## Validation checklist

- `SKILL.md` has valid YAML frontmatter.
- `SKILL.md` contains no private data.
- Installation instructions copy `SKILL.md` into `~/.hermes/skills/actual-budget-finance-planner/SKILL.md`.
- Examples use placeholders for environment variables.
- Any write-capable workflow has a dry-run path and explicit confirmation path.
