#!/usr/bin/env bash
# ccguard teardown, team dev, account 537997492026
# Reverse order of creation. Each step tolerates "already gone".
set -u

ACCOUNT=537997492026
BUDGET_MONTHLY=ccguard-dev-monthly
BUDGET_DAILY=ccguard-dev-daily
ACTION_ID=aae620d8-3881-4257-aab3-15062e50a83f
GROUP=ccguard-dev-devs
INVOKE_POLICY_ARN=arn:aws:iam::${ACCOUNT}:policy/ccguard-dev-invoke
FROZEN_POLICY_ARN=arn:aws:iam::${ACCOUNT}:policy/ccguard-dev-frozen
ROLE=ccguard-budgets-role
AIP_SONNET=arn:aws:bedrock:us-east-1:${ACCOUNT}:application-inference-profile/oba4m7fxnl7e
AIP_HAIKU=arn:aws:bedrock:us-east-1:${ACCOUNT}:application-inference-profile/tb0ytgdw25dg

step() { echo; echo "==> $*"; }

step "1. Reverse the budget action if it has executed (detaches frozen policy)"
aws budgets execute-budget-action --account-id "$ACCOUNT" --budget-name "$BUDGET_MONTHLY" \
  --action-id "$ACTION_ID" --execution-type REVERSE_BUDGET_ACTION 2>/dev/null \
  && echo "reversed" || echo "nothing to reverse (action was in STANDBY)"
# Belt-and-suspenders: detach frozen policy directly if still attached
aws iam detach-group-policy --group-name "$GROUP" --policy-arn "$FROZEN_POLICY_ARN" 2>/dev/null \
  && echo "frozen policy detached" || true

step "2. Delete budget action"
aws budgets delete-budget-action --account-id "$ACCOUNT" --budget-name "$BUDGET_MONTHLY" \
  --action-id "$ACTION_ID" 2>/dev/null && echo "action deleted" || echo "action already gone"

step "3. Delete budgets"
aws budgets delete-budget --account-id "$ACCOUNT" --budget-name "$BUDGET_DAILY"   2>/dev/null && echo "daily deleted"   || echo "daily already gone"
aws budgets delete-budget --account-id "$ACCOUNT" --budget-name "$BUDGET_MONTHLY" 2>/dev/null && echo "monthly deleted" || echo "monthly already gone"

step "4. Delete CloudWatch alarm and SNS topic (optional layer - not deployed; no-op if absent)"
aws cloudwatch delete-alarms --alarm-names ccguard-dev-token-tripwire 2>/dev/null || true
SNS_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'ccguard-dev-alerts')].TopicArn" --output text 2>/dev/null)
[ -n "${SNS_ARN:-}" ] && aws sns delete-topic --topic-arn "$SNS_ARN" && echo "SNS topic deleted" || echo "no SNS topic"

step "5. Delete application inference profiles"
aws bedrock delete-inference-profile --region us-east-1 --inference-profile-identifier "$AIP_SONNET" 2>/dev/null && echo "sonnet AIP deleted" || echo "sonnet AIP already gone"
aws bedrock delete-inference-profile --region us-east-1 --inference-profile-identifier "$AIP_HAIKU"  2>/dev/null && echo "haiku AIP deleted"  || echo "haiku AIP already gone"

step "6. Remove members from group, delete ccguard users, detach policies, delete group"
for u in $(aws iam get-group --group-name "$GROUP" --query 'Users[].UserName' --output text 2>/dev/null); do
  aws iam remove-user-from-group --group-name "$GROUP" --user-name "$u"
  case "$u" in
    ccguard-*)
      for k in $(aws iam list-access-keys --user-name "$u" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
        aws iam delete-access-key --user-name "$u" --access-key-id "$k"
      done
      aws iam delete-user --user-name "$u" && echo "user $u deleted"
      ;;
    *) echo "user $u removed from group but NOT deleted (not ccguard-created)" ;;
  esac
done
aws iam detach-group-policy --group-name "$GROUP" --policy-arn "$INVOKE_POLICY_ARN" 2>/dev/null || true
aws iam detach-group-policy --group-name "$GROUP" --policy-arn "$FROZEN_POLICY_ARN" 2>/dev/null || true
aws iam delete-group --group-name "$GROUP" 2>/dev/null && echo "group deleted" || echo "group already gone"

step "7. Delete ccguard policies and role"
aws iam delete-policy --policy-arn "$INVOKE_POLICY_ARN" 2>/dev/null && echo "invoke policy deleted" || echo "invoke policy already gone"
aws iam delete-policy --policy-arn "$FROZEN_POLICY_ARN" 2>/dev/null && echo "frozen policy deleted" || echo "frozen policy already gone"
aws iam delete-role-policy --role-name "$ROLE" --policy-name ccguard-attach-detach-frozen 2>/dev/null || true
aws iam delete-role --role-name "$ROLE" 2>/dev/null && echo "role deleted" || echo "role already gone"

step "8. Final sweep - remaining ccguard-* resources (MUST be empty)"
LEFT=0
for x in $(aws iam list-policies --scope Local --query "Policies[?starts_with(PolicyName, 'ccguard-')].PolicyName" --output text); do echo "LEFT: policy $x"; LEFT=1; done
for x in $(aws iam list-groups   --query "Groups[?starts_with(GroupName, 'ccguard-')].GroupName"   --output text); do echo "LEFT: group $x";  LEFT=1; done
for x in $(aws iam list-roles    --query "Roles[?starts_with(RoleName, 'ccguard-')].RoleName"      --output text); do echo "LEFT: role $x";   LEFT=1; done
for x in $(aws iam list-users    --query "Users[?starts_with(UserName, 'ccguard-')].UserName"      --output text); do echo "LEFT: user $x";   LEFT=1; done
for x in $(aws budgets describe-budgets --account-id "$ACCOUNT" --query "Budgets[?starts_with(BudgetName, 'ccguard-')].BudgetName" --output text 2>/dev/null); do echo "LEFT: budget $x"; LEFT=1; done
for x in $(aws bedrock list-inference-profiles --region us-east-1 --type-equals APPLICATION --query "inferenceProfileSummaries[?starts_with(inferenceProfileName, 'ccguard-')].inferenceProfileName" --output text 2>/dev/null); do echo "LEFT: inference profile $x"; LEFT=1; done
for x in $(aws budgets describe-budget-actions-for-account --account-id "$ACCOUNT" --query "Actions[?starts_with(BudgetName, 'ccguard-')].ActionId" --output text 2>/dev/null); do echo "LEFT: budget action $x"; LEFT=1; done
for x in $(aws sns list-topics --query "Topics[?contains(TopicArn, 'ccguard-')].TopicArn" --output text 2>/dev/null); do echo "LEFT: SNS topic $x"; LEFT=1; done
for x in $(aws cloudwatch describe-alarms --alarm-name-prefix ccguard- --query "MetricAlarms[].AlarmName" --output text 2>/dev/null); do echo "LEFT: CloudWatch alarm $x"; LEFT=1; done
if [ "$LEFT" -eq 0 ]; then echo "CLEAN: no ccguard-* resources remain."; else echo "WARNING: ccguard-* resources remain (listed above)."; exit 1; fi
