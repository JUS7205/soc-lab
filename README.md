# soc-lab

[![CI](https://github.com/JUS7205/soc-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/JUS7205/soc-lab/actions/workflows/ci.yml)

A home SOC lab: **Wazuh** (single node) + **Sysmon** telemetry + custom
detection rules + hunt/triage playbooks. This is where I tune the rules in
[detection-rules](https://github.com/JUS7205/detection-rules) against real
Windows telemetry instead of intuition, and where the
[dfir-writeups](https://github.com/JUS7205/dfir-writeups) scenarios are built.

## Architecture

```text
Windows host --Sysmon E1/E3/E5/E7/E11/E13/E22--> Wazuh agent --> Wazuh manager
                                                       |--> Wazuh indexer
                                                       |--> Wazuh dashboard
Windows host --pulse snapshot/diff------------------> host drift baseline
```

| Layer | Component | Purpose |
| --- | --- | --- |
| Telemetry | Sysmon (events 1, 3, 5, 7, 11, 13, 22) | Process, network, file, registry, DNS visibility |
| Collection | Wazuh agent | Ships Windows events to the manager |
| Platform | Wazuh manager + indexer + dashboard (4.9) | Alerting, FIM, dashboards |
| Baseline | `pulse` snapshot/diff | Host drift tripwire (process tree + TCP table) |
| Detection | `custom-rules.xml` + Sigma conversions | The `detection-rules` repo mapped onto the lab |

## Quickstart

```sh
# 1. Bring up the Wazuh stack (single node, pinned 4.9)
docker compose -f wazuh/docker-compose.yml up -d

# 2. Install the Wazuh agent on the Windows host
#    (official installer; manager address from the compose output)

# 3. Ship Sysmon events into Wazuh
#    - Install Sysmon with sysmon/sysmon-config.xml
#    - Apply the agent ossec.conf snippets in wazuh/agent-ossec-snippets.conf

# 4. Load the custom detection rules
cp wazuh/custom-rules.xml /var/ossec/etc/rules/local_rules.xml

# 5. Build a host baseline with pulse
pulse snapshot > baseline.json
```

Generated files (indexer certs, dashboard settings) follow the official Wazuh
single-node quickstart and are intentionally not committed — the compose file
pins the layout and versions.

## What's in here

| Path | Content |
| --- | --- |
| `sysmon/sysmon-config.xml` | Minimal-but-meaningful Sysmon config (E1, E3, E5, E7, E11, E13, E22) |
| `wazuh/docker-compose.yml` | Single-node Wazuh stack (manager, indexer, dashboard), pinned 4.9.2 images |
| `wazuh/custom-rules.xml` | Custom rules keyed to the Wazuh 4.9.2 Sysmon groups: registry Run-key persistence, new external connections, suspicious child processes |
| `wazuh/agent-ossec-snippets.conf` | `ossec.conf` snippets: Sysmon channel, PowerShell 4104 channel |
| `playbooks/hunt-playbook.md` | Reusable daily threat-hunt checklist (ATT&CK-aligned) |
| `playbooks/triage-playbook.md` | Alert triage flow, first alert to containment |
| `NOTES.md` | Lab journal — what broke, what I changed, why |

## Sample detection chain

1. Sysmon E13 fires on `HKCU\...\Run` write (registry).
2. `custom-rules.xml` raises severity when the value points at a non-standard
   path like `AppData\Local\Temp`.
3. Cross-check: `pulse diff` shows a new external connection from the same
   host — the drift that ties the alert to a real chain.
4. Confirm with a `detection-rules` YARA scan of the dropped binary.

## Honest status

- The stack configs follow the official quickstart; the custom parts (rules,
  Sysmon config, playbooks, pulse integration) are original and versioned here.
- The custom rules are written against the Wazuh 4.9.2 Sysmon ruleset and
  validated (XML well-formedness, group names) in CI. Live validation with
  `wazuh-logtest` happens on the next lab run.
- Screenshots will be added to `docs/screenshots/` after the next rebuild.

## License

Apache-2.0 + Commons Clause. Commercial rights reserved to the copyright
owner — you may use/modify/host it freely for non-commercial purposes and as a
capability showcase, but may not sell it or a product derived from it without a
commercial license (see LICENSE).
