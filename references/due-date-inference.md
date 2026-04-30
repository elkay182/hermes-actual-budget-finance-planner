# Due Date Inference from Actual Budget Transaction History

Actual Budget does not store due dates natively. Due dates should live in the debt profile sidecar. When due dates are missing or stale, infer them from payment transaction patterns, then ask the user to verify before writing anything back to Actual Budget or a sidecar.

## Method

1. Query a 6–8 month window of transactions for each user-confirmed debt account.
2. Filter for positive-amount transactions, which are payments made **to** the account in Actual Budget's liability-account convention.
3. Build a histogram of day-of-month values.
4. Treat the mode as the likely payment day, not necessarily the contractual due date.
5. If the inferred day differs by 1–2 days from user-provided data, prefer the user-provided statement due date.
6. If there is no payment history, ask the user for the due date or statement data.

## Generic Script Pattern

```js
const txns = await api.getTransactions(acctId, 'YYYY-MM-DD', 'YYYY-MM-DD');
const payments = txns.filter(t => t.amount > 0);
const dayCounts = {};

for (const payment of payments) {
  const day = payment.date.slice(8, 10);
  dayCounts[day] = (dayCounts[day] || 0) + 1;
}

const sortedDays = Object.entries(dayCounts).sort((a, b) => b[1] - a[1]);
const inferredPaymentDay = sortedDays.length ? Number(sortedDays[0][0]) : null;
```

## Placeholder Example

| Account | Inferred payment day | User-confirmed due day | Action |
|---|---:|---:|---|
| Example Credit Card A | 8 | 9 | Keep user-confirmed due day 9 |
| Example Loan B | 12 | null | Ask user to confirm before updating sidecar |
| Example Card C | null | null | No payment history; ask user or inspect statement |

## Known Edges

- **Payment day vs due date:** users often pay 1–2 days before the actual due date. Label the histogram result as a payment day until verified.
- **Externally paid accounts:** accounts paid outside the tracked budget may have no positive payment transactions.
- **Multiple peaks:** use the dominant peak only as evidence; ask the user when the pattern is ambiguous.
- **Writes:** due-date updates to the debt sidecar or Actual Budget notes must be dry-run by default and require explicit user confirmation.
