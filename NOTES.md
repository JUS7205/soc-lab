# Lab journal

Running log of what broke, what I changed, and why. Newest first.

## 2026-08-11 — Custom rules validated live with wazuh-logtest (Wazuh 4.9.2)

**What worked:** brought up the `wazuh/wazuh-manager:4.9.2` image with
`custom-rules.xml` mounted as `local_rules.xml`, and exercised all three rules
against crafted eventchannel events. All fire:

| Rule | Test event | Result |
| --- | --- | --- |
| 100201 | Sysmon E13 `SetValue` on `...\CurrentVersion\Run` → `AppData\Local\Temp\e.exe` | **level 8**, T1547.001 |
| 100202 | Sysmon E22 `queryName` `superlegit-bonus.xyz` | **level 5**, T1071.001 |
| 100203 | Sysmon E1 `WINWORD.EXE` → `powershell.exe` | **level 10**, T1566.001 |
| (negative) | E13 run-key set to `C:\Program Files\...` | stays at base 61615, no alert |

**Two real bugs the test caught (rule 100201):**

1. `targetObject` for a run-key write ends with the *value name*
   (`...\CurrentVersion\Run\Updater`), not `Run` — the first regex
   (`...\\Run$`) never matched anything. Fixed to allow an optional trailing
   value segment.
2. The key path includes the `SOFTWARE\` segment (`HKCU\...\Software\Microsoft\
   ...\CurrentVersion\Run`) — my first regex went straight from the SID to
   `\Microsoft`, which matches nothing on real Windows.

**Logtest gotchas worth remembering:**

- `wazuh-logtest` does not route through the `winevtchannel` decoder (that's
  a separate queue in `analysisd`), so base rule 60000
  (`decoded_as windows_eventchannel`) never matches and no sysmon group is
  assigned. Workaround for rule testing: patch rule 60000 in the test
  container to `decoded_as json` and feed events in the already-decoded
  `win.system.*` / `win.eventdata.*` JSON shape.
- The agent sends `win.system.eventID` as a **string** ("13"), not a number —
  the JSON decoder skips numeric values as dynamic fields.
- `severityValue` must be present for the 60004 → 61600 chain
  (`^INFORMATION$`).

**Environment notes:** `analysisd` needs the full data layout to run outside
the s6 entrypoint: `etc/ossec.conf` + `internal_options.conf` from
`data_tmp/permanent` / `data_tmp/exclusion`, `etc/shared/ar.conf`, and the
`logs/{alerts,archives,firewall}/<year>` directories, or it dies with
"Could not create directory" during init. `wazuh-db` must run first or
analysisd logs MITRE-load errors (it survives those, though).

## 2026-08-11 — Custom rules rewritten for Wazuh 4.9.2

**Symptom:** The custom rules in `wazuh/custom-rules.xml` never fired in the
4.9.x stack. No errors, no alerts — the ruleset just silently matched nothing.

**Root cause (found by diffing against the Wazuh 4.9.2 ruleset):**

1. **Wrong field names.** The rules were written against the old Sysmon XML
   agent field layout (`data.*`), but eventchannel-based agents in 4.9 emit
   `win.eventdata.*` / `win.system.eventID`. `if_group` + `win.eventdata.*`
   is the shape that matches.
2. **Wrong group names.** Sysmon events 1, 13, 22 map to groups
   `sysmon_event1`, `sysmon_event_13`, `sysmon_event_22` — underscore from
   event 10 up, and no underscore below. The rules referenced `sysmon_event_13`
   and `sysmon_event1` correctly but `sysmon_event22` / `sysmon_event13`
   inconsistently, so `if_group` never matched the decoded events.
3. **Regex flavour.** The pattern matcher on these fields is PCRE2, not the
   default; `\.regex` with a plain string worked but the match semantics
   differed from what I wrote. Rewrote the patterns against actual
   eventchannel JSON samples.

**Fix:** Rewrote the three rules (`100201` run-key persistence via Sysmon E13,
`100202` suspicious child process via E1, `100203` DNS query anomalies via
E22) using `if_group` + `win.eventdata.eventType|targetObject|details|queryName|parentImage|image`
with PCRE2 patterns, keyed off the 4.9.2 base rules (IDs 184665+).

**Also fixed:** `agent-ossec-snippets.conf` had an illegal `--` inside an XML
comment that made the whole snippet invalid XML.

**Validation:** All XML now well-formed; group names are checked against the
4.9.2 naming convention by the CI workflow. Next lab run: exercise each rule
with `wazuh-logtest` and real Sysmon events.
