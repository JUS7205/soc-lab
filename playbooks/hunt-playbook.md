# Daily Hunt Playbook

A reusable, ATT&CK-aligned checklist for a 30–60 minute hunt. Run it the same
way every day so *drift from the norm* is what stands out — the same
philosophy as the `pulse` baseline/diff loop, applied to logs.

## 0. Prep (5 min)

- [ ] Check Wazuh dashboard for new alerts since last hunt
- [ ] Note today's baseline: `pulse snapshot > baseline-YYYY-MM-DD.json`
- [ ] Confirm Sysmon is collecting (E1/E3/E13/E22 non-empty last 24h)

## 1. Initial access & execution (15 min)

- [ ] **Office → shell**: `winword|excel|powerpnt` spawning `powershell|mshta|cmd`
      (rule 100203). Investigate parent chain of every hit.
- [ ] **LOLBin usage**: `rundll32`, `mshta`, `regsvr32`, `wmic` with
      `http`/`javascript:`/`vbscript:` in command line (`detection-rules` sigma set).
- [ ] **PowerShell**: download cradles (`Invoke-WebRequest`, `DownloadString`,
      `Net.WebClient`) combined with `-ExecutionPolicy Bypass`.

## 2. Persistence & privilege (10 min)

- [ ] **Run keys** written to non-standard paths (rule 100201) — `Temp`,
      `ProgramData`, user-writable dirs.
- [ ] **Scheduled tasks** created with `/ru SYSTEM` (`detection-rules` sigma).
- [ ] New services registered outside `C:\Windows\System32`.

## 3. Network & C2 (10 min)

- [ ] **New external destinations** in the last 24h vs. the 14-day baseline —
      cross-check with `pulse diff` on the host side.
- [ ] DNS queries to high-risk TLDs (rule 100202).
- [ ] `svchost.exe` connecting to non-standard ports (sigma set).

## 4. Wrap-up (5 min)

- [ ] Any `ALERT` from `pulse verdict`? Investigate or whitelist deliberately.
- [ ] Log hunt findings (even "nothing new") — the daily log is the baseline
      of *what normal looks like*.

## Metrics worth tracking

| Metric | Why |
| --- | --- |
| Time-to-triage per alert | Measures workflow, not luck |
| New external destinations per day | Baseline "normal noise" per host |
| False-positive rate of each rule | Every rule gets tuned or retired |
| Detections without any alert | The gap list (feeds `detection-rules` backlog) |
