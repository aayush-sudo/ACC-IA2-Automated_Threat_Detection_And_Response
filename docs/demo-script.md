# Demo script: Automated Threat Detection and Response on Microsoft Azure

Three presenters, one live run. Every number below comes from our real runs
(`evidence/06-*`, `docs/test-results.md`). Say "about" for times: each live run
differs by a minute or two.

| Segment | Presenter | Length | What happens live |
|---|---|---|---|
| 1. Problem and objectives | Aayush | 1 min | slides only |
| 2. Architecture | Anthony | 1.5 min | portal tour |
| 3. Test traffic | Third teammate | 2 min | **attack sent (T0)** |
| 4. WAF | Anthony | 1.5 min | WAF logs fill in (~4 min delay) |
| 5. Detection | Aayush | 2 min | Sentinel rules run every 5 min |
| 6. Response | Anthony | 2 min | incident → playbook → isolation |
| 7. Effects of the response | Third teammate | 1.5 min | 502, Unhealthy, Discord |
| 8. Results and conclusion | Aayush | 1.5 min | rollback runs off camera |

Total about 13 minutes. Segments 4 and 5 are deliberately placed between the
attack and the response: Sentinel needs about 6–8 minutes from attack to
incident, and these two explanations fill that wait. If the incident is late,
pause the recording and cut.

---

## Before recording (Anthony, about 10 minutes before)

1. `bash tests/e2e_run.sh rec1 --preflight` must end in `pre-flight OK`
   (no open ATDR incidents, VM normal, site 200, backend Healthy, automation rule off).
2. Open the browser tabs in this order:
   - **A** `http://<gateway-ip>/` (the demo portal home page).
   - **B** Azure portal → resource group **rg-atdr** (Overview, resource list).
   - **C** Azure portal → **atdr-wafpolicy** → Managed rules.
   - **D** Azure portal → **atdr-law** → Logs, with the two queries from segment 4 pasted in.
   - **E** Defender portal → Microsoft Sentinel → Configuration → **Analytics**.
   - **F** Defender portal → Investigation & response → **Incidents**.
   - **G** **atdr-playbook-contain** → Overview (Runs history).
   - **H** **atdr-appgw** → Backend health.
   - **I** Discord channel.
   - **J** Terminal in the repo folder.
3. The gateway IP is on **atdr-pip-appgw → Overview**. It only changes if the
   gateway is deleted and recreated.
4. The attack is sent by `bash tests/e2e_run.sh rec1` from Anthony's laptop
   (it switches the automation rule on, records every timestamp, and switches
   it off at the end). The third teammate narrates it.
   *Fallback if the teammate runs the traffic from their own laptop:* Anthony runs
   `bash detection-live/automation-rule.sh on` first, the teammate runs
   `python waf_tests.py http://<gateway-ip>/` (T3, T4 and the T5 burst are enough
   to trigger both rules), and Anthony runs `automation-rule.sh off` after the
   playbook has run. The incident then names the teammate's IP. Use only one
   of the two ways per recording.

---

## 1. Problem and objectives (Aayush, about 1 minute)

**On screen:** title slide, then one slide with the three objectives.

**Say:**
> Web applications are attacked all the time. On the 24th of October, while our
> test gateway was online, two real internet scanners triggered our detection
> rules: one probing for PHP code-execution holes, one hunting for leaked `.env`
> and `.git` files. Nobody had told anyone our address; it was simply on the internet. A security team usually has to notice the alert, investigate,
> and then contain the server by hand, and that takes minutes to hours.
>
> Our objectives were: one, block common web attacks before they reach the
> server; two, detect an attacker automatically from the firewall logs; and
> three, contain the affected server automatically within seconds, with a
> snapshot for forensics and a notification to the team. All of it runs on an
> Azure for Students subscription, in one resource group.

**If asked**
- *Why Azure?* Every piece is a managed service (WAF, Log Analytics, Sentinel,
  Logic Apps), so the whole chain is configuration plus a little code, with no
  servers of our own except the test VM.
- *Is the attack traffic real?* Ours uses standard documented test strings
  against our own gateway only. The scanner traffic was genuinely from outside;
  we did not create it.

---

## 2. Architecture (Anthony, about 1.5 minutes)

**On screen:** the diagram in `docs/architecture.md`, then tab **B** (rg-atdr resource list).

**Say:**
> Traffic from the internet reaches only one public address: an Azure
> Application Gateway with Web Application Firewall, `atdr-appgw`. Behind it, in
> a private subnet, is our demo web server, `atdr-vm-backend`, a small Flask
> shop. It has no public IP, and its network security group only accepts port 80
> from the gateway's subnet.
>
> The gateway sends every firewall decision to a Log Analytics workspace,
> `atdr-law`. Microsoft Sentinel runs two detection rules over those logs every
> five minutes. When a rule raises an incident, an automation rule starts our
> Logic App playbook, `atdr-playbook-contain`, which contains the server and
> notifies us on Discord.
>
> Everything is in this one resource group, `rg-atdr`, in Central India, and
> is created by scripts in our repository's `infra/` folder.

