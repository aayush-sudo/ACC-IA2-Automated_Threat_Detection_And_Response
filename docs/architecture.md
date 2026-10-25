# Architecture

Everything is in one resource group, **`rg-atdr`**, in **Central India**, on an
Azure for Students subscription. Every resource is tagged `Project=ATDR`.

```mermaid
flowchart LR
    internet(["Internet clients<br/>(our tests, real scanners)"])

    subgraph vnet["VNet atdr-vnet 10.10.0.0/16"]
        subgraph snetgw["snet-appgw 10.10.1.0/24 (atdr-nsg-appgw)"]
            appgw["Application Gateway WAF_v2<br/>atdr-appgw<br/>public IP atdr-pip-appgw"]
        end
        subgraph snetbe["snet-backend 10.10.2.0/24"]
            vm["VM atdr-vm-backend 10.10.2.4<br/>Flask demo shop, no public IP<br/>NIC NSG: atdr-nsg-backend"]
        end
    end

    policy["WAF policy atdr-wafpolicy<br/>Prevention · DRS 2.1 · RateLimitDemo"]
    law[("Log Analytics atdr-law<br/>AGWFirewallLogs · AGWAccessLogs")]
    sentinel["Microsoft Sentinel<br/>2 analytics rules (every 5 min)<br/>→ incident (IP + VM entities)"]
    defender["Defender portal<br/>(incident sync)"]
    auto["Automation rule<br/>(on only during test runs)"]
    playbook["Logic App atdr-playbook-contain<br/>managed identity"]
    iso["atdr-nsg-isolation<br/>deny all in/out"]
    snap[("Snapshot atdr-snap-&lt;n&gt;")]
    discord["Discord channel"]

    internet -- "HTTP :80" --> appgw
    policy -. attached .- appgw
    appgw -- "allowed requests :80" --> vm
    appgw -- "diagnostics (~4 min)" --> law
    law --> sentinel
    sentinel <--> defender
    sentinel -- "incident created" --> auto
    auto -- "run playbook" --> playbook
    playbook -- "1. snapshot OS disk" --> snap
    playbook -- "2. swap NIC NSG" --> iso
    iso -. "isolates" .- vm
    playbook -- "3. tag VM, verify" --> vm
    playbook -- "4. comment" --> sentinel
    playbook -- "5. notify" --> discord
```

## Sequence of one attack

```mermaid
sequenceDiagram
    participant A as Attacker (our test laptop)
    participant W as atdr-appgw (WAF)
    participant L as atdr-law
    participant S as Sentinel rules
    participant R as Automation rule
    participant P as Playbook
    participant V as atdr-vm-backend
    A->>W: 5 SQLi/XSS strings + 50-request burst
    W-->>A: 403 (949110 / RateLimitDemo)
    W->>L: firewall + access logs (~4 min)
    S->>L: query every 5 min, last 15 min
    S->>R: incident created (High, IP + VM)
    R->>P: run (~10 s after the incident)
    P->>V: validate tags, snapshot, isolate NIC, tag, verify (~10-12 s)
    P->>S: incident comment
    P-->>A: (site now 502 for everyone after ~4 min of failed probes)
```

## Components

| Component | Name | Configuration | Script |
|---|---|---|---|
| Virtual network | `atdr-vnet` | 10.10.0.0/16; `snet-appgw` 10.10.1.0/24, `snet-backend` 10.10.2.0/24 | `infra/01-foundation.sh` |
| NSG (gateway subnet) | `atdr-nsg-appgw` | Internet → 80; GatewayManager 65200–65535; AzureLoadBalancer | 01 |
| NSG (backend NIC) | `atdr-nsg-backend` | 80 from 10.10.1.0/24 only; AzureLoadBalancer; deny all else | 01 |
| NSG (isolation) | `atdr-nsg-isolation` | deny all inbound and outbound (priority 100) | 01 |
| Backend VM | `atdr-vm-backend` | Ubuntu 24.04, Standard_B2ats_v2, StandardSSD 30 GB, no public IP, tags `Role=TestBackend` | 01, `02-deploy-webapp.sh` |
| Web app | ATDR Demo Portal | Flask + gunicorn on :80, systemd hardening, JSON access log | `webapp/` |
| Log Analytics + Sentinel | `atdr-law` | PerGB2018, 30-day retention, 1 GB/day cap; Sentinel onboarded; Defender portal primary | 01 |
| WAF policy | `atdr-wafpolicy` | Prevention, Microsoft_DefaultRuleSet 2.1, `RateLimitDemo` (20/min per client, `RequestUri` begins with `/`) | `infra/04a-waf-policy.sh` |
| Application Gateway | `atdr-appgw` + `atdr-pip-appgw` | WAF_v2, autoscale 0–2 (minimum maximum is 2), HTTP :80, probe `GET /health` every 30 s, diagnostics → atdr-law (resource-specific) | `infra/04-appgw-create.sh` / `-delete.sh` |
| Analytics rules | 2 scheduled rules | 5 min / 15 min, entities IP + AzureResource, grouping by IP, 15-min suppression | `detection-live/deploy-rules.sh` |
| Automation rule | run atdr-playbook-contain | incidents created by either ATDR rule; **off between sessions** | `detection-live/automation-rule.sh` |
| Playbook | `atdr-playbook-contain` (+ connection `atdr-conn-sentinel`) | Logic App Consumption, Sentinel incident trigger, managed identity, ARM calls via HTTP | `response/deploy-playbook.sh` |

## Identities and permissions (all scoped to rg-atdr)

| Principal | Role | Why |
|---|---|---|
| Playbook managed identity | Microsoft Sentinel Responder | comment on incidents |
| | Network Contributor | swap the NIC's NSG |
| | Virtual Machine Contributor | read and tag the VM |
| | Disk Snapshot Contributor | create the snapshot |
| Azure Security Insights (Sentinel service) | Microsoft Sentinel Automation Contributor | lets the automation rule start the playbook |
| Aayush (guest) | Microsoft Sentinel Contributor | work with the Sentinel rules and incidents (no Owner/Contributor) |
| Third teammate (guest) | Reader + Microsoft Sentinel Reader | view the portal for the demo |

There are no keys or passwords in the repository. The Discord webhook URL is
passed only as a secure deployment parameter, from the environment variable
`NOTIFY_WEBHOOK_URL`.
