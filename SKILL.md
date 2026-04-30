---
name: actual-budget-finance-planner
description: Use Actual Budget's official Node.js API to analyze budgets, cash flow, spending, account balances, and debt payoff plans. Use for personal finance checkups, debt snowball planning, budget category adjustments, transaction review, and safe user-confirmed Actual Budget updates.
version: 1.0.0
author: elkay182 / ChatGPT
license: MIT
metadata:
  hermes:
    category: productivity
    tags: [finance, budgeting, actual-budget, debt-snowball, personal-finance, cash-flow]
    requires_toolsets: [terminal]
    config:
      - key: actualBudget.dataDir
        description: Local cache directory for Actual Budget API data.
        default: ~/.cache/hermes/actual-budget
        prompt: Where should Hermes cache Actual Budget data locally?
required_environment_variables:
  - name: ACTUAL_SERVER_URL
    prompt: Actual Budget sync server URL, for example https://actual.example.com
    help: The URL of the running Actual Budget server.
    required_for: Connecting to Actual Budget
  - name: ACTUAL_PASSWORD
    prompt: Actual Budget server password
    help: Store this as an environment variable or secret. Do not hard-code it in scripts.
    required_for: Connecting to Actual Budget
  - name: ACTUAL_SYNC_ID
    prompt: Actual Budget Sync ID from Settings → Advanced / Show advanced settings → Sync ID
    help: Identifies the budget file to load.
    required_for: Loading the correct Actual Budget file
---

# Actual Budget Finance Planner

Use this skill when the user wants Hermes to inspect or manage finances through Actual Budget, review spending, build a budget, plan debt payoff, create a debt snowball, compare snowball vs avalanche payoff orders, categorize transactions, adjust budget amounts, or automate Actual Budget workflows.

This skill uses Actual Budget's official Node.js package, `@actual-app/api`. Actual does **not** expose a normal REST API for budget automation. Do not use `curl` against `ACTUAL_SERVER_URL` for finance operations unless the user is explicitly asking about server health. Run short Node.js scripts through the terminal.

## Operating Principles

1. Default to **read-only analysis**.
2. Never claim to be a certified financial planner, CPA, attorney, or fiduciary.
3. Treat outputs as educational budgeting support unless the user provides professional context.
4. Never invent balances, APRs, promo dates, minimum payments, due dates, income, or debts.
5. If Actual Budget does not store a needed debt field, ask for it or use a local sidecar JSON file.
6. Before any write operation, show the exact proposed changes and get explicit user confirmation.
7. Do not initiate real-world payments, transfers, investing trades, or creditor interactions. Actual Budget can track planned and completed activity; it cannot replace the user's bank or lender.
8. Prefer debt elimination, emergency cash protection, and recurring‑expense clarity over aggressive optimization. **For dry‑run requests, set `ACTUAL_APPLY=false` and execute the provided script from `/tmp`; no changes are made unless the user explicitly confirms and `ACTUAL_APPLY=true` is set**.
9. When analyzing debt, always distinguish:
   - recorded Actual account balance
   - statement balance
   - payoff balance
   - APR / promo APR
   - minimum payment
   - due date
   - promotional expiration date
10. After write operations, call `api.sync()` and provide a verification summary.

## Setup / Dependency Check

Before using the API, verify Node and install the package in a workspace-local or temp directory:

```bash
node --version
npm --version
npm install --save @actual-app/api
```

Use environment variables for secrets:

```bash
export ACTUAL_SERVER_URL="https://actual.example.com"
export ACTUAL_PASSWORD="replace-me"
export ACTUAL_SYNC_ID="replace-me"
export ACTUAL_DATA_DIR="${ACTUAL_DATA_DIR:-$HOME/.cache/hermes/actual-budget}"
# Optional, only if the Actual budget file has end-to-end encryption enabled:
export ACTUAL_ENCRYPTION_PASSWORD="replace-me"
# Optional, for self-signed or private CA TLS:
export NODE_EXTRA_CA_CERTS="/path/to/ca.pem"
```

Avoid `NODE_TLS_REJECT_UNAUTHORIZED=0` unless the user explicitly accepts the risk and the script will contact only the user's Actual server.

## Reusable Connection Pattern

Use this pattern for every script. Always call `shutdown()` in `finally`.

```js
const api = require('@actual-app/api');

async function withActual(fn) {
  const dataDir = process.env.ACTUAL_DATA_DIR || `${process.env.HOME || process.cwd()}/.cache/hermes/actual-budget`;

  await api.init({
    dataDir,
    serverURL: process.env.ACTUAL_SERVER_URL,
    password: process.env.ACTUAL_PASSWORD,
  });

  try {
    const encryption = process.env.ACTUAL_ENCRYPTION_PASSWORD
      ? { password: process.env.ACTUAL_ENCRYPTION_PASSWORD }
      : undefined;

    await api.downloadBudget(process.env.ACTUAL_SYNC_ID, encryption);
    return await fn(api);
  } finally {
    await api.shutdown();
  }
}

function dollars(integerAmount) {
  if (integerAmount === null || integerAmount === undefined) return null;
  return Number(integerAmount) / 100;
}

function cents(decimalAmount) {
  return api.utils.amountToInteger(Number(decimalAmount));
}
```

Actual stores currency amounts as integers with no decimal places. In USD-style currencies, store a dollar amount as integer cents, not as a decimal string. Dates are `YYYY-MM-DD`; months are `YYYY-MM`.

## Actual API Shape Notes / Source of Truth

Observed API shape can differ from examples in older docs. Verify shape before doing calculations.

