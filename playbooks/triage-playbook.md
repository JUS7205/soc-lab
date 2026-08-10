# Alert Triage Playbook

From first alert to containment in a scripted, repeatable flow.

## Stage 1 — Validate (0–5 min)

1. **Is it real?** Open the raw event. Sysmon E1 command line, E13 key path,
   E3 destination. One raw event beats three dashboards.
2. **Is it this host?** Confirm the asset's role (DC? workstation? server?).
3. **Enrich**: search the binary hash against VirusTotal/MalwareBazaar, domain
   against reputation. 5-minute budget — don't rabbit-hole.
4. Decide: `NOISE` (whitelist + annotate why) | `SUSPICIOUS` → Stage 2 |
   `MALICIOUS` → escalate now.

## Stage 2 — Scope (10–20 min)

- [ ] Timeline: what happened 30 min before and after the alert on this host?
- [ ] Host-side drift: `pulse diff baseline current` — new processes,
      new external connections, orphaned parents.
- [ ] Account context: is the alerting account admin? Service account?
      Logged in at the time?
- [ ] Lateral spread: same behavior on other hosts? (Wazuh agent-wide query)
- [ ] Data exposure: which files/shares did the account touch?

## Stage 3 — Contain (20–30 min, per playbook)

- [ ] Isolate host at the switch or via EDR quarantine (block first, ask later)
- [ ] Disable the account / reset credentials (even if just suspicious)
- [ ] Terminate attacker processes via EDR kill-switch
- [ ] Preserve evidence: collect Sysmon logs, memory dump (if EDR-capable),
      copy dropped files — evidence before eradication

## Stage 4 — Eradicate, recover, learn (next shift)

- [ ] Remove persistence (run keys, tasks, services) — verify by re-scan
- [ ] Reimage from known-good backup if the host was admin-owned
- [ ] Write the writeup: `dfir-writeups` format (timeline, IOCs, gap analysis)
- [ ] Detection gap: did `detection-rules` miss it? File a new rule idea

## Rules of thumb

- **Alert fatigue is a design failure**: every alert you triage as noise should
  produce a rule/tuning change that week.
- **Suspicious beats sorry**: erring toward containment on a workstation is
  cheap; erring toward "wait" on a DC is not.
- **Write while it's fresh**: the 30-minute writeup you do during the incident
  is worth more than the 3-hour reconstruction you do after.
