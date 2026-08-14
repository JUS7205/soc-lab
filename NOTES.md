# Lab journal

Running log of what broke, what I changed, and why. Newest first.

## 2026-08-11 — pulse tripwire demoed on the live box

- `pulse snapshot > baseline.json` (committed) captured the host process tree
  + TCP table (non-elevated run works).
- Spawned a throwaway `cmd.exe /c timeout /t 60` marker, took a second
  snapshot, ran `pulse diff` and `pulse verdict`: verdict **ALERT** with the
  marker chain (`cmd.exe` → `conhost.exe` → `timeout.exe`) plus a new
  external connection. The tripwire path works on real Windows.
- Note: agent-less logtest on the LIVE manager cannot exercise the sysmon
  chain (the base-rule 60000 patch used in the container validation is
  test-only; the live ruleset needs a real agent through the winevt channel).

## 2026-08-11 — Full stack brought up (indexer + manager + dashboard, 4.9.2)

`docker compose up -d` now runs the complete single-node stack on
Windows/Docker Desktop. Verified end to end:

- indexer answers on https://localhost:9200 with admin auth; cluster green
- manager: all daemons + API (55000) up; filebeat ships alerts to the indexer
  (wazuh-alerts-4.x index, 187 docs within minutes)
- custom rules confirmed loaded via API:
  `GET /rules?group=soclab` returns all three (100201/100202/100203,
  status enabled, from `etc/rules/local_rules.xml`); analysisd reports
  7010 rules enabled, zero errors
- dashboard on https://localhost:443: login page loads, `POST /auth/login`
  with admin/SecretPassword → 200 + session cookie (OSD 2.13 route —
  it's `/auth/login`, not `/api/auth/login`)

**Three real-world bugs found while bringing it up:**

1. **File bind-mount into a named volume poisons first-boot provisioning.**
   Mounting `custom-rules.xml` at `/var/ossec/etc/rules/local_rules.xml`
   made Docker create `/var/ossec/etc/rules/` inside the `wazuh_etc` volume,
   so the image init's "volume is empty?" check skipped copying the entire
   permanent etc tree — `etc/shared/ar.conf` never appeared and analysisd
   died (`ERROR (1103): Could not open file 'etc/shared/ar.conf'`). Fix:
   mount custom rules at `/wazuh-config-mount/etc/rules/local_rules.xml`
   (the image copies that dir over `/var/ossec` after provisioning).
   `docker compose down -v` once, then up.
2. **`wazuh/wazuh-certs-tool` image does not exist on Docker Hub.** Generated
   the certs with openssl instead (same DNs as the tool); committed as
   `scripts/gen-certs.sh`. DNs must match indexer `admin_dn`/`nodes_dn`
   exactly (`/C=US/L=California/O=Wazuh/OU=Wazuh/CN=<node>`).
3. **Key file permissions.** openssl writes keys 0600 as root; the indexer
   runs as uid 1000 and Docker Desktop preserves POSIX perms on bind mounts
   → "Unable to read wazuh.indexer.key". `chmod 644` the key/cert files
   (now done inside gen-certs.sh).

Also learned: manager API auth is JWT (`/security/user/authenticate` →
Bearer token), not basic auth; the OSD 2.13 login POST goes to `/auth/login`.

Screenshots are still pending (no browser available on the lab box) —
`https://localhost:443`, admin/SecretPassword.

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