- `api.getAccounts()` may not include `type`; do not rely on `acct.type` for debt/cash classification. Use account names plus the debt sidecar (`actual-debt-profile.json`) when available.
- `api.getBudgetMonth(month)` returns monthly budget data under `budget.categoryGroups`, not `budget.categories`.
- Category rows inside `budget.categoryGroups[].categories[]` use:
  - `budgeted` for assigned/budgeted amount
  - `spent` for monthly category activity
  - `balance` for available/remaining amount
- For monthly spending by category and cash-flow by category, prefer `getBudgetMonth(month).categoryGroups[].categories[].spent/balance`. This avoids double-counting payments/transfers between on-budget accounts.
- Use `getTransactions()` for payee review, uncategorized samples, subscription detection, and transaction-level auditing — not as the primary category-spend total unless you explicitly filter transfers and account-payment rows.

Example category cash-flow extraction:

```js
const budget = await api.getBudgetMonth(month);
const categoryRows = [];
for (const group of budget.categoryGroups || []) {
  for (const cat of group.categories || []) {
    if (cat.hidden || cat.is_income) continue;
    categoryRows.push({
      group: group.name,
      name: cat.name,
      budgeted: dollars(cat.budgeted || 0),
      spent: dollars(cat.spent || 0),
      available: dollars(cat.balance || 0),
    });
  }
}
```

## Read-Only Financial Snapshot

Use this first for most finance questions.

```bash
cat > /tmp/actual_snapshot.cjs <<'JS'
const fs = require('fs');
const api = require('@actual-app/api');

async function withActual(fn) {
  const dataDir = process.env.ACTUAL_DATA_DIR || `${process.env.HOME || process.cwd()}/.cache/hermes/actual-budget`;
  await api.init({ dataDir, serverURL: process.env.ACTUAL_SERVER_URL, password: process.env.ACTUAL_PASSWORD });
  try {
    const encryption = process.env.ACTUAL_ENCRYPTION_PASSWORD ? { password: process.env.ACTUAL_ENCRYPTION_PASSWORD } : undefined;
    await api.downloadBudget(process.env.ACTUAL_SYNC_ID, encryption);
    return await fn(api);
  } finally {
    await api.shutdown();
  }
}

function dollars(n) { return n == null ? null : Number(n) / 100; }
function ym(date = new Date()) { return date.toISOString().slice(0, 7); }

withActual(async api => {
  const month = process.env.ACTUAL_MONTH || ym();
  const accounts = await api.getAccounts();
  const balances = [];

  for (const acct of accounts) {
    const balance = await api.getAccountBalance(acct.id);
    balances.push({
      id: acct.id,
      name: acct.name,
      type: acct.type,
      offbudget: !!acct.offbudget,
      closed: !!acct.closed,
      balance_raw: balance,
      balance: dollars(balance),
      balance_current: acct.balance_current == null ? null : dollars(acct.balance_current),
    });
  }

  /**
   * CRITICAL: getBudgetMonth() returns categoryGroups, NOT a flat categories dict.
   * budget.categories is EMPTY. Use budget.categoryGroups[].categories instead.
   * Each category entry in categoryGroups has: id, name, budgeted, spent,
   * balance, carryover, hidden, and is_income.
   */
  const budget = await api.getBudgetMonth(month);
  const categories = await api.getCategories();
  const groups = await api.getCategoryGroups();
  const payees = await api.getPayees();

  // Extract budget category rows from categoryGroups (the actual source of truth)
  const budgetByCatId = {};
  for (const group of (budget.categoryGroups || [])) {
    for (const cat of (group.categories || [])) {
      budgetByCatId[cat.id] = {
        budgeted: cat.budgeted,
        spent: cat.spent,
        balance: cat.balance,
        group: group.name,
      };
    }
  }

  // Use fs.writeFileSync to avoid breadcrumb corruption (see Pitfalls)
  fs.writeFileSync('/tmp/actual_snapshot.json', JSON.stringify({
    month,
    generated_at: new Date().toISOString(),
    accounts: balances,
    categories,
    category_groups: groups,
    category_budgets: budgetByCatId,
    budget_summary: {
      income_available: dollars(budget.incomeAvailable),
      to_budget: dollars(budget.toBudget),
      total_budgeted: dollars(budget.totalBudgeted),
      total_spent: dollars(budget.totalSpent),
      total_balance: dollars(budget.totalBalance),
    },
    payee_count: payees.length,
  }, null, 2));
});
JS
node /tmp/actual_snapshot.cjs
cat /tmp/actual_snapshot.json
```

When summarizing the snapshot:

- Use `budget.categoryGroups` to iterate over groups and their categories. Do NOT access `budget.categories` directly — it is empty. Each group has a `categories` array where each category entry includes `budgeted`, `spent`, and `balance` amounts in integer cents.
- Build a lookup from category ID to budgeted/spent/balance amounts by extracting from `categoryGroups` before doing any spending analysis.

- Separate cash/checking/savings from liabilities.
- Show raw Actual balances if liability sign is unclear.
- Exclude closed accounts unless the user asks for historical analysis.
- Do not assume `api.getAccounts()` includes `type`; some Actual API versions return account names/balances without type metadata.
- If `acct.type` is missing, classify cash/debt using account names plus the debt sidecar, and clearly label classification as inferred.
- Call out missing debt fields that Actual does not inherently store, especially APR and minimum payment.

## Spending Review

Use this to identify categories, payees, subscriptions, and unusual spend.

Important: category-level monthly spending should come from `api.getBudgetMonth(month).categoryGroups[].categories[].spent`, not from summing all negative transactions across all accounts. Summing all negative transactions can double-count credit-card payments, debt transfers, and other account-to-account activity. Use transactions for payee-level review and uncategorized samples.

