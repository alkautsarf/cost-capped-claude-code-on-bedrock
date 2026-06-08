# Cost-Capped Claude Code on Amazon Bedrock

A production-ready, copy-paste prompt that deploys Claude Code for a development team on Amazon Bedrock
with hard spend controls and a Verification Gate that proves the controls fire before declaring success.

## What's here

| Path | What it is |
|------|------------|
| `PROMPT.md` | **The submission.** The verbatim prompt, paste into Claude Code (or any capable assistant) and it runs the intake -> pre-flight -> build -> Verification Gate end to end. |
| `DOCS.md` | Context docs: use case, prerequisites, expected outcome, troubleshooting, AWS services used, Well-Architected alignment, and the Proof section. |
| `test-run-v1/` | Evidence the prompt works: artifacts and AWS CLI receipts from a real run on a fresh account. |
| `test-run-v1/evidence/README.md` | Index of all proof, build receipts + gate drill. |
| `test-run-v1/cards/` | Sample developer onboarding card template + runbook the prompt emits. |
| `test-run-v1/teardown.sh` | The reverse-order teardown the prompt generates. |

## What it deploys

A deny-by-default IAM leash (both invoke doors, approved models only, cross-region pinned), per-team
application inference profiles for cost attribution, an `UnblendedCost` budget ladder filtered to the
Marketplace billing lane (where Claude-on-Bedrock spend actually lands and Cost Anomaly Detection is
blind), and an automated budget-action spend cutoff that is drilled and reversed before it is trusted.

## Proof status

Run on a real, freshly created AWS account that was under AWS's new-account verification hold. The build
and the guardrail + cutoff **authorization** logic are proven now (IAM policy simulation + a real cutoff
attach/detach drill, reproduced by an independent agent); the two **live-token** checks (model response,
attribution figures) run the moment the hold clears. See `DOCS.md` -> Proof and
`test-run-v1/evidence/README.md`.

## Provenance and redaction

The evidence under `test-run-v1/` is verbatim AWS CLI output from account `537997492026`, a real,
freshly created AWS account. The account ID is intentionally left in place: it is not a secret, and it
makes the ARNs in the receipts verifiable rather than templated. The only redaction is the budget alert
email, replaced with `alerts@example.com` to avoid publishing a personal address; nothing else in the
evidence is altered. No credentials, access keys, or secrets are present in this repository.
