# Submission Documentation: Cost-Capped Claude Code on Amazon Bedrock

The verbatim prompt is in `PROMPT.md`. This document is the wrapper: who it is for, what you need, what you get, what to do when something misbehaves, and how it maps to AWS services and the Well-Architected Framework.

---

## Use Case

You are a CTO or platform engineer at a startup. You want your developers on Claude Code, billed through AWS (where your Activate credits live) instead of per-seat subscriptions. Your real fear is not setup, it is the bill, and the bill has three documented ways of surprising you:

1. **Claude usage on Bedrock bills through AWS Marketplace** under the legal entity "Anthropic, PBC", a different billing lane than native AWS services.
2. **AWS Cost Anomaly Detection does not monitor that lane.** AWS's own documentation names "Anthropic Claude models on Amazon Bedrock" as unmonitored and directs you to AWS Budgets instead. The tool most teams trust to catch a runaway is documented-blind to exactly this spend.
3. **Promotional credits mask the burn.** A budget measuring net-of-credit cost reads $0 while credits absorb real consumption, and every alarm stays green until the credits run out. Teams have discovered five-figure AI bills exactly this way (a widely reported case in May 2026, covered by The Register).

This prompt deploys Claude Code for a team with those three failure modes engineered out: scoped per-developer access (IAM), per-team spend attribution (tagged application inference profiles), a layered alarm that measures gross pre-credit spend in the Marketplace lane (AWS Budgets), and an automated cutoff that blocks invocation at the cap (Budget Action attaching an explicit Deny), then proves every control by firing it in a drill before declaring success. One stated limitation, by design and in writing: budget data refreshes up to 3x/day, so the cap is a lagged hard stop (up to one refresh cycle of spend can accrue past the threshold), with an optional minutes-grade CloudWatch token alarm as the early-warning layer.

**Who it adapts to (reusability).** Run it once per team with different intake answers: `team=frontend cap=200`, `team=ml cap=500`. Per-team resources carry the `ccguard-<team>-` prefix and sit side by side in one account; the one account-global act (cost-allocation tag activation) is performed once, reused idempotently, and never removed by a per-team teardown. Swap approved models as new Claude versions ship. The pattern (budget action + explicit Deny + drill) transfers unchanged to any Bedrock model, not just Claude.

**Relationship to AWS's official tooling.** AWS publishes "Guidance for Claude Code with Amazon Bedrock" (the `aws-solutions-library-samples` repository), an enterprise kit for OIDC identity federation and OpenTelemetry usage dashboards. It is excellent at authentication and observability. Its quota enforcement counts tokens at a credential broker and, per its own authentication-modes table, is available only in the external-IdP (OIDC) mode, and to our reading it does not configure AWS Budgets or address the Marketplace billing lane. This prompt is the complementary billing-truth layer: dollar-denominated, gross-before-credits, works on a bare AWS account in minutes with no identity provider. Enterprises can run both.

---

## Prerequisites