```bash
cat > /tmp/actual_spending_review.cjs <<'JS'
const api = require('@actual-app/api');

async function withActual(fn) {
  const dataDir = process.env.ACTUAL_DATA_DIR || `${process.env.HOME || process.cwd()}/.cache/hermes/actual-budget`;
  await api.init({ dataDir, serverURL: process.env.ACTUAL_SERVER_URL, password: process.env.ACTUAL_PASSWORD });
  try {
    const encryption = process.env.ACTUAL_ENCRYPTION_PASSWORD ? { password: process.env.ACTUAL_ENCRYPTION_PASSWORD } : undefined;
    await api.downloadBudget(process.env.ACTUAL_SYNC_ID, encryption);
    return await fn(api);
  } finally {
    await api.shutdown();
  }
}

function dollars(n) { return n == null ? null : Number(n) / 100; }
function monthBounds(month) {
  const start = `${month}-01`;
  const end = new Date(`${start}T00:00:00Z`);
  end.setUTCMonth(end.getUTCMonth() + 1);
  end.setUTCDate(0);
  return { start, end: end.toISOString().slice(0, 10) };
}

withActual(async api => {
  const month = process.env.ACTUAL_MONTH || new Date().toISOString().slice(0, 7);
  const { start, end } = monthBounds(month);
  const [accounts, categories, payees, budget] = await Promise.all([
    api.getAccounts(),
    api.getCategories(),
    api.getPayees(),
    api.getBudgetMonth(month),
  ]);

  const categoryById = new Map(categories.map(c => [c.id, c]));
  const payeeById = new Map(payees.map(p => [p.id, p]));
  const txns = [];

  for (const acct of accounts.filter(a => !a.closed)) {
    const rows = await api.getTransactions(acct.id, start, end);
    for (const t of rows) txns.push({ ...t, account_name: acct.name, account_type: acct.type });
  }

  const byCategory = new Map();
  for (const group of budget.categoryGroups || []) {
    for (const cat of group.categories || []) {
      if (cat.hidden || cat.is_income) continue;
      if ((cat.spent || 0) < 0) byCategory.set(cat.name, cat.spent || 0);
    }
  }
  const byPayee = new Map();
  const uncategorized = [];

  for (const t of txns) {
    if (t.amount >= 0) continue; // expense-only summary
    const payeeName = payeeById.get(t.payee)?.name || t.payee_name || t.imported_payee || '(Unknown Payee)';
    byPayee.set(payeeName, (byPayee.get(payeeName) || 0) + t.amount);
    if (!t.category) uncategorized.push(t);
  }

  const sortExpenses = ([, a], [, b]) => Math.abs(b) - Math.abs(a);
  const topCategories = [...byCategory.entries()].sort(sortExpenses).slice(0, 25).map(([name, amount]) => ({ name, amount: dollars(amount) }));
  const topPayees = [...byPayee.entries()].sort(sortExpenses).slice(0, 25).map(([name, amount]) => ({ name, amount: dollars(amount) }));

  console.log(JSON.stringify({
    month,
    date_range: { start, end },
    transaction_count: txns.length,
    top_expense_categories: topCategories,
    top_expense_payees: topPayees,
    uncategorized_count: uncategorized.length,
    uncategorized_sample: uncategorized.slice(0, 25).map(t => ({
      id: t.id,
      date: t.date,
      amount: dollars(t.amount),
      imported_payee: t.imported_payee,
      payee_name: t.payee_name,
      notes: t.notes,
      account_name: t.account_name,
    })),
  }, null, 2));
});
JS
node /tmp/actual_spending_review.cjs
```

Analysis format:

1. What changed materially.
2. Top spending categories/payees.
3. Recurring/subscription candidates.
4. Uncategorized or suspicious items.
5. Cash-flow opportunities to redirect toward debt.
6. Recommended next action, with no more than 3 choices.

## LLM Categorization Review Sidecar

Use this when the user asks Hermes to classify uncategorized transactions with an LLM. Keep Actual Budget read-only during classification unless the user explicitly confirms the proposed category updates.

By default, track LLM suggestions in a local sidecar file instead of adding tags or notes to Actual Budget transactions:

```bash
export ACTUAL_AI_REVIEW_PATH="${ACTUAL_AI_REVIEW_PATH:-$HOME/.hermes/state/actual-llm-review.json}"
```

Recommended sidecar shape:

```json
{
  "version": 1,
  "generated_at": "YYYY-MM-DDTHH:mm:ss.sssZ",
  "budget_month": "YYYY-MM",
  "items": [
    {
      "transaction_id": "actual-transaction-id-placeholder",
      "date": "YYYY-MM-DD",
      "amount_cents": null,
      "imported_payee": "Example Merchant",
      "current_category": null,
      "suggested_category": "Example Category",
      "confidence": "high",
      "reason": "Matched a repeated merchant pattern.",
      "status": "pending"
    }
  ],
  "proposed_categories": [
    {
      "name": "Example Category",
      "group": "Example Group",
      "example_transaction_ids": ["actual-transaction-id-placeholder"],
      "reason": "Existing categories do not clearly fit this repeated spending pattern.",
      "confidence": "medium",
      "status": "pending"
    }
  ]
}
```

Rules:

- In dry-run mode, write or update only the sidecar file; do not mutate Actual Budget.
- Do not add audit tags, notes, or other review markers to Actual Budget unless the user explicitly asks for in-budget markers.
- Use `status` values such as `pending`, `approved`, `rejected`, and `needs_review`.
- Apply category changes only for user-approved sidecar items, then call `api.sync()` and verify the changed transactions.
- If a merchant is repeatedly approved for the same category, propose a narrow Actual Budget rule instead of repeatedly applying one-off changes.
- Let the LLM propose new categories when no existing category fits, but store those proposals in `proposed_categories` with example transactions and a reason.
- Create new categories only after showing the proposed category name, group, affected transactions, and getting explicit confirmation. Category creation must be a separate confirmed write before applying transaction category updates.
- After creating a category, re-read Actual Budget categories to verify it exists before assigning transactions to it.

