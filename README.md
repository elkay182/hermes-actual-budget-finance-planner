# Hermes Actual Budget Finance Planner Skill

A Hermes Agent skill for managing finances with [Actual Budget](https://actualbudget.org/) using the official `@actual-app/api` Node.js automation package.

This skill helps Hermes perform read-only financial analysis by default, classify transactions with an optional LLM-assisted review workflow, and build debt payoff plans using snowball, avalanche, hybrid, Cash Flow Index, and debt-ratio / DTI impact methods.

## What it does

- Connects Hermes to Actual Budget through `@actual-app/api`.
- Produces account, balance, category, income, spending, and cash-flow summaries.
- Builds debt payoff plans with multiple strategy options:
  - debt snowball
  - debt avalanche
  - hybrid snowball / avalanche
  - Cash Flow Index (CFI)
  - debt-ratio / DTI impact
  - custom manual priority
  - Actual-specific credit-card carrying-debt handling
- Provides LLM-assisted categorization workflows:
  - classify uncategorized transactions with an LLM
  - dry-run before applying changes
  - track suggestions, confidence, and review status in a local sidecar file
  - propose new categories when existing categories do not fit
  - keep Actual Budget transaction notes/tags unchanged unless explicitly requested
  - rerun previously missed or rejected transactions
  - suggest or create new categories after explicit confirmation
  - optionally sync before classification
  - optionally use merchant web search for ambiguous payees
- Enforces write-safety guardrails:
  - read-only by default
  - no payments, transfers, trades, or lender interactions
  - explicit confirmation required before writes
  - sync after writes and summarize changes

## Install

Clone this repository, then copy the skill into Hermes' skills directory. Copy the whole skill support set so linked reference docs and examples remain available:

```bash
git clone https://github.com/elkay182/hermes-actual-budget-finance-planner.git
mkdir -p ~/.hermes/skills/actual-budget-finance-planner
cp hermes-actual-budget-finance-planner/SKILL.md ~/.hermes/skills/actual-budget-finance-planner/SKILL.md
for dir in references examples scripts docs; do
  if [ -d "hermes-actual-budget-finance-planner/$dir" ]; then
    cp -R "hermes-actual-budget-finance-planner/$dir" ~/.hermes/skills/actual-budget-finance-planner/
  fi
done
```

Or install directly from a local checkout:

```bash
./scripts/install.sh
```

Restart Hermes after installing the skill.

## Required environment variables

```bash
export ACTUAL_SERVER_URL="https://actual.example.com"
export ACTUAL_PASSWORD="replace-me"
export ACTUAL_SYNC_ID="replace-me"
```

Optional:

```bash
export ACTUAL_ENCRYPTION_PASSWORD="replace-me"
export ACTUAL_DATA_DIR="$HOME/.cache/hermes/actual-budget"
export ACTUAL_DEBT_PROFILE="$HOME/.hermes/state/actual-debt-profile.json"
export ACTUAL_AI_REVIEW_PATH="$HOME/.hermes/state/actual-llm-review.json"
export ACTUAL_AI_BASE_URL="http://localhost:11434/v1"
export ACTUAL_AI_API_KEY="replace-me"
export ACTUAL_AI_MODEL="replace-me"
```

See [`examples/env.example`](examples/env.example).

## Example Hermes prompts

```text
Use the actual-budget-finance-planner skill.

Pull my Actual Budget data and give me:
- account balances
- monthly spending by category
- cash flow
- debt summary

Mode: dry-run
```

```text
Use the actual-budget-finance-planner skill.

Build a debt payoff plan comparing:
- snowball
- avalanche
- cash flow index
- debt-ratio / DTI impact

Assume I want to minimize interest but also improve monthly cash flow quickly.

Mode: dry-run
```

```text
Use the actual-budget-finance-planner skill.

Classify uncategorized transactions using LLM classification.
Track suggestions in the local LLM review sidecar.
Do not add tags or notes to Actual Budget transactions.
Do not apply changes yet.

Mode: dry-run
```

## Safety model

This skill is for educational budgeting support. It does not provide fiduciary, legal, accounting, bankruptcy, tax, investment, or lending advice. It must not initiate real-world payments, transfers, trades, retirement withdrawals, or creditor interactions.

## Repository layout

```text
.
├── SKILL.md
├── README.md
├── AGENTS.md
├── LICENSE
├── examples/
│   ├── debt-profile.example.json
│   └── env.example
├── references/
│   ├── due-date-inference.md
│   ├── payoff-methods.md
│   └── session-due-date-inference.md
├── scripts/
│   └── install.sh
└── docs/
    └── codex-task.md
```
