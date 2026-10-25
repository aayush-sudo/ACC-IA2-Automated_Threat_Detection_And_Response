# Cost and cleanup

## What it costs

Prices are Azure retail prices for Central India (USD) at the time of the
build. The costs below are **estimates**: Cost Management in the portal shows
the real charges, 8–24 hours late.

| Resource | Price | Running since | Estimated so far (to 24 Oct 23:45 UTC) |
|---|---|---|---|
| Application Gateway WAF_v2 `atdr-appgw` | $0.504/h fixed + $0.0144 per capacity-unit-hour | 23 Oct 16:41 UTC (31 h) | **≈ $15.6** fixed + < $1 capacity units |
| Public IP `atdr-pip-appgw` (Standard, static) | $0.005/h | 23 Oct 16:41 (31 h) | ≈ $0.16 |
| VM `atdr-vm-backend` (Standard_B2ats_v2) | $0.00615/h | 22 Oct 08:57 (63 h) | ≈ $0.39 |
| OS disk, StandardSSD 30 GB | ≈ $2.40/month | 22 Oct | ≈ $0.20 |
| Log Analytics `atdr-law` (PerGB2018, 1 GB/day cap) | $3.22/GB after the free allowance | 22 Oct | ≈ $0: about 0.002 GB ingested in a week |
| Microsoft Sentinel | $6.02/GB; **31-day free trial** | 22 Oct | $0 during the trial |
| Logic App (Consumption) + Sentinel connector | per action / per call (fractions of a cent) | 22 Oct | < $0.01 (fewer than 10 runs) |
| Disk snapshots `atdr-snap-*` | $0.05/GB-month | deleted after each test | < $0.01 |
| WAF policy `atdr-wafpolicy` (standalone) | no charge | 23 Oct | $0 |
| **Total** | | | **≈ $17**, almost all of it the gateway |

- **The gateway is the only meaningful cost: about $12 per day.** Everything
  else together is about 35 cents per day: the public IP about 12 cents (deleted
  together with the gateway), the VM and disk about 23 cents.
- No Bastion, no Defender paid plans, no premium SKUs. The VM has no public IP.
- The Log Analytics workspace has a 1 GB/day ingestion cap, so a log flood cannot
  run up a bill.
- Budget alerts are set in Cost Management (configured in the portal, not by
  these scripts).
- **After the 31-day Sentinel trial**, ingestion would cost about $9.24/GB
  (Log Analytics plus Sentinel). At our volume, about 0.3 MB per day, that is still
  well under a cent.

## Cleanup

### Step 1: right after the final recording

```sh
bash infra/cleanup.sh
```

1. Switches the automation rule **off**.
2. Deletes **only** `atdr-appgw` and `atdr-pip-appgw`, which stops about $12/day.
3. Lists what remains.

Everything else stays: VNet, NSGs, VM, workspace and logs, Sentinel rules,
playbook, and the free WAF policy. To test again later,
`bash infra/04-appgw-create.sh` recreates the gateway identically in about 15
minutes; only the public IP address will change. Each create and delete is
timestamped in `evidence/04-appgw-lifecycle.log`.

What keeps costing after step 1: VM plus disk, about $0.23/day (stop it with
`az vm deallocate -g rg-atdr -n atdr-vm-backend` to cut this to the disk
only, about $0.08/day).

### Step 2: delete everything (only after Anthony agrees)

```sh
bash infra/cleanup.sh --delete-resource-group
```

- Deletes the **whole resource group `rg-atdr`**: VM, disk, workspace with all
  logs and incidents, Sentinel, rules, playbook, role assignments. This cannot be
  undone.
- **Export anything needed for the report first.** Screenshots, `evidence/` and
  the docs are in the repository and are not affected.
- The script lists every resource, refuses to run non-interactively, and
  requires you to type `rg-atdr`.
- Afterwards, by hand in the portal, if no longer needed:
  - remove the two guest teammate accounts (**Entra ID → Users**);
  - remove the budget alerts (**Cost Management → Budgets**).

### Check that billing has stopped

```sh
az resource list -g rg-atdr --query "[?type=='Microsoft.Network/applicationGateways' || type=='Microsoft.Network/publicIPAddresses'].name" -o tsv
```

An empty result after step 1 means the gateway charges have stopped. After
step 2, `az group exists -n rg-atdr` returns `false`.