## Debt Profile Sidecar

Actual accounts can store balances and account type, but debt planning normally requires fields Actual may not store: APR, promo APR, promo expiration, minimum payment, due date, and whether the debt should be included.

Maintain this sidecar outside the budget file unless the user asks for a different location:

```bash
mkdir -p .hermes/state
cat > .hermes/state/actual-debt-profile.example.json <<'JSON'
{
  "currency": "USD",
  "monthly_extra_debt_payment_cents": null,
  "minimum_emergency_cash_cents": null,
  "debts": [
    {
      "account_name": "Example Credit Card",
      "actual_account_id": "optional-uuid-from-actual",
      "include": true,
      "current_balance_cents": null,
      "statement_balance_cents": null,
      "minimum_payment_cents": null,
      "apr": null,
      "promo_apr": null,
      "promo_end_date": null,
      "due_day": null,
      "notes": "Do not guess missing values. Ask user or use statement data."
    }
  ]
}
JSON
```

Rules for the sidecar:

- Prefer Actual's current account balance for `current_balance_cents` only after the user confirms which accounts are debts.
- Use statement balances when planning near a statement due date if the user provides them.
- Never calculate payoff dates without minimum payment and extra payment inputs.
- If APR is missing, still produce a snowball order by balance, but label interest estimates unavailable.
- If promo APR expiration is known, flag deadlines before recommending snowball order blindly.

## Credit Card Debt in Actual Budget

When planning credit-card payoff for carried debt, align recommendations with Actual Budget's carrying-debt workflow: https://actualbudget.org/docs/budgeting/credit-cards/carrying-debt/

Rules:

- Treat carried credit-card debt as distinct from cards that are paid in full within the budget.
- Fund necessary spending categories before recommending extra payoff toward carried debt.
- Use absolute values when interpreting negative credit-card account balances for payoff planning.
- Require statement minimum payment, interest and fees, new purchases, and return credits before calculating payment guidance.
- Track interest and fees as debt-category activity when relevant.
- Do not double-count debt by subtracting both negative card balances and debt-category balances from the same available funds.
- Prefer user-confirmed Actual Budget debt categories for each card carrying debt.
- Keep guidance educational; do not initiate card payments or creditor communications.

## Critical Simulation Pitfall: Active Debt vs Passive Debt

**NEVER** include 0% promotional accounts or the primary mortgage in the active attack pile of a debt payoff simulation. This produces mathematically wrong results — the simulation will waste extra payments on the mortgage or a 0% auto loan before touching high-interest revolving debt.

**Correct approach:**
1. Classify each debt as **active** (interest-bearing, non-mortgage, non-0%) or **passive** (0% promos, mortgage, 0% auto loans).
2. Run the payoff simulation attacking ONLY active debts with the extra payment pool.
3. Pay minimums on passive debts during the active phase.
4. After all active debt clears, roll all freed minimum payments + the extra into the mortgage or passive accounts.

**Example classification:**
- Active: carried-revolving credit cards, unsecured personal loans
- Passive: 0% promotional credit cards, 0% auto loans, primary mortgage

A simulation that attacks all accounts uniformly will put the mortgage ahead of high-APR credit cards. Always filter.

## Debt Snowball / Avalanche Planner

Debt snowball order: smallest balance first while paying minimums on all other debts. Avalanche order: highest APR first while paying minimums on all other debts. Produce both when APRs are known, and state the tradeoff plainly.

Also offer these two additional methods when the user has dual goals (minimize interest AND improve cash flow quickly):

**Cash Flow Index** — prioritize debts by (minimum_payment / original_balance) ratio. Eliminating a debt with a high ratio frees the most monthly cash per dollar invested. Best for users who want rapid monthly cash flow improvement.

**DTI Impact** — prioritize by (balance × weight) where credit cards get weight=2, unsecured loans weight=1, secured debts weight=0.5. Best for users optimizing debt-to-income ratio for refinancing or qualification.

See `[references/payoff-methods.md](references/payoff-methods.md)` for method definitions and cash flow index formulas.

