# Fixed IDs of the Phase 5 Sentinel rules (sourced by the detection-live scripts and tests/e2e_run.sh).
RULE_BLOCKS_ID="61f2546c-043a-4cd5-912f-e3e354c6b45a"   # ATDR – Repeated WAF blocks from one client (High)
RULE_RATE_ID="f28693aa-8349-4ff4-a6d1-77040f2faaf8"     # ATDR – WAF rate limit triggered (Medium)
AUTOMATION_ID="4f5cb1ad-17ee-441b-94e7-b3358131d28b"    # run atdr-playbook-contain on their incidents
SI="/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.OperationalInsights/workspaces/$LAW/providers/Microsoft.SecurityInsights"
