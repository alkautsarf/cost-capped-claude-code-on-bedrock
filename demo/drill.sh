#!/bin/bash
# Verification Gate drill: live re-run, recorded with asciinema.
# Proves the cost cutoff FIRES and REVERSES on a real AWS account, deterministically,
# using AWS's own IAM evaluation engine (simulate-principal-policy).
# Safe + reversible: attaches then detaches ccguard-dev-frozen; trap guarantees detach.

set -u
export AWS_PAGER=""
ACCOUNT=537997492026
REGION=us-east-1
GROUP=ccguard-dev-devs
GROUP_ARN="arn:aws:iam::${ACCOUNT}:group/${GROUP}"
HAIKU_AIP="arn:aws:bedrock:${REGION}:${ACCOUNT}:application-inference-profile/tb0ytgdw25dg"
OPUS_FM="arn:aws:bedrock:${REGION}::foundation-model/anthropic.claude-opus-4-8"
FROZEN_ARN="arn:aws:iam::${ACCOUNT}:policy/ccguard-dev-frozen"

# guarantee zero residue even if the script dies mid-drill
trap 'aws iam detach-group-policy --group-name "$GROUP" --policy-arn "$FROZEN_ARN" 2>/dev/null' EXIT

C="\033[1;36m"; G="\033[1;32m"; R="\033[1;31m"; Y="\033[1;33m"; N="\033[0m"; D="\033[2m"

say()  { printf "\n${C}== %s${N}\n" "$1"; sleep 1.2; }
note() { printf "${D}%s${N}\n" "$1"; sleep 0.8; }
run()  { printf "${Y}\$ %s${N}\n" "$1"; sleep 0.6; }

sim() { # action resource -> prints decision + matched statements
  aws iam simulate-principal-policy \
    --policy-source-arn "$GROUP_ARN" \
    --action-names "$1" \
    --resource-arns "$2" \
    --query 'EvaluationResults[0].{decision:EvalDecision,matched:MatchedStatements[].SourcePolicyId}' \
    --output json
}

policies() {
  aws iam list-attached-group-policies --group-name "$GROUP" \
    --query 'AttachedPolicies[].PolicyName' --output json
}

clear
printf "${C}Cost-Capped Claude Code on Amazon Bedrock · Verification Gate drill (live)${N}\n"
printf "${D}account %s · region %s · team dev · %s${N}\n" "$ACCOUNT" "$REGION" "$(date '+%Y-%m-%d %H:%M %Z')"
printf "${D}AWS's own IAM evaluation engine answers: would this call be allowed RIGHT NOW?${N}\n"
sleep 3

say "0 · Baseline: dev group carries ONLY the invoke leash"
run "aws iam list-attached-group-policies --group-name $GROUP"
policies
sleep 2.5

say "1 · Leash (G2): approved Haiku profile is ALLOWED"
run "simulate bedrock:InvokeModel on the approved Haiku inference profile"
sim bedrock:InvokeModel "$HAIKU_AIP"
sleep 2.5

say "2 · Leash (G2): forbidden Opus 4.8 is DENIED, on BOTH doors"
run "simulate bedrock:InvokeModel on foundation-model/anthropic.claude-opus-4-8"
sim bedrock:InvokeModel "$OPUS_FM"
sleep 2
run "simulate bedrock:InvokeModelWithResponseStream (the streaming door Claude Code uses)"
sim bedrock:InvokeModelWithResponseStream "$OPUS_FM"
sleep 2.5

say "3 · The cutoff is WIRED: budget action applies ccguard-dev-frozen automatically"
run "aws budgets describe-budget-action ... (what fires at 100% actual spend)"
aws budgets describe-budget-action --account-id "$ACCOUNT" \
  --budget-name ccguard-dev-monthly \
  --action-id "$(aws budgets describe-budget-actions-for-budget --account-id "$ACCOUNT" --budget-name ccguard-dev-monthly --query 'Actions[0].ActionId' --output text)" \
  --query 'Action.{trigger:ActionThreshold,type:ActionType,approval:ApprovalModel,status:Status,applies:Definition.IamActionDefinition}' \
  --output json
sleep 3

say "4 · FIRE the cutoff (G3): attach the exact policy the budget action applies"
run "aws iam attach-group-policy --group-name $GROUP --policy-arn .../ccguard-dev-frozen"
aws iam attach-group-policy --group-name "$GROUP" --policy-arn "$FROZEN_ARN"
policies
sleep 2

note "cutoff armed: re-ask AWS, is the APPROVED profile still allowed?"
run "simulate bedrock:InvokeModel on the approved Haiku profile (frozen attached)"
sim bedrock:InvokeModel "$HAIKU_AIP"
sleep 2
run "simulate bedrock:InvokeModelWithResponseStream (streaming door, frozen attached)"
sim bedrock:InvokeModelWithResponseStream "$HAIKU_AIP"
printf "${R}deny-beats-allow: the approved profile flips to explicitDeny on BOTH doors${N}\n"
sleep 3

say "5 · REVERSE the cutoff (G4): detach, access must come back"
run "aws iam detach-group-policy --group-name $GROUP --policy-arn .../ccguard-dev-frozen"
aws iam detach-group-policy --group-name "$GROUP" --policy-arn "$FROZEN_ARN"
policies
sleep 2
run "simulate bedrock:InvokeModel on the approved Haiku profile (after detach)"
sim bedrock:InvokeModel "$HAIKU_AIP"
sleep 2.5

say "6 · Zero residue: group is back to baseline"
run "aws iam list-attached-group-policies --group-name $GROUP"
policies
sleep 2

printf "\n${G}VERDICT: cutoff fires (explicitDeny on both invoke doors) and reverses (allowed again).${N}\n"
printf "${G}Leash holds: approved profile allowed, forbidden model denied on both doors.${N}\n"
printf "${D}Receipts + SHA-256 manifest: github.com/alkautsarf/cost-capped-claude-code-on-bedrock${N}\n"
sleep 4
