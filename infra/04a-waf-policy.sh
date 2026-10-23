#!/usr/bin/env bash
# Phase 4a — WAF policy atdr-wafpolicy (no charge on its own; billing starts only
# when an Application Gateway WAF_v2 exists). Safe to re-run.
#   - Prevention mode, enabled, request body inspection on
#   - Managed rules: Microsoft_DefaultRuleSet 2.1 (newest offered for WAF_v2:
#     OWASP CRS 3.3.2 base + Microsoft Threat Intelligence rules)
#   - Custom rule RateLimitDemo: RateLimitRule, group by client address,
#     20 requests per 1 minute, action Block
set -euo pipefail
source "$(dirname "$0")/common.sh"

POLICY="atdr-wafpolicy"
RULESET_TYPE="Microsoft_DefaultRuleSet"
RULESET_VERSION="2.1"

if ! az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none 2>/dev/null; then
  echo "[$(utc_now)] Creating WAF policy $POLICY ($RULESET_TYPE $RULESET_VERSION)"
  az network application-gateway waf-policy create -g "$RG" -n "$POLICY" -l "$LOCATION" \
    --type "$RULESET_TYPE" --version "$RULESET_VERSION" --tags "${TAGS[@]}" -o none
fi

echo "[$(utc_now)] Policy settings: Prevention, enabled, request body inspection on"
az network application-gateway waf-policy policy-setting update -g "$RG" --policy-name "$POLICY" \
  --mode Prevention --state Enabled \
  --request-body-check true --request-body-enforcement true \
  --max-request-body-size-in-kb 128 --request-body-inspect-limit-in-kb 128 \
  --file-upload-limit-in-mb 100 -o none

if ! az network application-gateway waf-policy custom-rule show -g "$RG" --policy-name "$POLICY" -n RateLimitDemo -o none 2>/dev/null; then
  echo "[$(utc_now)] Custom rule RateLimitDemo: 20 requests / 1 min per client IP -> Block"
  # Every request path begins with "/", so every request counts towards the per-client
  # limit. (Azure rejects RemoteAddr as a match variable in RateLimitRule conditions:
  # ApplicationGatewayFirewallConditionUnsupportedMatchVariable.)
  az network application-gateway waf-policy custom-rule create -g "$RG" --policy-name "$POLICY" \
    -n RateLimitDemo --priority 10 --rule-type RateLimitRule --action Block --state Enabled \
    --rate-limit-duration OneMin --rate-limit-threshold 20 \
    --group-by-user-session "[{group-by-variables:[{variable-name:ClientAddr}]}]" \
    --match-conditions "[{variables:[{variable-name:RequestUri}],operator:BeginsWith,values:[/]}]" -o none
fi
echo "[$(utc_now)] Done"
