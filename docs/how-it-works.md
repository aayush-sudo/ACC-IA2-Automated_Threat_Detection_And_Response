# How it works

This is a plain-language walk through the live system, from one malicious
request to a quarantined server and back. The diagram is in
[`architecture.md`](./architecture.md), and the measured numbers are in
[`test-results.md`](./test-results.md).

## The chain in one paragraph

A request from the internet can only reach our demo shop through the
Application Gateway's Web Application Firewall (WAF). The WAF blocks SQL
injection, cross-site scripting and floods, and writes every decision to the
Log Analytics workspace `atdr-law`. Every 5 minutes, two Microsoft Sentinel
analytics rules look at the last 15 minutes of those logs. If one client keeps
getting blocked, a rule raises an incident that names the client IP and our
server. An automation rule immediately starts the Logic App playbook
`atdr-playbook-contain`. For a High incident, the playbook snapshots the
server's disk, cuts the server off the network, tags it as quarantined, checks
that all of this really happened, comments on the incident and messages the
team on Discord. `response/rollback.sh` undoes the isolation.

## 1. Web app and network (Person 1)

- **`atdr-vm-backend`** is an Ubuntu 24.04 VM (`Standard_B2ats_v2`) running a small
  Flask shop (`webapp/app.py`) under gunicorn: `/`, `/health`,
  `/products?search=` and `/login`. It has **no public IP**. It is managed only
  through `az vm run-command`; there is no SSH port.
- Its network security group, `atdr-nsg-backend`, accepts port 80 only from the
  gateway subnet `10.10.1.0/24`, plus Azure's load balancer, and denies
  everything else.
- The app logs one JSON line per request (time, request ID, method, path,
  status, client IP from `X-Forwarded-For`, duration), never query strings or
  form data.

## 2. The WAF (Person 1)

- **`atdr-appgw`** is an Application Gateway WAF_v2 (autoscale 0–2) with a
  static public IP. It forwards port 80 to the VM and checks `GET /health`
  every 30 seconds.
