# config/

Generated configuration for the Wazuh stack. Everything here mirrors the
official Wazuh 4.9.2 single-node quickstart, so it stays reproducible.

| File | Purpose |
| --- | --- |
| `wazuh_indexer/wazuh.indexer.yml` | indexer opensearch.yml (TLS, single-node) |
| `wazuh_indexer/internal_users.yml` | pre-hashed security-plugin users matching the default quickstart passwords |
| `wazuh_dashboard/opensearch_dashboards.yml` | dashboard TLS + indexer connection |
| `wazuh_dashboard/wazuh.yml` | dashboard -> manager API connection (wazuh-wui user) |
| `wazuh_cluster/wazuh_manager.conf` | manager ossec.conf (remote, indexer integration, API) |
| `wazuh_indexer_ssl_certs/` | TLS certs — **generated, gitignored** |

## Certs (one-time, before first `docker compose up`)

The official `wazuh/wazuh-certs-tool` image is not published on Docker Hub,
so generate the same certificates with the repo script (requires openssl):

```sh
sh scripts/gen-certs.sh   # defaults to wazuh/config/wazuh_indexer_ssl_certs
```

or, in a container:

```sh
docker run --rm -v ${PWD}/wazuh/config/wazuh_indexer_ssl_certs:/out \
  -v ${PWD}/scripts/gen-certs.sh:/gen.sh:ro alpine:3.20 \
  sh -c "apk add --no-cache openssl >/dev/null && sh /gen.sh /out"
```

The script emits the root CA, `root-ca-manager.pem`, and cert/key pairs for
admin, wazuh.indexer, wazuh.manager and wazuh.dashboard using the same DNs as
the official cert tool.

## Secrets

Passwords are the documented quickstart defaults (admin / SecretPassword,
kibanaserver / kibanaserver, wazuh-wui / MyS3cr37P450r.*-). Change them
before exposing the stack beyond a lab: regenerate `internal_users.yml`
(`/usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh`) and
update the compose env + `wazuh.yml` to match.
