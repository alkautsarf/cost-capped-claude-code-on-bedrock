# Independent reproduction of the Verification Gate (prompt-driven)

**Captured:** see `_timestamp.txt`. AWS account 537997492026, team `dev`, region us-east-1, under the new-account verification hold.

These receipts were produced by a **separate, fresh Claude Code session** given only `PROMPT.md` and the
fact that pre-flight check 4 found the verification hold. Reading the prompt's Verification Gate section
alone, that independent agent:

- chose `iam simulate-principal-policy` for the authorization checks (G2/G3/G4),
- deferred the live-token checks (G1/G5),
- did **not** create the ephemeral gate principal (correct under a hold),
- attached then detached `ccguard-dev-frozen` to drill the cutoff and restored the group to baseline,
- emitted the `CONTROLS VERIFIED, LIVE TOKEN PENDING` block.

This is a second, independent confirmation of the hand-run drill in `../gate-drill-underhold/`: same
deployment, same method, same result, different operator. It demonstrates the prompt's gate is
self-executing, an agent reaches the correct, deterministic proof procedure from the prompt text alone.

## Files

| File | Result |
|------|--------|
| `g2-forbidden-denied.json` | forbidden Opus 4.8 → `implicitDeny` on `InvokeModel` and `InvokeModelWithResponseStream` |
| `g3-action-config.json` | budget action wiring: `APPLY_IAM_POLICY` → `ccguard-dev-frozen` → group, AUTOMATIC, 100% ACTUAL, STANDBY |
| `g3-frozen-denied.json` | with `ccguard-dev-frozen` attached, approved profile → `explicitDeny` on both doors |
| `g4-restored-allowed.json` | after detach, approved profile → `allowed` on both doors |
| `baseline-group-policies.json` / `final-group-policies.json` | group identical before and after (only `ccguard-dev-invoke`), zero residue |

## Incidental QA finding (not a gate result)

The agent also noticed the budget action's `ExecutionRoleArn` is `ccguard-budgets-role`, while Build
Requirement 4 specifies `ccguard-<team>-budgets-role` (= `ccguard-dev-budgets-role`). The prompt text is
correct and consistent; the v1 build dropped the team prefix when creating the role. `teardown.sh`
targets the actual name and also sweeps all `ccguard-` roles, so there is no orphan risk; the only
consequence is cross-team name collision, which the fresh v2 build (which follows the prompt) avoids.
Recorded here as evidence that the gate's rigor surfaces even cosmetic deployment drift.