- **`atdr-wafpolicy`** is in **Prevention** mode, using the Microsoft Default
  Rule Set 2.1. It works by **anomaly scoring**: each matching rule
  (for example 942xxx for SQL injection, 941xxx for XSS) adds to a score and is logged
  as `Matched`. When the total reaches the threshold, rule **949110** ("Inbound
  Anomaly Score Exceeded") blocks the request with 403 and is logged as `Blocked`.
- **`RateLimitDemo`** is our custom rule: more than 20 requests per minute from
  one client address → 403. Each gateway instance counts separately, and there
  are always at least 2 instances, so in practice about 40 requests a minute get
  through before blocking starts.
- Diagnostics go to `atdr-law` in resource-specific mode, in the tables
  `AGWFirewallLogs` (WAF decisions) and `AGWAccessLogs` (every request; a
  blocked request has an empty `ServerRouted`). Logs are queryable about **4
  minutes** after the request.

## 3. Detection (Person 2's queries, live versions in `detection-live/`)

| Rule | Severity | Fires when | Why |
|---|---|---|---|
| ATDR – Repeated WAF blocks from one client | High | ≥ 5 distinct blocked transactions from one IP in 15 min | repeated blocked attacks look like active probing |
| ATDR – WAF rate limit triggered | Medium | ≥ 3 RateLimitDemo blocks from one IP in 15 min | flooding is noisy, but not necessarily an attack |

- Both rules run every 5 minutes with a 15-minute lookback. They map two
  entities: **IP** (the client) and **AzureResource** (the protected VM), and
  they create incidents grouped by IP.
- **Suppression is 15 minutes:** after a rule fires, it stays quiet for 15
  minutes, so the same burst cannot raise a second incident and re-isolate the
  VM right after a rollback.
- **Thresholds:**
  - The High rule keeps Aayush's original 5.
  - The rate-limit threshold was lowered from 10 to 3, because a real 30-request
    burst produced only 4 blocks: the rate limit is counted per gateway instance.
- **Defender portal:** `atdr-law` is onboarded to the Defender portal, so
  incidents also appear there (provider "Microsoft XDR"), with Defender's own
  numbering.

## 4. Response: the playbook (Person 3)

The automation rule "ATDR – Run containment playbook on ATDR incidents" runs
`atdr-playbook-contain` whenever either ATDR rule **creates** an incident. The
playbook authenticates with its own **managed identity**. It holds four roles,
all scoped to `rg-atdr` only: Microsoft Sentinel Responder, Network
Contributor, Virtual Machine Contributor and Disk Snapshot Contributor. There
are no secrets in the workflow; the Discord webhook URL is a secure deployment
parameter.

**Safety checks first (`Validate`).** The playbook acts only if:
- the severity is High or Medium;
- the protected VM can be read;
- the VM is tagged `Project=ATDR` and `Role=TestBackend`.

Anything else is rejected with a comment and no change (tested with a Low
incident). The VM comes from a playbook parameter, not from the alert, so an
attacker cannot steer the playbook to another machine.

**High → containment, in this order:**

1. Record the NIC's current NSG in the VM tag `OriginalNsg`, for rollback.
2. **Snapshot** the OS disk (`atdr-snap-<incident>`, incremental), so evidence is
   preserved before anything changes.
3. **Isolate:** attach `atdr-nsg-isolation` (deny all inbound and outbound) to the VM's NIC.
4. Tag the VM `SecurityStatus=Quarantined`, `IncidentNumber`, `QuarantinedAt`.
5. **Verify:** re-read the NIC and the snapshot. The run counts as successful only
   if both are confirmed.
6. Comment on the incident with every step and its time, and post to Discord.

**Medium → comment and Discord message only.** The site stays up.

Measured: the playbook starts about 10 seconds after the incident, runs for
10–12 seconds, and the VM is verified isolated about 30 seconds after the incident
is created. The same steps done by hand took 17 minutes.

### Why we quarantine the backend

- When the WAF keeps blocking one client, we know someone is **actively
  attacking** the site. We do not know whether an earlier request, or one the
  WAF did not recognise, already got through. Isolation is the standard
  "contain first, investigate second" step in incident response: if the server
  was compromised, cutting it off stops data leaving it, stops it being used
  to attack other machines, and stops the attacker's further commands.
- The **snapshot is taken before isolation**, so investigators have the disk as it
  was at the time of the incident.
- Blocking the attacker's IP alone would not be enough: the WAF already blocks
  their requests, attackers change IP addresses, and it would do nothing about a
  server that is already compromised.
- Isolation is **reversible in about 1–2 minutes** (`rollback.sh` reads
  `OriginalNsg` and removes the quarantine tags), so a cautious decision costs little.

### Limitations

- **A blocked request does not prove compromise.** By definition, every
  request the WAF blocked never reached the server. Our High rule therefore
  isolates on evidence of *attempted* attack, not of *successful* attack. For a
  demo this is deliberately cautious; in production it would take a healthy
  site offline every time a scanner passes by. We saw four such real incidents
  in one day (`evidence/06-scanner-incidents.txt`).
- **False positives from shared IPs.** Many users behind one office or mobile
  NAT address count as one client.
- **Detection takes minutes.** About 4 minutes of log ingestion plus up to 5
  minutes until the next rule run: 5.5–8 minutes from attack to incident in our
  runs. The response itself takes seconds.
- **Availability.** With one backend VM, isolation means a 502 for everyone,
  until rollback. The 502 appears about 4 minutes after isolation, because the
  gateway waits for 3 timed-out health probes.
- **The rate limit is approximate**, because it is counted per gateway instance.
- **Open incidents absorb new alerts** (grouping by IP), so the "incident
  created" trigger does not fire for them. Close each incident after it has been
  handled.

What we would do in production: isolate only when WAF signals are combined
with signals from the server itself (Defender for Servers, unusual outbound
traffic); add a human approval button to the notification; run at least two
backends and drain the suspicious one instead of taking the site down.

## 5. Operating it

| Task | Command |
|---|---|
| Automation rule on / off / status (keep **off** between sessions) | `bash detection-live/automation-rule.sh on\|off\|status` |
| Dry pre-flight (no traffic) | `bash tests/e2e_run.sh <name> --preflight` |
| Full automated end-to-end run | `bash tests/e2e_run.sh <name>` |
| Manual-response baseline | `bash tests/e2e_run.sh <name> --manual` |
| Undo isolation | `bash response/rollback.sh --delete-snapshot` |
| Close a run's incidents afterwards | `bash tests/e2e_run.sh <name> --close` |
| WAF tests T1–T6 from any laptop | `python tests/waf_tests.py http://<gateway-ip>/` |
| Stop / recreate the paid gateway | `bash infra/04-appgw-delete.sh` / `bash infra/04-appgw-create.sh` |

## Verified versus simulated

| Part | Status |
|---|---|
| Web app, WAF blocks, logs, analytics rules, incidents, automation rule, playbook, isolation, 502/Unhealthy, rollback, Discord message | **verified live**, twice end to end |
| Defender portal sync and entities | verified through the API (provider "Microsoft XDR") and in screenshots |
| Manual baseline | verified live: Azure timestamps plus the operator's stopwatch |
| Attack traffic | our own standard test strings against our own gateway; not a real attacker |
| Scanner incidents | real outside traffic, detected live; containment deliberately not run |
| Aayush's `sentinel-rules/samples/` | simulated by design; not used by the live system |
