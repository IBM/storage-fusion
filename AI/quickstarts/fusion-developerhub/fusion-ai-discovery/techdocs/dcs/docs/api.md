# DCS REST API Reference

## Authentication

DCS uses token-based authentication. Get a token against your cluster's DCS console Route:

```bash
TOKEN=$(curl -s -u sdadmin:<password> \
  https://console-ibm-data-cataloging.apps.<domain>/auth/v1/token \
  -D - | grep x-auth-token | awk '{print $2}' | tr -d '\r')
```

Replace `<domain>` with your cluster's OCP apps domain (visible in the catalog entry Links tab).

Then pass as a header on every subsequent request:
```bash
-H "x-auth-token: ${TOKEN}"
```

## Core Endpoints

| Path | Method | Auth | Description |
|---|---|---|---|
| `/auth/v1/token` | GET | Basic | Obtain auth token |
| `/connmgr/v1/connections` | GET | x-auth-token | List data source connections |
| `/policyengine/v1/policies` | GET | x-auth-token | List scan/classification policies |
| `/api/v1/metadata` | GET | x-auth-token | Query metadata catalog |

## Via RHDH Proxy

All endpoints are accessible without VPN via the RHDH proxy. Use `<cluster-id>` from the catalog entity name:

```bash
curl https://<rhdh-host>/api/proxy/fusion-<cluster-id>-dcs/connmgr/v1/connections \
  -H "x-auth-token: ${TOKEN}"
```

The proxy strips the `/api/proxy/fusion-<cluster-id>-dcs` prefix before forwarding to the DCS console Route.

## IBM Documentation

- [Data Cataloging REST API — IBM Docs](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=services-data-cataloging)
