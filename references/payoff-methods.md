# Payoff Method Definitions

Beyond snowball and avalanche, the user may request comparison across multiple payoff strategies. Use these definitions when building simulations.

## 1. Snowball (Smallest Balance First)

- **Sort:** `balance ascending`
- **Strength:** Fastest first wins, freeing minimum payments early
- **Weakness:** Pays more total interest than avalanche
- **Best for:** Users who need psychological momentum and quick cash flow improvement

## 2. Avalanche (Highest APR First)

- **Sort:** `effective APR descending` (account for promo transitions)
- **Strength:** Minimizes total interest paid
- **Weakness:** First free-up takes longest (largest/highest-APR debts take longer)
- **Best for:** Users who want to save the most money and have discipline to sustain

### Avalanche with Promo Transitions

When debts have time-limited promos, recalculate effective APR each simulation month:

```js
function effectiveAPR(debt, simMonthOffset) {
  let simDate = new Date(now);
  simDate.setUTCMonth(simDate.getUTCMonth() + simMonthOffset);
  if (debt.promo_end && simDate < debt.promo_end) return debt.promo_apr || 0;
  return debt.apr;
}
```

Re-sort each month based on the current effective APR, not just the static APR.

## 3. Cash Flow Index (Max Payment Freed Per Dollar)

- **Sort:** `minimum_payment / original_balance descending`
- **What it measures:** Eliminating a $8,000 debt with a $814/mo minimum (10.3% ratio) frees drastically more monthly cash per dollar than eliminating a $3,800 debt with a $40/mo minimum (1.0% ratio).
- **Strength:** Maximizes monthly cash flow improvement fastest when you count FREED minimums, not just "debt gone"
- **Weakness:** Ignores APR entirely — can overpay interest on high-APR low-ratio debts
- **Best for:** Users whose primary bottleneck is monthly cash flow, not total interest

## 4. DTI Impact (Debt-to-Income Optimization)

- **Sort:** `balance * weight descending` where weight: credit_card=2, unsecured=1, secured=0.5
- **Rationale:** Lenders view revolving credit utilization as the strongest DTI signal. Clearing credit card balances has outsized impact on DTI ratio for refinancing or qualification.
- **Strength:** Fastest path to DTI ratio improvement and credit utilization < 10%
- **Weakness:** Can overpay interest if lower-APR credit cards are attacked while higher-APR personal loans wait
- **Best for:** Users preparing to refinance mortgage, qualify for new loan, or reset credit utilization

## Comparison Template

When presenting results, include:
1. Months until active debt cleared
2. Total interest on active debt
3. First credit card eliminated (month #)
4. Cash flow milestones (how many payments freed per month)
5. Mortgage clearance date (if including passive debts in phase 2)