**If asked**
- *Why a gateway in front instead of protecting the VM directly?* The WAF
  inspects HTTP itself (SQL injection, XSS) before anything reaches the server,
  and it gives us one place where every request is logged.
- *How does the playbook get permission to change the VM?* It has its own
  managed identity with four narrow roles on rg-atdr only (Sentinel Responder,
  Network Contributor, VM Contributor, Disk Snapshot Contributor). There are no
  passwords or keys in the playbook.

---

## 3. Test traffic (third teammate, about 2 minutes)

**On screen:** tab **A** (the shop works: home page, a normal search), then tab
**J**, where Anthony starts `bash tests/e2e_run.sh rec1`.

**Say (while it runs):**
> First, the site works normally: home page, search for "lock". Now we act as
> the attacker. The script sends five standard attack strings from security
> testing guides, two SQL injections like `' OR 1=1--` and three cross-site
> scripting payloads like `<script>alert('xss')</script>`. Each one comes back
> `403 Forbidden`; the firewall stopped them.
>
> Then it sends fifty normal searches in about one and a half seconds, like a
> bot flooding the site. The first thirty or so get through, then the gateway
> starts answering `403`. That is our rate-limit rule, 20 requests per minute
> per client.
>
> All of this took about two seconds. From here on, nobody touches anything.

**Point at:** the five `-> HTTP 403` lines and the line
`burst of 50 ... 403s=… first 403 at #…` (our runs: 15–19 blocks, first block
at request 30–36).

**If asked**
- *Why does the rate limit start after about 30 requests, not 20?* The gateway
  runs on two instances and each counts separately, so roughly 20 per instance
  get through. We measured this in the logs.
- *Is this safe to do?* It is our own gateway, about 55 requests, using
  documented test strings. No exploit is run; the server never even receives
  the blocked requests.

---

## 4. The WAF (Anthony, about 1.5 minutes)

**On screen:** tab **C** (atdr-wafpolicy: Prevention mode, Microsoft Default
Rule Set 2.1, custom rule RateLimitDemo), then tab **D** (Logs).

**Query 1** (WAF decisions in the last 15 minutes):
```kusto
AGWFirewallLogs
| where TimeGenerated > ago(15m) and Action == "Blocked"
| summarize blocked = count() by ClientIp, RuleId
```
**Query 2** (did blocked requests reach the server?):
```kusto
AGWAccessLogs
| where TimeGenerated > ago(15m)
| summarize count() by HttpStatus, ServerRouted
```

**Say:**
> The firewall policy is in Prevention mode, so it blocks rather than just
> logging. It uses Microsoft's managed rule set, which scores each request
> against hundreds of attack patterns. Once the score is high enough, rule
> 949110, "inbound anomaly score exceeded", blocks it. Our own custom rule,
> RateLimitDemo, blocks any client sending more than 20 requests a minute.
>
> Every decision lands in Log Analytics after about four minutes. Here are our
> attack's blocks: rule 949110 for the injections, RateLimitDemo for the flood.
> And in the access log, the blocked requests have an empty "server routed"
> field: they never reached the web server.

