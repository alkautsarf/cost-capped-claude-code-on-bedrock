# ccguard onboarding card, team `dev` (template)

No developers were provisioned (`none-yet`). To add a member later:

```bash
aws iam create-user --user-name <username>
aws iam add-user-to-group --group-name ccguard-dev-devs --user-name <username>
aws iam create-access-key --user-name <username>   # hand the keypair to the developer
```

The developer then configures a credentials profile and exports:

```bash
export CLAUDE_CODE_USE_BEDROCK=1
export AWS_REGION=us-east-1            # required: Claude Code does not read this from ~/.aws/config
export ANTHROPIC_MODEL='arn:aws:bedrock:us-east-1:537997492026:application-inference-profile/oba4m7fxnl7e'
export ANTHROPIC_DEFAULT_HAIKU_MODEL='arn:aws:bedrock:us-east-1:537997492026:application-inference-profile/tb0ytgdw25dg'
export AWS_PROFILE=<their-credentials-profile>
```

- `oba4m7fxnl7e` = ccguard-aip-dev-sonnet (Claude Sonnet 4.6)
- `tb0ytgdw25dg` = ccguard-aip-dev-haiku (Claude Haiku 4.5)

See `RUNBOOK.md` in this directory for alarms, freeze/unfreeze, and billing-lag notes.
