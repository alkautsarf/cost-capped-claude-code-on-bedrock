# Evidence index

All artifacts are real AWS CLI captures from account 537997492026 (a freshly created account), region
us-east-1, team `dev`. They accompany the prompt as proof it produces working controls, not described
ones. The account was under AWS's new-account verification hold throughout, which blocks runtime
inference only; the control plane (IAM, Budgets, policy evaluation) is fully functional.

## Build receipts (the deployment exists, every claim read back)

| File | Proves |
|------|--------|
| `iam-group-create.json`, `iam-group-attached.json` | dev group exists; leash policy attached to it |
| `iam-policy-invoke-create.json` | the leash: both invoke actions, approved-resource ARNs, cross-region pattern, marketplace condition |
| `iam-policy-frozen-create.json` | the cutoff: explicit Deny of both invoke actions |
| `iam-role-budgets-create.json` | budgets service role, confused-deputy trust pinning |
| `aip-sonnet-create.json`, `aip-haiku-create.json`, `profile-sonnet.json`, `profile-haiku.json` | tagged application inference profiles (the per-team meter), ACTIVE |
| `budget-monthly-create.json`, `budget-monthly-describe.json` | monthly cap budget + read-back asserting `UnblendedCost` + Marketplace/Usage filter |
| `budget-daily-create.json`, `budget-daily-describe.json` | daily tripwire budget + read-back |
| `budget-action-create.json`, `budget-action-describe.json` | the cutoff action wired to the group, AUTOMATIC, 100% ACTUAL, correct STANDBY resting state |
| `cost-allocation-tags.json` | `team` / `managed-by` cost-allocation tags activated |
| `preflight-4-converse.json` | pre-flight check 4 detecting the verification hold ("Operation not allowed") |

## Gate proof (the controls actually work)

The Verification Gate's authorization checks (G2 leash-denies-forbidden, G3 cutoff-fires, G4
cutoff-reverses) are IAM-evaluation questions, proven here with `iam simulate-principal-policy` (the same
engine that emits the runtime `AccessDeniedException`) plus a real attach/detach cutoff drill. The
live-token checks (G1 model response, G5 attribution figures) run when the hold clears; their
authorization is already shown.

- **`gate-drill-underhold/`**, the hand-run drill (16 files + README): full allow/deny matrix on both
  invoke doors, cutoff armed -> `explicitDeny` -> disarmed -> `allowed`, zero residue. Includes the
  `ResourceLockedException` finding that hardened the gate's drill method.
- **`gate-run-independent/`**, the same gate reproduced by a separate, fresh Claude Code session given
  only the prompt (7 files + README). Same deployment, same method, different operator: the gate is
  self-executing from the prompt text alone.

## Verify it yourself

Every JSON here is a verbatim AWS CLI response. Re-run any command against your own deployment and
compare. The drill is reversible and leaves the group and budget action exactly as found (see the
`*-final-*` / `final-*` captures).