```bash
cat > /tmp/actual_debt_plan.cjs <<'JS'
const fs = require('fs');
const path = require('path');
const api = require('@actual-app/api');

const profilePath = process.env.ACTUAL_DEBT_PROFILE || '.hermes/state/actual-debt-profile.json';
const method = (process.env.DEBT_METHOD || 'snowball').toLowerCase();
const maxMonths = Number(process.env.DEBT_MAX_MONTHS || 360);

async function withActual(fn) {
  const dataDir = process.env.ACTUAL_DATA_DIR || `${process.env.HOME || process.cwd()}/.cache/hermes/actual-budget`;
  await api.init({ dataDir, serverURL: process.env.ACTUAL_SERVER_URL, password: process.env.ACTUAL_PASSWORD });
  try {
    const encryption = process.env.ACTUAL_ENCRYPTION_PASSWORD ? { password: process.env.ACTUAL_ENCRYPTION_PASSWORD } : undefined;
    await api.downloadBudget(process.env.ACTUAL_SYNC_ID, encryption);
    return await fn(api);
  } finally {
    await api.shutdown();
  }
}

function dollars(n) { return n == null ? null : Number(n) / 100; }
function centsFromBalance(balance) { return Math.round(Math.abs(Number(balance || 0))); }
function monthlyRate(apr) { return apr == null ? null : Number(apr) / 100 / 12; }

function sortDebts(debts, orderMethod) {
  const live = debts.filter(d => d.include !== false && d.balance_cents > 0);
  if (orderMethod === 'avalanche') {
    return live.sort((a, b) => (Number(b.apr ?? -1) - Number(a.apr ?? -1)) || (a.balance_cents - b.balance_cents));
  }
  return live.sort((a, b) => (a.balance_cents - b.balance_cents) || (Number(b.apr ?? -1) - Number(a.apr ?? -1)));
}

function effectiveAPR(d, monthOffset) {
  const simDate = new Date();
  simDate.setUTCMonth(simDate.getUTCMonth() + monthOffset);
  if (d.promo_end_date && new Date(d.promo_end_date) < simDate) return d.apr;
  if (typeof d.promo_apr === 'number') return d.promo_apr;
  return d.apr;
}

function simulate(inputDebts, monthlyExtra, orderMethod) {
  // CRITICAL: Split into active targets (interest-bearing, non-mortgage) and passive (min only)
  // Paying mortgage or 0% accounts ahead of 22% credit cards is mathematically wrong.
  const passive = inputDebts.filter(d =>
    d.debt_type === 'mortgage' ||
    (d.apr === 0 && (d.promo_apr == null || d.promo_apr === 0)) ||
    (d.promo_apr === 0 && d.promo_end_date && new Date(d.promo_end_date) > new Date())
  );
  const activeTargets = inputDebts.filter(d => !passive.includes(d));

  const debts = activeTargets.map(d => ({ ...d }));
  const timeline = [];
  let month = 0;
  let totalInterest = 0;

  // Phase 1: Attack active debts, passive pay minimums only
  while (debts.some(d => d.balance_cents > 0) && month < maxMonths) {
    month += 1;

    for (const d of debts) {
      if (d.balance_cents <= 0) continue;
      const r = effectiveAPR(d, month - 1) / 100 / 12;
      if (r > 0) {
        const interest = Math.round(d.balance_cents * r);
        d.balance_cents += interest;
        totalInterest += interest;
      }
    }

    const sorted = sortDebts(debts.filter(d => d.balance_cents > 0), orderMethod);
    let pool = monthlyExtra + sorted.reduce((sum, d) => sum + (d.minimum_payment_cents || 0), 0);

    // Pay minimums on every active debt first.
    for (const target of sorted) {
      if (target.balance_cents <= 0) continue;
      const min = Math.min(target.balance_cents, target.minimum_payment_cents || 0);
      target.balance_cents -= min;
      pool -= min;
    }

    // Then send remaining pool to the current priority debt.
    while (pool > 0) {
      const priority = sorted.find(d => d.balance_cents > 0);
      if (!priority) break;
      const pay = Math.min(priority.balance_cents, pool);
      priority.balance_cents -= pay;
      pool -= pay;
    }

    const newlyPaid = debts.filter(d => d.balance_cents <= 0 && !d.paid_off_month);
    for (const d of newlyPaid) d.paid_off_month = month;

    const clearedMins = debts.filter(d => d.paid_off_month).reduce((s, d) => s + d.minimum_payment_cents, 0);

    timeline.push({
      month,
      remaining_cents: debts.reduce((sum, d) => sum + Math.max(0, d.balance_cents), 0),
      paid_off: newlyPaid.map(d => d.name),
      freed_minimum_cents: clearedMins,
    });
  }

  // Phase 2: Roll all freed cash into mortgage (if present)
  const mortgage = passive.find(d => d.debt_type === 'mortgage');
  if (mortgage) {
    const freedCash = debts.reduce((s, d) => s + d.minimum_payment_cents, 0);
    const mortgagePayment = monthlyExtra + freedCash;
    let mBal = mortgage.balance_cents;
    while (mBal > 0 && month < maxMonths) {
      month += 1;
      mBal += Math.round(mBal * mortgage.apr / 100 / 12);
      mBal -= mortgagePayment;
    }
    mortgage.paid_off_month = month;
  }

  const allDebts = [...debts, ...passive.map(p => ({ ...p, paid_off_month: (p.apr === 0 && !p.promo_apr) ? null : p.paid_off_month }))];

  return {
    method: orderMethod,
    active_clear_month: month,
    months: month,
    total_interest_cents: totalInterest,
    payoff_order: allDebts
      .filter(d => d.paid_off_month || d.apr === 0)
      .sort((a, b) => (a.paid_off_month || 9999) - (b.paid_off_month || 9999))
      .map(d => ({ name: d.name, paid_off_month: d.paid_off_month || null })),
    timeline: timeline.filter(row => row.paid_off.length > 0 || row.month % 6 === 0 || row.remaining_cents === 0),
  };
}

withActual(async api => {
  if (!fs.existsSync(profilePath)) {
    throw new Error(`Debt profile not found: ${profilePath}`);
  }

  const profile = JSON.parse(fs.readFileSync(profilePath, 'utf8'));
  const accounts = await api.getAccounts();
  const accountsById = new Map(accounts.map(a => [a.id, a]));
  const accountsByName = new Map(accounts.map(a => [a.name, a]));

  const debts = [];
  const missing = [];

  for (const d of profile.debts || []) {
    if (d.include === false) continue;
    const acct = d.actual_account_id ? accountsById.get(d.actual_account_id) : accountsByName.get(d.account_name);
    let actualBalance = null;
    if (acct) actualBalance = await api.getAccountBalance(acct.id);

    const balance = d.current_balance_cents != null
      ? centsFromBalance(d.current_balance_cents)
      : actualBalance != null
        ? centsFromBalance(actualBalance)
        : null;

    const name = d.account_name || acct?.name;
    if (!name || balance == null || d.minimum_payment_cents == null) {
      missing.push({
        name: name || '(unnamed debt)',
        needs: {
          balance: balance == null,
          minimum_payment_cents: d.minimum_payment_cents == null,
        },
      });
      continue;
    }

    debts.push({
      name,
      account_id: acct?.id || d.actual_account_id || null,
      balance_cents: balance,
      minimum_payment_cents: centsFromBalance(d.minimum_payment_cents),
      apr: d.apr,
      promo_apr: d.promo_apr,
      promo_end_date: d.promo_end_date,
      due_day: d.due_day,
      debt_type: d.debt_type || null,
      secured: d.secured ?? null,
      notes: d.notes,
    });
  }

  const monthlyExtra = centsFromBalance(profile.monthly_extra_debt_payment_cents || 0);
  const snowballOrder = sortDebts(debts.map(d => ({ ...d })), 'snowball').map((d, i) => ({ rank: i + 1, name: d.name, balance: dollars(d.balance_cents), apr: d.apr, minimum_payment: dollars(d.minimum_payment_cents) }));
  const avalancheOrder = sortDebts(debts.map(d => ({ ...d })), 'avalanche').map((d, i) => ({ rank: i + 1, name: d.name, balance: dollars(d.balance_cents), apr: d.apr, minimum_payment: dollars(d.minimum_payment_cents) }));

  const canSimulate = debts.length > 0 && debts.every(d => d.balance_cents != null && d.minimum_payment_cents != null);
  const snowball = canSimulate ? simulate(debts, monthlyExtra, 'snowball') : null;
  const avalanche = canSimulate && debts.every(d => d.apr != null) ? simulate(debts, monthlyExtra, 'avalanche') : null;

  console.log(JSON.stringify({
    generated_at: new Date().toISOString(),
    monthly_extra_debt_payment: dollars(monthlyExtra),
    missing_inputs: missing,
    debts: debts.map(d => ({ ...d, balance: dollars(d.balance_cents), minimum_payment: dollars(d.minimum_payment_cents) })),
    snowball_order: snowballOrder,
    avalanche_order: avalancheOrder,
    simulations: {
      snowball: snowball && {
        months: snowball.months,
        total_interest: dollars(snowball.total_interest_cents),
        payoff_order: snowball.payoff_order,
        timeline: snowball.timeline.map(t => ({ ...t, remaining: dollars(t.remaining_cents) })),
      },
      avalanche: avalanche && {
        months: avalanche.months,
        total_interest: dollars(avalanche.total_interest_cents),
        payoff_order: avalanche.payoff_order,
        timeline: avalanche.timeline.map(t => ({ ...t, remaining: dollars(t.remaining_cents) })),
      },
    },
    selected_method: method,
  }, null, 2));
});
JS
node /tmp/actual_debt_plan.cjs
```

