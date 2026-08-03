# Firewall: the `0.0.0.0/0` demo rule

`infra/azure/bootstrap.sh` (guided demo / `make bootstrap`) creates two firewall
rules on the Azure SQL logical server:

1. **`AllowClientLoad`** — your current public IP only. Used by `SqlPackage`
   and `sqlcmd` from your machine.
2. **`AllowDatabricksDemo`** — `0.0.0.0/0` (the entire public internet). Used
   by Databricks Free Edition to reach Azure SQL via Lakehouse Federation.

## Why `0.0.0.0/0`?

Databricks Free Edition is **AWS-hosted**, not Azure-hosted. The Azure SQL
"Allow Azure services" toggle only allows traffic from inside the same
Azure region; it does NOT allow traffic from AWS. Free Edition's outbound
NAT IPs are not published as a stable allowlist, so the only reliable way
to let Free Edition reach Azure SQL is to open the server to the public
internet.

This is acceptable for a **demo database** that contains only public sample
data (WideWorldImporters) and is torn down after the demo. It is **not**
acceptable for any database with real or sensitive data.

## Risk

- Anyone on the internet can attempt to connect to your SQL server on port
  1433.
- They still need the admin username + password (which you set in `.env` and
  never commit), so the data is not directly exposed.
- Brute-force attacks are possible. Azure SQL has built-in brute-force
  protection, but it is not a substitute for a closed firewall.

## Mitigations

1. **Tear down when done.** Ask `edw-demo-guide` to teardown, or run
   `./infra/azure/teardown.sh` — deletes the entire resource group, including
   the firewall rule.
2. **Use a strong admin password.** `materialize_demo_env.sh` generates one;
   do not weaken it.
3. **Optional: auto-delete the rule after 2 hours.** Example:

```bash
az sql server firewall-rule delete \
  --resource-group "$AZ_RG" \
  --server "$AZ_SQL_SERVER" \
  --name AllowDatabricksDemo
```

## Path B (existing Azure SQL)

For a real customer database, do **not** open `0.0.0.0/0`. Use private link,
VNet rules, or an allowlisted egress path appropriate to your Databricks tier.
The engine only needs a reachable SQL Server endpoint and a login that can
read base tables and export procedure definitions.
