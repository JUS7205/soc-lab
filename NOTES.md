# Lab journal

Running log of what broke, what I changed, and why. Newest first.

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