When presenting the debt plan:

- Lead with the recommended next debt target.
- Show required minimum-payment total and extra-payment amount.
- Include a warning if promotional APRs expire before estimated payoff.
- Compare snowball vs avalanche only when APR inputs are available.
- Use snowball when the user prioritizes motivation and quick wins.
- Use avalanche when the user prioritizes least interest and has enough discipline to sustain it.
- Do not recommend liquidating retirement accounts, home equity, or investments without explicitly labeling the risk and recommending professional review.

## Budget Adjustment Workflow

Use this when the user asks to change category budgets, create a debt-payment envelope, or redirect money from discretionary categories.

Read first:

```js
const month = process.env.ACTUAL_MONTH || new Date().toISOString().slice(0, 7);
const budget = await api.getBudgetMonth(month);
const categories = await api.getCategories();
```

Propose before writing:

```text
Proposed Actual Budget changes:
- Month: YYYY-MM
- Category: Debt Paydown
- Old budget amount: $X
- New budget amount: $Y
- Source category reduction(s): ...
- Net change: $0 / $X
Confirm before I apply these changes.
```

Write only after explicit confirmation, and keep the script dry-run by default. Set `ACTUAL_APPLY=true` only after the user confirms the proposed changes:

```bash
cat > /tmp/actual_set_budget_amount.cjs <<'JS'
const api = require('@actual-app/api');

async function withActual(fn) {
  const dataDir = process.env.ACTUAL_DATA_DIR || `${process.env.HOME || process.cwd()}/.cache/hermes/actual-budget`;
  await api.init({ dataDir, serverURL: process.env.ACTUAL_SERVER_URL, password: process.env.ACTUAL_PASSWORD });
  try {
    const encryption = process.env.ACTUAL_ENCRYPTION_PASSWORD ? { password: process.env.ACTUAL_ENCRYPTION_PASSWORD } : undefined;
    await api.downloadBudget(process.env.ACTUAL_SYNC_ID, encryption);
    return await fn(api);
  } finally {
    await api.shutdown();
  }
}

withActual(async api => {
  const month = process.env.ACTUAL_MONTH;
  const categoryName = process.env.ACTUAL_CATEGORY_NAME;
  const amount = Number(process.env.ACTUAL_BUDGET_AMOUNT);
  const apply = process.env.ACTUAL_APPLY === 'true';

  if (!month || !categoryName || Number.isNaN(amount)) {
    throw new Error('Require ACTUAL_MONTH, ACTUAL_CATEGORY_NAME, and ACTUAL_BUDGET_AMOUNT');
  }

  const categoryId = await api.getIDByName('categories', categoryName);
  const amountInt = api.utils.amountToInteger(amount);
  if (!apply) {
    console.log(JSON.stringify({ dry_run: true, would_update: { month, categoryName, amount } }, null, 2));
    return;
  }

  await api.setBudgetAmount(month, categoryId, amountInt);
  await api.sync();
  console.log(JSON.stringify({ updated: true, month, categoryName, amount }, null, 2));
});
JS
ACTUAL_MONTH="YYYY-MM" ACTUAL_CATEGORY_NAME="Debt Paydown" ACTUAL_BUDGET_AMOUNT="0.00" node /tmp/actual_set_budget_amount.cjs
# After explicit user confirmation:
ACTUAL_APPLY=true ACTUAL_MONTH="YYYY-MM" ACTUAL_CATEGORY_NAME="Debt Paydown" ACTUAL_BUDGET_AMOUNT="0.00" node /tmp/actual_set_budget_amount.cjs
```