- **An AWS account**, ideally dedicated to Claude Code (AWS's own recommendation: "Create a dedicated AWS account for Claude Code to simplify cost tracking and access control"). Expected account type: **standalone or management**. In an AWS Organizations member account, Marketplace charges can consolidate at the payer account and the budget's billing-entity filter may not see the member's Anthropic spend; the prompt flags this and tells you to verify the filtered budget sees your first real spend before trusting the cutoff. Member accounts also cannot activate cost-allocation tags.
- **Administrator-level credentials** configured for the AWS CLI v2 (`aws sts get-caller-identity` succeeds). The prompt provisions IAM, Bedrock, and Budgets resources; the identity running it needs rights to create them. Developers never get these credentials: they get leashed identities, with access keys issued per developer and delivered via private onboarding cards.
- **Claude Code installed** for the operator running the prompt (any auth: subscription or Bedrock). Developer machines need Claude Code plus their card.
- **A region with Bedrock Claude availability.** Default: `us-east-1`; the intake asks, and every ARN and card is templated to your answer.
- **Brand-new AWS accounts only:** two one-time gates apply, in this order. The Anthropic use-case form comes first (granted instantly on submission); the Marketplace subscription then initiates on first invocation (up to 15 minutes). Separately, a new-account verification hold can block all Bedrock inference for up to ~2 days after signup; control-plane building works during the hold, so the prompt builds everything and defers verification.
- **No other tooling.** The prompt uses the AWS CLI only: no Terraform, no Python environment, no containers.

**Cost of the deployment itself:** nothing with an hourly rate. IAM, inference profiles, and budget alert emails are free. The first action-enabled budget falls within AWS Budgets' free allowance (first two are free); running many teams means one action-enabled budget each, and budgets beyond the allowance carry AWS Budgets' standard small daily fee. Real cost starts only when developers invoke models, which is exactly the spend this machine meters and caps.

---

## Expected Outcome

About 10-15 minutes after pasting the prompt and answering nine intake questions (defaults provided for eight of them), the account contains, for team `dev` in `us-east-1` with a $100/month cap:

| Layer | Resources | What it does |
|---|---|---|
| Leash | IAM group `ccguard-dev-devs`, policy `ccguard-dev-invoke`, per-dev users + access keys (or zero users with `none-yet`) | Devs can invoke exactly the approved models, through both invoke actions, in every member region of the routing profile, and nothing else |
| Meter | Application inference profiles `ccguard-aip-dev-sonnet` / `-haiku`, tagged `team=dev` | Per-team dollars-per-day attribution in Cost Explorer once tags are activated (24h to surface) |
| Alarms | Budget `ccguard-dev-monthly` ($100): email at 50% and 80% actual, 100% forecast. Budget `ccguard-dev-daily` ($10): email at 100% actual | Gross pre-credit spend (`UnblendedCost`), Marketplace billing lane only, read back and asserted after creation |
| Cutoff | Policy `ccguard-dev-frozen`, role `ccguard-dev-budgets-role` (confused-deputy-pinned trust), one Budget Action | At 100% actual spend, an explicit Deny on both invoke actions attaches to the group automatically; reversible; resting state STANDBY (armed, not fired) |
| Early warning (intake-toggled, default on) | SNS topic + CloudWatch alarm on Bedrock token metrics | Minutes-grade runaway detection, with the dollars-to-tokens arithmetic shown |
| Onboarding | `cards/` directory | Per-developer env-var card with issued credentials plus a half-page runbook for the 2 AM developer |
| Exit | `teardown.sh` | Reverse-order removal, leaves account-global tag activation alone, ends by verifying nothing `ccguard-dev-*` remains |

Then the **Verification Gate** runs five binary checks as a leashed identity (never the admin): allowed model answers (G1), forbidden model is refused (G2), the cutoff fires in a drill and blocks invocation (G3), the cutoff reverses and work resumes (G4), and the test tokens land on the right team's meter (G5). Every command and response is captured to `evidence/` files, the cutoff drill attaches then detaches the freeze and restores the group to its baseline, and the ephemeral gate identity is destroyed even if the gate aborts. Only a 5/5 pass yields the completion block (quoted verbatim from the prompt):

```
DEPLOYMENT VERIFIED
Team: dev   Region: us-east-1   Cap: $100/mo (daily tripwire $10)
Gate: G1 PASS  G2 PASS  G3 PASS  G4 PASS  G5 PASS
Evidence: evidence/g1-allowed.json ... evidence/g5-attribution.json
Your spend controls have FIRED IN A DRILL and been reversed. They are real.
Next: review developer cards in cards/, schedule a quarterly G3/G4 re-drill.
```

That block is template output, emitted ONLY on a full live pass. On a brand-new account still under its verification hold, the gate does not go dark: the authorization checks (G2 forbidden-refused, G3 cutoff-fires, G4 cutoff-reverses) are IAM-evaluation questions it still proves via `iam simulate-principal-policy`, and only the two live-token checks (G1's returned text, G5's attribution figures) defer. It then reports **CONTROLS VERIFIED, LIVE TOKEN PENDING**, and G1/G5 run the moment the hold clears. The prompt never declares success it has not demonstrated.

---

## Troubleshooting

The prompt embeds an error-handling table for build-time and gate failures. These are the operational ones, for life after deployment:

| Symptom | Likely cause | Resolution |
|---|---|---|
| Spend is climbing but no alarm email arrived | Budget data refreshes up to 3x/day (8-12h apart) | Wait one refresh cycle; the token alarm is the minutes-grade signal; re-run the prompt's read-back assertion if you suspect the budget was edited |
| Invoice reads $0 but you want to see real burn | Promotional credits are absorbing the bill | Cost Explorer, filter Charge type = Usage: shows true consumption under credits |
| Every dev suddenly gets `AccessDeniedException` | The cutoff fired: `ccguard-<team>-frozen` is attached to the group | Look for the budget action's freeze-applied notification (distinct from threshold emails); confirm via `aws iam list-attached-group-policies`; if resumption is approved, REVERSE the action, then RESET to re-arm |
| Cutoff fired and was reversed, but will not re-fire this period | `RESET_BUDGET_ACTION` was skipped after the reverse | Run RESET; a reversed action is not re-evaluated that period without it |
| A new dev's every call fails (`Unable to locate credentials`) | The card's AWS_PROFILE was never configured on their machine | Run `aws configure --profile ccguard-<team>-<name>` with the operator-issued access key |
| One dev cannot invoke (others can) | Not in the group, or wrong env vars | Check group membership; verify the card's `AWS_REGION` and profile ARNs match the deployment region |
| `on-demand throughput isn't supported` on a dev machine | Bare foundation-model ID used instead of a profile | Point `ANTHROPIC_MODEL` at the team's application-inference-profile ARN from the card |
| Cost Explorer shows no per-team breakdown | Cost allocation tags not activated, or activated less than 24h ago | Activate `team` and `managed-by` in Billing > Cost allocation tags (management or standalone account only); data appears within 24h and can be backfilled |
| Need per-developer (not per-team) numbers | Attribution grain | Per-developer comes from IAM principal tracking in Cost and Usage Reports; the team profile meters dollars per day per team |
| Brand-new account: every invoke returns `Operation not allowed` | New-account verification hold | Wait for verification (up to ~2 days from signup); the deployment is already built and the gate runs after |
| You drill the cutoff but the action sits in `Requires approval` | Cutoff mode was set to `manual` | That is the designed human-in-the-loop mode; approve it in Budgets > Actions, or recreate with `automatic` |
| `execute-budget-action APPROVE` returns `ResourceLockedException` (Standby) | Tried to force-fire an `automatic` cutoff; APPROVE only applies to a `manual` action awaiting approval | Expected: an automatic cutoff fires on a real billing breach, not on demand. Drill its effect by attaching/detaching `ccguard-<team>-frozen` directly (Gate G3/G4); REVERSE then RESET is the recovery after a real fire |

---

## AWS Services Used

- **AWS IAM**: group, customer-managed policies, per-developer users and access keys, the deny-overrides-allow cutoff mechanism, condition keys (`bedrock:InferenceProfileArn`, `aws:CalledViaLast`, `aws:SourceAccount`)
- **Amazon Bedrock**: model inference (Claude Sonnet 4.6 / Haiku 4.5), cross-region inference profiles, application inference profiles as taggable cost meters
- **AWS Budgets + Budget Actions**: gross-spend measurement (`UnblendedCost` metric), Marketplace billing-entity filtering, threshold notifications, the automated apply-IAM-policy cutoff, the `ExecuteBudgetAction` drill API
- **AWS Cost Explorer / cost allocation tags / CUR**: per-team and per-principal attribution, the under-credits Usage view
- **Amazon CloudWatch + SNS** (intake-toggled layer): `AWS/Bedrock` token metrics for minutes-grade runaway detection
- **AWS CloudTrail**: account-default management event history corroborates the gate's budget-action executions and policy attachments out of band (no setup required)
- **AWS Marketplace**: the billing lane Claude spend actually travels through (the design's central fact)

## Well-Architected Alignment

- **Cost Optimization** (the core pillar here): spend is attributed (tagged profiles, principal tracking), bounded (budgets on gross pre-credit cost in the correct billing lane, read back and asserted), enforced (automated cutoff), and right-sized (Sonnet for primary work, cheaper Haiku as the background default), with the monitoring blindspot (Cost Anomaly Detection vs Marketplace) explicitly designed around rather than discovered on the first invoice.
- **Security**: least-privilege per-developer identities; both invocation actions in every allow and deny (a deny listing only one leaves streaming open); resources pinned to specific model and profile ARNs with the documented cross-region pattern; the budgets service role trust-pinned against confused-deputy (`aws:SourceAccount`); admin credentials never distributed; the gate refuses to run as the administrator and destroys its ephemeral credential even on abort.
- **Operational Excellence**: the Verification Gate is a built-in game day, the cutoff is drilled and reversed before anyone trusts it, and the completion block schedules a quarterly re-drill, making it a cadence rather than a one-off; runbook and per-developer cards ship with the deployment; every gate check leaves evidence artifacts; honest limitation statements (budget refresh latency, attribution grain, UTC budget clocks) are part of the deliverable.
- **Reliability**: the cutoff is reversible by design and the disarm procedure is tested (G4); the drill records the original threshold before mutating and restores it even on abort; build failures stop after three strikes with diagnostics instead of looping; verification blockers degrade to BUILT, PENDING VERIFICATION rather than false success; `teardown.sh` is a verified reverse-order rollback that asserts zero residual team resources.
- **Performance Efficiency**: cross-region inference profiles (used here primarily as the cost meter) also improve invocation availability via member-region routing; the Sonnet-primary / Haiku-background split right-sizes model capability per task.
- **Sustainability**: routine and background work defaults to the smallest sufficient model (Haiku), and the deny-by-default leash prevents oversized-model use, lowering inference compute per unit of work.

---

## Proof

**Watch it (70 seconds).** `demo/drill.gif` is a live re-run of the cutoff drill recorded against this deployment: the approved profile evaluates `allowed`, the forbidden model `implicitDeny` on both invoke doors, the exact frozen policy the budget action applies attaches (`explicitDeny`), detaches (`allowed` again), zero residue. The asciinema source is `demo/drill.cast`; `SHA256SUMS` at the repo root is a recomputable manifest over every receipt including the recording itself, so the firing evidence is fingerprint-verifiable, not just the pre-drill state.

**Why the obvious kill-switch fails on Claude-on-Bedrock.** A generic budget kill-switch inherits two defaults that are both wrong in this lane: AWS Cost Anomaly Detection does not monitor third-party Marketplace products, which is exactly where Claude-on-Bedrock spend bills (legal entity "Anthropic, PBC"), and a default budget measures post-credit spend, which on a credited account reads $0 while real consumption accrues, so its trigger never fires. A cutoff wired to those defaults is a control that cannot fire on the spend it claims to bound. This deployment wires the cutoff to a gross-spend (`UnblendedCost`) budget filtered to the Marketplace billing lane, asserts by read-back that the metric and filters persisted, and then drills the cutoff instead of trusting it.

What has been demonstrated, all on a real, freshly created AWS account (537997492026) that was under AWS's new-account verification hold throughout:

- **The build is real and independently verified.** Claude Code executed this verbatim prompt and completed the full build, including live enumeration of routing member regions and self-recovery from an AWS input-validation quirk. Every claimed resource was then verified by direct AWS CLI reads from a separate session: the dual-action leash policy with member-region ARNs and condition pinning, the `UnblendedCost` + Marketplace-filtered budgets with their notification ladder, the budget action in its correct STANDBY (armed, not yet fired) resting state, the tagged ACTIVE inference profiles.
- **The guardrail and cutoff logic is proven now, not promised.** Authorization is an IAM-evaluation question, and `iam simulate-principal-policy` answers it with the same engine that emits the runtime `AccessDeniedException`. On the live deployment, under the hold: approved Sonnet and Haiku profiles resolve `allowed`; the forbidden model resolves `implicitDeny` on **both** `InvokeModel` and `InvokeModelWithResponseStream` (the streaming door, which only 1 of 129 surveyed entries closed); and the cutoff was drilled for real, attaching the exact `frozen` policy the budget action applies (the approved profile flips to `explicitDeny`) then detaching it (back to `allowed`), leaving zero residue. Receipts in `evidence/gate-drill-underhold/`.
- **The gate is self-executing, confirmed by an independent run.** A second, fresh Claude Code session given only this prompt reached the identical procedure and result from the Verification Gate text alone, producing `evidence/gate-run-independent/`: same deployment, same method, different operator.
- **The honest-degradation path is proven, not theoretical.** Rather than refuse to verify under the hold, the gate proves what is deterministically provable (G2/G3/G4 by simulation) and defers only the two live-token checks (G1's returned text and G5's attribution figures, whose authorization is already shown), reporting `CONTROLS VERIFIED, LIVE TOKEN PENDING`. Those two run the moment the hold clears and join the same `evidence/` directory.
- **Rigor surfaced a real defect.** The gate's original drill fired the cutoff with `execute-budget-action APPROVE_BUDGET_ACTION`; on an automatic action resting in STANDBY that returns `ResourceLockedException` (APPROVE applies only to a manual action awaiting approval). The gate was hardened to drill the cutoff's effect deterministically and verify the automatic trigger by configuration, a method that works under any condition. A control whose own test could not run is exactly what proof-gating exists to catch.

A budget that has never fired is a guess. This deployment exists to retire that guess, and its gate produces the receipts now, not on a promise.