(If the rows have not arrived yet, say "the logs take about four minutes" and
show last night's scanner rows by changing `15m` to `1d`.)

**If asked**
- *Why anomaly scoring instead of one rule per attack?* One suspicious pattern
  alone can be a false positive. Requiring several matches (a score) before
  blocking reduces false positives.
- *Can the WAF be bypassed?* Any signature-based filter can be evaded by a
  determined attacker, which is why we also detect and respond rather than
  relying on blocking alone.

---

## 5. Detection (Aayush, about 2 minutes)

**On screen:** tab **E** (Analytics: the two ATDR rules, both Enabled), open
**"ATDR – Repeated WAF blocks from one client"** → Set rule logic. Then the
`detection-live/` folder (header of `waf-rate-limit.kql`).

**Say:**
> Sentinel is Microsoft's cloud SIEM. I wrote the detection queries in KQL.
> The first rule asks: has one client IP been blocked at least five times in
> the last fifteen minutes? That is High severity, because repeated blocked
> attacks look like someone actively probing the site. It runs every five
> minutes.
>
> The second rule fires when one client hits our rate limit at least three
> times. That is Medium severity, because flooding alone is noisy but not
> necessarily an attack.
>
> Each alert carries two entities: the attacker's IP, and the server we
> protect. Those entities are what the response playbook acts on.
>
> One thing we changed from my original design: I first set the rate-limit
> threshold to 10. When we measured real traffic, one burst only produced
> about four blocks, because of the two gateway instances, so 10 could never
> fire. We lowered it to 3, based on the measured data, and documented why.

**Then switch to tab F** (Incidents) as soon as the incident appears:
> And here it is: Sentinel has raised a High incident, "Repeated WAF blocks
> from" our IP, with the server attached.

**If asked**
- *Why five blocks in fifteen minutes?* A single blocked request is often a
  harmless false positive or a random scanner. Five in fifteen minutes from one
  address is a pattern. Our test produces about twenty, and real scanners
  produced 47–231.
- *Why does it take minutes, not seconds?* About four minutes is log ingestion
  in Log Analytics, and up to five minutes is the rule schedule. The response
  itself, after the incident exists, takes seconds.
- *What about false positives, such as a whole office behind one IP?* That is a
  real limitation, covered in the conclusion. The threshold and the High-only
  isolation policy are the tuning knobs.

---

## 6. Response (Anthony, about 2 minutes)

**On screen:** tab **F** → open the High incident (entities, Activity log
comment), then tab **G** → the newest run → the green action list.

**Say:**
> The moment the incident was created, an automation rule in Sentinel started
> our playbook. Nobody clicked anything. It started about ten seconds after the
> incident.
>
> The playbook first checks that it is allowed to act: the incident must be High or
> Medium, and the server must carry our tags, Project ATDR and Role
> TestBackend, so it can never isolate the wrong machine. Then, for a High
> incident:
> one, it takes a snapshot of the server's disk, for forensics, before
> anything changes;
> two, it swaps the server's network security group for an isolation group
> that denies all traffic in and out;
> three, it tags the server as Quarantined, recording the incident number and
> the original security group so we can undo it;
> four, it reads everything back to verify the isolation really happened;
> and five, it writes this comment into the incident and messages the team on
> Discord.
>
> The whole playbook takes about ten to twelve seconds.

**Point at:** the actions `b_Snapshot_OS_disk`, `c_Isolate_NIC`, `e_Verify_NIC`,
`Comment_high`, `g_Notify_high`, all Succeeded, and the comment text in the incident.

**If asked**
- *Why isolate instead of blocking the attacker's IP?* Attackers change IPs,
  and the WAF already blocks their requests. Isolation assumes the server
  might be affected and stops anything spreading or leaking from it, while the
  snapshot preserves evidence. It is the standard "contain first" step in
  incident response.
- *Why only for High?* Isolation takes the site offline. A Medium incident
  (rate limit only) gets a comment and a notification, no disruption.
- *Who started the playbook?* The automation rule. Sentinel's own health log
  records the automation rule firing on "incident created" and names the exact
  playbook run it started. Our script never calls the playbook.

---

## 7. Effects of the response (third teammate, about 1.5 minutes)

**On screen:** tab **I** (Discord message), tab **A** refreshed (502), tab **H**
(Backend health: Unhealthy). The 502 appears **about 4 minutes after isolation**;
show Discord first.

**Say:**
> Here is the team notification on Discord: incident number, attacker IP,
> server, each containment step with its time, and "NIC isolated: true".
>
> Now the website. Refresh: `502 Bad Gateway`. The gateway can no longer reach
> the server, because the server is cut off. The gateway's health page agrees:
> the backend is Unhealthy, because its health checks time out.
>
> It takes a few minutes to show here because the gateway waits for three failed
> health checks, thirty seconds each, before it gives up on the server.

**If asked**
- *Isn't taking the site down bad?* For this prototype we chose safety over
  availability: a possibly compromised server goes offline until a person
  checks it. In production you would fail over to a clean server.
- *How do you bring it back?* `response/rollback.sh` re-attaches the original
  security group from the tag and removes the quarantine tags; the site is back
  in under two minutes.

---

## 8. Results and conclusion (Aayush, about 1.5 minutes)

**On screen:** `docs/test-results.md` (the comparison table).

**Say:**
> Results. We ran the full chain twice automatically and once by hand.
> Automatically, from the incident being created to the server being isolated
> and verified took about 30 seconds both times. Then we timed the same steps
> done by hand in the portals: snapshot, isolate, tag, comment and Discord
> message. Anthony needed 11 minutes of hands-on work by the stopwatch, and 17
> minutes passed between the incident being created and the server being fully
> quarantined, even though he knew exactly what to do. That is about thirty
> times slower, before even counting the time for someone to notice the alert.
>
> The longest part is detection, about six to eight minutes, which is mostly
> log ingestion and the rule schedule, not our logic.
>
> The system also worked against real attackers. While the gateway was
> online, four real incidents were raised against internet scanners. Because
> we keep automatic containment switched off between test sessions, those were
> recorded but did not take the server down.
>
> Limitations: a blocked request does not prove the server was compromised, so
> isolating on WAF blocks is deliberately cautious, and a shared office IP could
> trigger it. Detection takes minutes, not seconds. And the rate limit is
> counted per gateway instance.
>
> Future work: isolate only on stronger evidence, such as signals from the server
> itself; add a human approval step for production; and fail over to a clean
> server instead of going offline. Thank you.

**If asked**
- *What would you change first?* Combine WAF signals with host signals before
  isolating, and add an approval button in the Discord or Teams message for
  production use.
- *What did it cost?* Mostly the gateway, about 50 US cents an hour; see
  `docs/cost-and-cleanup.md`.

---

## After recording (Anthony, off camera)

1. Take any missing screenshots before rollback.
2. `bash response/rollback.sh --delete-snapshot` (site back to 200 and Healthy
   in about 1–2 minutes).
3. `bash tests/e2e_run.sh rec1 --close` (close the recording's incidents).
4. `bash detection-live/automation-rule.sh status` must say `enabled=false`.