## Transaction Import / Update Rules

Use `importTransactions` for normal transaction imports because it runs rules and deduplicates imported transactions. Use `addTransactions` only when intentionally importing raw historical data and the user understands that duplicate avoidance and normal post-processing are skipped.

Never modify `transfer_id` on existing transfers.

For rules:

- Read existing rules first.
- Prefer narrow payee/category rules.
- Create a rule only after showing the condition and action.
- Avoid broad rules like “contains CARD” or “amount greater than 0” unless the user explicitly wants them.

Example create-rule workflow. First show the dry-run payload, then set `ACTUAL_APPLY=true` only after explicit confirmation:

```js
const payeeId = await api.getIDByName('payees', 'Netflix');
const categoryId = await api.getIDByName('categories', 'Subscriptions');
const rule = {
  stage: 'pre',
  conditionsOp: 'and',
  conditions: [{ field: 'payee', op: 'is', value: payeeId }],
  actions: [{ op: 'set', field: 'category', value: categoryId }],
};

if (process.env.ACTUAL_APPLY !== 'true') {
  console.log(JSON.stringify({ dry_run: true, would_create_rule: rule }, null, 2));
  return;
}

await api.createRule(rule);
await api.sync();
```

## Financial Planner-Style Review Checklist

Use this checklist when the user asks for a broader financial plan:

1. **Goal definition**: debt elimination, cash buffer, monthly surplus, purchase planning, retirement/investing, or all of the above.
2. **Data inventory**: accounts, balances, monthly income, fixed expenses, variable expenses, debt APRs, minimum payments, due dates, promo dates.
3. **Cash-flow baseline**: income minus required monthly expenses, minimum debt payments, and recurring subscriptions.
4. **Risk buffer**: minimum emergency cash target before aggressive extra debt payment.
5. **Debt strategy**: snowball, avalanche, or hybrid.
6. **Budget implementation**: categories/envelopes and planned transfer or payment tracking.
7. **Monitoring cadence**: weekly transaction cleanup, monthly category adjustment, statement-date debt update.
8. **Escalation**: recommend a qualified professional for tax, legal, bankruptcy, investment liquidation, retirement account withdrawal, or insolvency questions.

## Debt Strategy Decision Rules

Use these defaults unless the user specifies otherwise:

- If the user feels overwhelmed, has many small debts, or needs motivation: recommend **snowball**.
- If the user has very high APR debt or expiring promo APR: recommend **hybrid** — urgent promo/high APR risk first, then snowball.
- If the user wants the mathematically lowest interest and has stable cash flow: recommend **avalanche**.
- If any debt is past due: prioritize becoming current before extra snowball payments.
- If cash buffer is below the user's minimum emergency threshold: recommend splitting extra cash between buffer and debt until the floor is reached.
- If a 0% APR auto/mortgage loan competes with high-interest revolving debt: do not accelerate the 0% loan unless the user explicitly values payment elimination over interest savings.

## Output Templates

### Budget Snapshot

```text
## Actual Budget Snapshot — YYYY-MM

### Cash / Liquid Accounts
| Account | Type | Balance |
|---|---:|---:|

### Debt / Liability Candidates
| Account | Type | Actual Balance | Include in payoff plan? |
|---|---:|---:|---:|

### Monthly Budget Observations
- Income available:
- Overspent categories:
- Categories with available cash:
- Uncategorized transaction count:

### Next Action
1. ...
```

### Debt Snowball Plan

```text
## Debt Payoff Plan

Method: Snowball / Avalanche / Hybrid
Monthly extra debt payment: $X
Minimum payments total: $Y
Estimated payoff: N months
Estimated interest: $Z / unavailable because APR is missing

### Priority Order
| Rank | Debt | Balance | APR | Minimum | Notes |
|---:|---|---:|---:|---:|---|

### Next Payment Instruction
Pay minimums on all debts. Send the extra $X to: [Debt Name].

### Missing Inputs
- ...

### Risks / Watch Items
- Promo APR expiration:
- Due date risk:
- Emergency cash floor:
```

### Proposed Write Confirmation

```text
I can apply this to Actual Budget after confirmation:

| Change | Month | Target | Old | New |
|---|---|---|---:|---:|

No payments will be sent. This only updates Actual Budget records.
```

## Verification

After any read operation:

- Confirm budget month and timestamp.
- Confirm number of accounts/transactions reviewed.
- Identify missing fields.

After any write operation:

- Call `api.sync()`.
- Re-read the changed account/category/rule.
- Show before/after values.
- State that Actual Budget was updated, but no external bank/lender action occurred.

## Hermes-Specific Terminal Tips

When running scripts from Hermes's terminal tool:
- **Always write Node.js to a `.cjs` file first**, then execute it. Inline `-e` scripts with `@actual-app/api` regularly time out because `downloadBudget()` and `sync()` need extra seconds to fetch and sync data from the server — the terminal's timeout limit may fire before the async work completes.
- Use a generous `timeout` (60–120s) on `terminal` calls that run actual-budget scripts.
- API breadcrumbs (sync messages) can go to stdout and stderr. Do not parse JSON from stdout directly. Write JSON to a file with `fs.writeFileSync('/tmp/result.json', JSON.stringify(data))`, print only a small completion marker, then read the JSON file.
- Always call `api.shutdown()` in a `finally` block to release the in-memory database lock, even on errors.

