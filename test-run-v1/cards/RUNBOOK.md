# ccguard runbook, team `dev`, account 537997492026

## What each alarm email means

| Email | Meaning | Do |
|---|---|---|
| `ccguard-dev-monthly` 50% actual | Half the $100/mo cap is spent (gross, pre-credit) | Awareness only |
| `ccguard-dev-monthly` 80% actual | $80 of $100 spent | Review usage; warn the team |
| `ccguard-dev-monthly` 100% forecasted | Trajectory says the cap will be exceeded this month | Slow down or raise the cap deliberately |
| `ccguard-dev-daily` 100% actual | More than $10 spent in one UTC day | Check for a runaway loop or oversized context |
| Budget action executed | The cutoff FIRED: `ccguard-dev-frozen` is now attached to `ccguard-dev-devs` | See "Frozen" below |

## The one view that shows true burn under credits

Cost Explorer → filter **Charge type = Usage** (and Billing entity = AWS Marketplace
for the Claude lane). Credited accounts show $0 in default views while real
consumption accumulates; this view shows gross spend at time of usage.
All ccguard budgets measure UNBLENDED cost for the same reason.

## What "frozen" looks like, and who can unfreeze

Frozen = every Bedrock call from a dev identity returns `AccessDeniedException`
(explicit Deny overrides every Allow). Unfreeze (admin only):

```bash
aws budgets execute-budget-action --account-id 537997492026 \
  --budget-name ccguard-dev-monthly \
  --action-id aae620d8-3881-4257-aab3-15062e50a83f \
  --execution-type REVERSE_BUDGET_ACTION
# then re-arm:
aws budgets execute-budget-action --account-id 537997492026 \
  --budget-name ccguard-dev-monthly \
  --action-id aae620d8-3881-4257-aab3-15062e50a83f \
  --execution-type RESET_BUDGET_ACTION
```

Review the cap with the team lead before unfreezing.

## Timing caveats (honest latencies)

- **Budget times are UTC.** The "day" for the daily tripwire is the UTC day.
- **Billing data lags hours.** Budget data refreshes up to 3x/day (typically
  8-12h between updates). The cutoff is NOT real-time; a runaway can spend past
  the cap before the action fires. The optional CloudWatch token alarm
  (not deployed; offered in section 5 of the deployment prompt) is the
  minutes-grade layer if you want it later.
- **Cost Anomaly Detection is blind to this lane** (third-party Marketplace
  products). Never rely on it for Claude spend; AWS Budgets is the spine.

## Attribution granularity

Application inference profiles attribute DOLLARS PER DAY per team (after the
daily billing cycle; cost-allocation tags take up to 24h to surface, 12-month
backfill available). Per-developer attribution uses IAM principal tracking in
Cost and Usage Reports, not one profile per person.

## Pending items (new-account verification hold)

1. **Account verification hold**: `bedrock-runtime converse` currently returns
   `Operation not allowed`. Clears within ~2 days of signup; contact AWS
   Support if it persists.
2. **Run the Verification Gate (G1-G5)** once the hold clears. The deployment
   is BUILT, PENDING VERIFICATION until the gate passes. A control that has
   never fired is a decoration, not a control.
3. **Activate cost allocation tags** once the keys surface in billing:

   ```bash
   aws ce update-cost-allocation-tags-status \
     --cost-allocation-tags-status Status=Active,TagKey=team Status=Active,TagKey=managed-by
   ```
4. Schedule a quarterly G3/G4 re-drill after first verification.
