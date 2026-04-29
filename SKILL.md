---
name: actual-budget-finance-planner
description: Use Actual Budget's official Node.js API to analyze budgets, cash flow, spending, account balances, and debt payoff plans. Use for personal finance checkups, debt snowball planning, budget category adjustments, transaction review, and safe user-confirmed Actual Budget updates.
version: 1.0.0
author: Tony M. / ChatGPT
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
8. Prefer debt elimination, emergency cash protection, and recurring-expense clarity over aggressive optimization.
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
export ACTUAL_PASSWORD="..."
export ACTUAL_SYNC_ID="..."
export ACTUAL_DATA_DIR="${ACTUAL_DATA_DIR:-$HOME/.cache/hermes/actual-budget}"
# Optional, only if the Actual budget file has end-to-end encryption enabled:
export ACTUAL_ENCRYPTION_PASSWORD="..."
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

Actual stores currency amounts as integers with no decimal places. In USD-style currencies, `$120.30` is represented as `12030`. Dates are `YYYY-MM-DD`; months are `YYYY-MM`.

## Read-Only Financial Snapshot

Use this first for most finance questions.

```bash
cat > /tmp/actual_snapshot.cjs <<'JS'
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

  const budget = await api.getBudgetMonth(month);
  const categories = await api.getCategories();
  const groups = await api.getCategoryGroups();
  const payees = await api.getPayees();

  console.log(JSON.stringify({
    month,
    generated_at: new Date().toISOString(),
    accounts: balances,
    categories,
    category_groups: groups,
    payee_count: payees.length,
    budget_month: budget,
  }, null, 2));
});
JS
node /tmp/actual_snapshot.cjs > /tmp/actual_snapshot.json
cat /tmp/actual_snapshot.json
```

When summarizing the snapshot:

- Separate cash/checking/savings from liabilities.
- Show raw Actual balances if liability sign is unclear.
- Exclude closed accounts unless the user asks for historical analysis.
- Do not assume an account is a debt solely from its name; prefer `type` values such as `credit`, `debt`, or `mortgage`, then ask the user to verify.
- Call out missing debt fields that Actual does not inherently store, especially APR and minimum payment.

## Spending Review

Use this to identify categories, payees, subscriptions, and unusual spend.

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
  const [accounts, categories, payees] = await Promise.all([
    api.getAccounts(),
    api.getCategories(),
    api.getPayees(),
  ]);

  const categoryById = new Map(categories.map(c => [c.id, c]));
  const payeeById = new Map(payees.map(p => [p.id, p]));
  const txns = [];

  for (const acct of accounts.filter(a => !a.closed)) {
    const rows = await api.getTransactions(acct.id, start, end);
    for (const t of rows) txns.push({ ...t, account_name: acct.name, account_type: acct.type });
  }

  const byCategory = new Map();
  const byPayee = new Map();
  const uncategorized = [];

  for (const t of txns) {
    if (t.amount >= 0) continue; // expense-only summary
    const categoryName = categoryById.get(t.category)?.name || '(Uncategorized)';
    const payeeName = payeeById.get(t.payee)?.name || t.payee_name || t.imported_payee || '(Unknown Payee)';
    byCategory.set(categoryName, (byCategory.get(categoryName) || 0) + t.amount);
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

## Debt Profile Sidecar

Actual accounts can store balances and account type, but debt planning normally requires fields Actual may not store: APR, promo APR, promo expiration, minimum payment, due date, and whether the debt should be included.

Maintain this sidecar outside the budget file unless the user asks for a different location:

```bash
mkdir -p .hermes/state
cat > .hermes/state/actual-debt-profile.example.json <<'JSON'
{
  "currency": "USD",
  "monthly_extra_debt_payment_cents": 0,
  "minimum_emergency_cash_cents": 100000,
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

## Debt Snowball / Avalanche Planner

Debt snowball order: smallest balance first while paying minimums on all other debts. Avalanche order: highest APR first while paying minimums on all other debts. Produce both when APRs are known, and state the tradeoff plainly.

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

function simulate(inputDebts, monthlyExtra, orderMethod) {
  const debts = inputDebts.map(d => ({ ...d }));
  const timeline = [];
  let month = 0;
  let totalInterest = 0;

  while (debts.some(d => d.balance_cents > 0) && month < maxMonths) {
    month += 1;

    for (const d of debts) {
      if (d.balance_cents <= 0) continue;
      const r = monthlyRate(d.apr);
      if (r != null && r > 0) {
        const interest = Math.round(d.balance_cents * r);
        d.balance_cents += interest;
        totalInterest += interest;
      }
    }

    const active = sortDebts(debts, orderMethod);
    let pool = monthlyExtra + debts.reduce((sum, d) => sum + (d.balance_cents > 0 ? d.minimum_payment_cents : d.minimum_payment_cents || 0), 0);
    const paidThisMonth = [];

    for (const target of active) {
      if (pool <= 0) break;
      const min = target.minimum_payment_cents || 0;
      let pay = Math.min(target.balance_cents, min);
      target.balance_cents -= pay;
      pool -= pay;
      paidThisMonth.push({ name: target.name, payment_cents: pay, priority: false });
    }

    while (pool > 0) {
      const priority = sortDebts(debts, orderMethod)[0];
      if (!priority) break;
      const pay = Math.min(priority.balance_cents, pool);
      priority.balance_cents -= pay;
      pool -= pay;
      paidThisMonth.push({ name: priority.name, payment_cents: pay, priority: true });
    }

    const newlyPaid = debts.filter(d => d.balance_cents === 0 && !d.paid_off_month);
    for (const d of newlyPaid) d.paid_off_month = month;

    timeline.push({
      month,
      remaining_cents: debts.reduce((sum, d) => sum + Math.max(0, d.balance_cents), 0),
      paid_off: newlyPaid.map(d => d.name),
    });
  }

  return {
    method: orderMethod,
    months: month,
    total_interest_cents: totalInterest,
    payoff_order: debts
      .slice()
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
    const result = await fn(api);
    await api.sync();
    return result;
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

## Common Pitfalls

- Actual Budget automation is via `@actual-app/api`, not a REST API.
- Amounts are integer minor units. Do not write decimal dollar amounts directly to `setBudgetAmount`, transactions, or balances.
- `importTransactions` deduplicates and runs rules; `addTransactions` does not.
- Existing transfer `transfer_id` values should not be changed.
- Account `type` is metadata and may not fully indicate whether the account should be treated as debt.
- APR, minimum payment, and due date usually require user-provided data or a sidecar profile.
- Do not over-optimize a payoff plan if the budget has uncategorized transactions or stale balances.
