# Codex Task: Publish Hermes Actual Budget Finance Planner Skill

## Goal

Prepare and publish this repository as a clean, safe, GitHub-hosted Hermes Agent skill for Actual Budget finance workflows.

## Tasks

1. Verify `SKILL.md` YAML frontmatter is valid.
2. Verify `README.md` accurately describes installation, required environment variables, example prompts, and safety model.
3. Verify `examples/env.example` contains only placeholder values.
4. Verify `examples/debt-profile.example.json` contains only placeholder values and no private financial data.
5. Verify `scripts/install.sh` installs to:

   ```bash
   ~/.hermes/skills/actual-budget-finance-planner/SKILL.md
   ```

6. Confirm all write-capable Actual Budget workflows remain dry-run by default and require explicit confirmation.
7. Add or improve tests/linting only if it does not complicate the repo.
8. Open a pull request with a concise summary and validation notes.

## Constraints

- Do not add secrets, real account numbers, real balances, real names, or real transaction data.
- Do not convert Actual Budget automation to direct REST calls; use `@actual-app/api` as the official automation surface.
- Do not add any feature that performs real-world payments, transfers, trades, retirement withdrawals, or creditor communications.
- Keep financial language educational and non-fiduciary.

## Suggested PR title

Publish Hermes Actual Budget Finance Planner skill