## Due Date Inference

Actual Budget does not store due dates natively. When the sidecar's `due_day` is null or stale, infer it from transaction history rather than guessing. See `references/due-date-inference.md` for generic worked examples.

1. Pull 6+ months of transactions for each debt account.
2. Filter for inbound (positive amount) transactions — these are payments made TO the account.
3. Count the distribution of calendar days (`new Date(t.date).getDate()`).
4. The most frequent day is the inferred due date (or payment day, which typically aligns with or slightly precedes the due date).

```js
const payments = txns.filter(t => t.amount > 0).map(t => t.date.slice(8, 10)); // day of month
const dayCounts = {};
payments.forEach(d => { dayCounts[d] = (dayCounts[d] || 0) + 1; });
const sortedDays = Object.entries(dayCounts).sort((a, b) => b[1] - a[1]);
const inferredDueDay = sortedDays[0][0]; // most frequent payment day
```

**Edge cases:**
- Zero payment transactions (e.g., user pays outside of tracked accounts): ask the user directly.
- Multiple consistent payment days: the earliest one is likely the due date, later ones are catch-up payments.
- Payments on variable days across months: the account likely has a statement-cycle due date rather than a fixed calendar day.

## Common Pitfalls

- Actual Budget automation is via `@actual-app/api`, not a REST API.
- Terminal timeout gotchas: **always write Node.js to a `.cjs` file first**, *not inline with `\ -e`*. The `downloadBudget()` fetch + `sync()` roundtrip easily exceeds inline timeouts. Execute via `node /path/to/script.cjs`.
- Amounts are integer minor units. Do not write decimal dollar amounts directly to `setBudgetAmount`, transactions, or balances.
- `importTransactions` deduplicates and runs rules; `addTransactions` does not.
- Existing transfer `transfer_id` values should not be changed.
- Account `type` is metadata and may not fully indicate whether the account should be treated as debt.
- APR, minimum payment, and due date usually require user-provided data or a sidecar profile.
- Do not over-optimize a payoff plan if the budget has uncategorized transactions or stale balances.
- **Never use `node -e "..."` for Actual Budget scripts** — inline eval scripts consistently timeout on this host. Always write the script to a `/tmp/` file and execute it with `node /tmp/script.cjs`.
- **Always set `ACTUAL_DATA_DIR`** even if the default works — explicit paths prevent stale cache conflicts when multiple sessions run the API.
- **Handle zero-payment accounts gracefully** — not all debt accounts will have payment history (user may pay externally). Do not crash on `sortedDays[0]` being undefined; log "NO payment transactions found" and flag for user input.
- **Breadcrumb contamination**: `@actual-app/api` writes sync breadcrumbs to BOTH stdout and stderr (not just stderr). If your script writes JSON to stdout, the breadcrumbs will corrupt the JSON. **Fix**: use `fs.writeFileSync('/tmp/result.json', JSON.stringify(data))` in the Node script and read the file from Python instead of parsing stdout. Example pattern:

```js
// In your .cjs script — do NOT console.log(JSON.stringify(result))
fs.writeFileSync('/tmp/actual_result.json', JSON.stringify(result, null, 2));
process.stdout.write('DONE\n');
```

Then in Python:

```python
result = subprocess.run(["node", "/tmp/script.cjs"], capture_output=True, text=True, env=env)
with open("/tmp/actual_result.json") as f:
    data = json.load(f)
```

- **Credential exposure blocking**: Passing `ACTUAL_PASSWORD` as a command-line argument can trigger terminal block ("BLOCKED: User denied"). Always pass credentials via the subprocess `env=` dict (Python) or by sourcing from an env file, never as a CLI flag or inline `-e` argument.
- **Create ACTUAL_DATA_DIR before running**: The API will error with `ENOENT: no such file or directory, scandir` if the data directory doesn't exist. Always `os.makedirs(ACTUAL_DATA_DIR, exist_ok=True)` before invoking the Node script.
- **`getBudgetMonth()` returns `categoryGroups`, NOT `categories`**: The `budget.categories` property is **empty** (0 keys). Monthly category data lives in `budget.categoryGroups[].categories[]`. Category rows use `budgeted`, `spent`, and `balance`, not `assigned`. Iterating `budget.categories` produces silently empty cash-flow results. Always extract from `categoryGroups`:
```js
const budgetByCatId = {};
for (const group of (budget.categoryGroups || [])) {
  for (const cat of (group.categories || [])) {
    budgetByCatId[cat.id] = { budgeted: cat.budgeted, spent: cat.spent, balance: cat.balance, group: group.name };
  }
}
```
The `Budget Adjustment Workflow` section's `api.getBudgetMonth().categories` usage is WRONG for reading — use `categoryGroups` instead. Only `api.setBudgetAmount()` writes (and that works correctly).
- **`getAccountBalance()` may diverge from `acct.balance_current`**: `getBalance()` returns the *cleared* balance (excluding pending), while `balance_current` includes pending transactions. For liabilities with significant pending activity they can differ. Always read BOTH and report both in snapshots. Use `getAccountBalance()` for the authoritative "what would pay off now" figure.
- **`acct.type` key may be missing**: Some actual account objects returned by `getAccounts()` omit the `type` field. Fall back to inferring account type from the account `name` (e.g., contains "CHECKING", "SAVINGS", "MORTGAGE", "Loan", "Card") rather than assuming `type` will always be present.
