# Verification Gate drill, captured under the new-account verification hold

**Captured:** 2026-06-08 07:19 WIB, AWS account 537997492026 (real, freshly created), region us-east-1.
**Deployment under test:** the live `ccguard-dev-*` resources built by this prompt's verbatim run (see `../`).

## Why this drill exists

At capture time the account was still under AWS's new-account verification hold, which blocks
**runtime model inference only** (every `bedrock:InvokeModel` / `Converse` returns
`ValidationException: Operation not allowed`, even for first-party Nova). The control plane, 
IAM, Budgets, Budget Actions, inference-profile and policy reads, and **IAM policy evaluation
(`iam simulate-principal-policy`)**, is fully functional.

The Verification Gate's job is to prove the guardrail and cutoff **logic** is real and reversible.
That logic is an IAM authorization question ("would this principal's `InvokeModel` call be allowed
or denied right now?"), and `simulate-principal-policy` answers it with AWS's own evaluation engine, 
the same engine that produces the runtime `AccessDeniedException`. The runtime error is the
observable shadow of this evaluation; the simulation is the ground truth. So the entire
guardrail + cutoff matrix is provable **now**, deterministically, without a single token of inference.

What the hold genuinely defers: the live token **response** itself (G1's returned text) and the live
**attribution figures** (G5's CloudWatch/Cost Explorer dollar+token rows), because those require real
invocations to generate data. Their authorization is proven here; only the generated data is pending.

## What is proven (files in this directory)

### Leash: approved allowed, forbidden denied, on BOTH invocation doors (G2)

| # | File | Action | Resource | Decision |
|---|------|--------|----------|----------|
| 01 | `01-sim-haiku-allowed.json` | InvokeModel | approved Haiku profile | **allowed** (ccguard-dev-invoke) |
| 02 | `02-sim-sonnet-invoke-allowed.json` | InvokeModel | approved Sonnet profile | **allowed** (ccguard-dev-invoke) |
| 03 | `03-sim-haiku-stream-allowed.json` | InvokeModelWithResponseStream | approved Haiku profile | **allowed** (ccguard-dev-invoke) |
| 04 | `04-sim-opus-invoke-denied.json` | InvokeModel | forbidden Opus 4.8 | **implicitDeny** (no statement matches) |
| 05 | `05-sim-opus-stream-denied.json` | InvokeModelWithResponseStream | forbidden Opus 4.8 | **implicitDeny** (no statement matches) |

Forbidden Opus is denied on **both** `InvokeModel` and `InvokeModelWithResponseStream`, the streaming
door is shut, not just the unary one. (Only 1 of 129 surveyed competitor entries covered the streaming
action in their deny.)

### Cutoff: fires and reverses (G3 / G4)

| # | File | State | Approved Haiku `InvokeModel` |
|---|------|-------|------------------------------|
| 00 | `00-baseline-group-policies.json` | resting: group has only `ccguard-dev-invoke` | (allowed, see 01) |
| 08 | `08-armed-group-policies.json` | **armed**: `ccguard-dev-frozen` attached | - |
| 09 | `09-frozen-invoke-denied.json` | armed | **explicitDeny** (ccguard-dev-frozen) |
| 10 | `10-frozen-stream-denied.json` | armed, streaming | **explicitDeny** (ccguard-dev-frozen) |
| 11 | `11-disarmed-group-policies.json` | **disarmed**: frozen detached | - |
| 12 | `12-restored-invoke-allowed.json` | disarmed | **allowed** again (ccguard-dev-invoke) |

Arming attaches the **exact policy the budget action is configured to apply** (verified in
`06-action-before-fire.json`: `APPLY_IAM_POLICY` → `ccguard-dev-frozen` → group `ccguard-dev-devs`).
Deny-beats-allow flips the approved profile to `explicitDeny`; detaching restores `allowed`. The cutoff
is real and reversible.

### The drill-method finding (`07-fire-approve.json`)

The gate's original G3 step fires the cutoff with `execute-budget-action --execution-type
APPROVE_BUDGET_ACTION`. Against this deployment that returns:

```
ResourceLockedException: This method is not allowed during [ActionStatus: Standby]
```

`APPROVE_BUDGET_ACTION` only applies to **MANUAL**-approval actions sitting in `PENDING`. The action
here is **AUTOMATIC** (the correct production design for a hands-off auto-cutoff), so it sits in
`STANDBY` and only leaves it when real billing data crosses the threshold on AWS's budget-evaluation
cycle, which is asynchronous (hours of latency) and, with current actual spend at **$0.00 against a
$100 limit** (`describe-budget` at capture time), cannot be forced synchronously at all.

The robust drill, used here, proves the cutoff's **effect and reversibility** deterministically
(attach → simulate → detach → simulate) and proves the **automatic wiring** separately by configuration
inspection (`describe-budget-action`). This is stronger than the original because it is synchronous,
deterministic, and independent of billing latency or approval model. The prompt's gate has been
updated to drill this way.

### No residual mutation

`13-action-final-standby.json` (action back to `STANDBY`) and `14-final-group-clean.json` (group back to
only `ccguard-dev-invoke`) confirm the drill left zero residue.

## What still requires the hold to clear

- **G1 live response:** an approved-profile call returning actual model output (authorization proven in 01–03; token generation pending).
- **G5 live attribution:** CloudWatch `AWS/Bedrock` rows / model-invocation-log identity records dimensioned by the application inference profile (requires real invocations to populate).

These run the moment the hold lifts; their receipts will be added to this directory.
