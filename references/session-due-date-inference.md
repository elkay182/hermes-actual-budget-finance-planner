# Session Notes — Due Date Inference & Terminal Patterns

This file intentionally contains **generic, sanitized lessons only**. Do not store real account names, account suffixes, balances, due dates, transaction evidence, server URLs, sync IDs, passwords, or other private finance data in repository docs.

## Due Date Inference Lessons

Actual Budget does not store due dates natively. If a debt sidecar has a missing or stale `due_day`, infer a likely payment day from transaction history and then ask the user to verify the contractual due date.

Generic evidence shape:

| Account | Existing due_day | Inferred payment day | Evidence | Next step |
|---|---:|---:|---|---|
| Example Credit Card A | null | 8 | 4 of 6 payments around day 8 | Ask user to confirm statement due day |
| Example Loan B | 15 | 26 | 5 of 6 payments around day 26 | Ask user whether sidecar is stale |
| Example Card C | null | null | No tracked payment transactions | Ask user or inspect statement |

## Terminal Execution Patterns

### What Works

- Write Actual Budget automation to `/tmp/script.cjs`, then run `node /tmp/script.cjs`.
- Pass secrets through environment variables, not committed files:

  ```bash
  ACTUAL_SERVER_URL="https://actual.example.com" \
  ACTUAL_PASSWORD="***" \
  ACTUAL_SYNC_ID="replace-me" \
  ACTUAL_DATA_DIR="$HOME/.cache/hermes/actual-budget" \
  node /tmp/script.cjs
  ```

### What Fails

- **`node -e '...'` inline scripts:** complex Actual Budget scripts can timeout or hit escaping issues. Prefer `.cjs` files.
- **Mixed breadcrumbs and JSON:** API sync messages can appear before JSON. Parse the final JSON object, not the whole terminal output blindly.

### Timeout Guidance

- Actual Budget API init + download can take 5–10 seconds on cached data and longer on first run.
- Use a generous foreground timeout for scripts that call `downloadBudget()` or `sync()`.
