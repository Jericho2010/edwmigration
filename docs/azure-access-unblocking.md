# Azure access unblocking (Track A prep)

**When you need this:** Track A bootstrap fails because Azure CLI can see a subscription but cannot create resources — or `az` auth is stale.

This page is a reusable Entra / RBAC lesson: **why** each step matters, with placeholders for your tenant.

← [Guided demo](guided-demo.md) · [Troubleshooting](troubleshooting.md) · [Prerequisites](prerequisites.md)

---

## Goal

Track A bootstrap (`make bootstrap` / `edw-demo-guide`) needs a logged-in Azure CLI identity that can:

- create a resource group, SQL server, and free-offer Azure SQL database  
- set firewall rules  
- register `Microsoft.Sql` if needed  

Portal login alone is not enough; the agent and Makefile use `az`.

---

## Typical findings

| Observation | Why it mattered |
|---|---|
| Portal showed an **Active** subscription | Billing/subscription existence was fine |
| Local `az` refresh token was **expired** (~90 days inactive) | `az account show` could look OK from cache, but ARM calls failed with `AADSTS700082` |
| After a fresh login, your UPN could **see** the subscription but had **no RBAC** | Could not list resource groups or create resources (`AuthorizationFailed` on `resourcegroups/read`) |
| Your account is **Global Administrator** in Entra ID | Directory admin ≠ subscription Owner/Contributor until RBAC (or elevate) is applied |
| `Microsoft.Sql` was **NotRegistered** | SQL server/DB create would fail until the provider is registered |

**Remember: Global Admin in Entra ≠ Owner on the subscription.**

---

## Fix sequence (in order)

Replace placeholders with your values: `<tenant-id>`, `<subscription-id>`, `<upn>`, `<principal-object-id>`.

### 1. Fresh CLI login

```bash
az logout
az login --tenant <tenant-id> --use-device-code
az account set --subscription <subscription-id>
```

**Why:** Replace the stale refresh token so Management API calls work as `<upn>`.

### 2. Elevate access (Global Admin → Azure RBAC)

```bash
az rest --method POST \
  --url "https://management.azure.com/providers/Microsoft.Authorization/elevateAccess?api-version=2016-07-01"
```

**Why:** Global Admin does not automatically get rights on every subscription. Elevate grants temporary **User Access Administrator** at tenant root (`/`), which is enough to assign subscription roles.

| Role | Scope |
|---|---|
| User Access Administrator | `/` |

### 3. Assign subscription roles to your user

`az role assignment create` can fail immediately after elevate (token/propagation). Assigning via ARM REST with a fresh management token often succeeds:

- **Contributor** on the subscription — create/manage resources  
- **Owner** on the subscription — full control (including future role changes without elevate)

Use principal object ID: `<principal-object-id>` (from `az ad signed-in-user show --query id -o tsv`).

**Why:** Bootstrap needs resource create permission. Owner alone is enough; Contributor is the minimal create role.

### 4. Prove create works

Create and delete a short-lived probe resource group in your demo region (often `eastus` for the free SQL offer).

**Why:** Confirm RBAC is effective before spending time on bacpac bootstrap.

### 5. Register SQL provider

```bash
az provider register --namespace Microsoft.Sql --wait
```

**Why:** If `Microsoft.Sql` is `NotRegistered`, Track A cannot create Azure SQL resources.

---

## End state (ready for bootstrap)

- CLI identity: `<upn>` on your subscription (`Enabled`)  
- Roles: **Owner** or **Contributor** on the subscription (plus temporary User Access Administrator at `/` if you elevated)  
- `Microsoft.Sql`: **Registered**  
- Create probe: succeeded  

Still required for a full Track A run:

1. Databricks auth (`databricks auth login --host …` or PAT)  
2. Serverless SQL warehouse + `CREATE CONNECTION` / `CREATE CATALOG`  
3. Launch `edw-demo-guide` or `make bootstrap` / `make setup`

---

## Optional cleanup

Microsoft recommends removing elevated root access when finished assigning roles:

- Remove **User Access Administrator** at `/` for `<upn>` if you no longer need elevate  
- Keep **Owner** (or at least **Contributor**) on the subscription so bootstrap/teardown keep working  

After the demo: `make teardown` (or ask the guide) to delete the demo resource group and close the temporary `0.0.0.0/0` SQL firewall rule. See [firewall.md](firewall.md).

---

## If this happens again

1. `az login` (device code or browser) for the right tenant  
2. If you can see the sub but cannot `az group list` → check RBAC, not billing  
3. If you are Global Admin with no subscription role → `elevateAccess`, then assign **Owner** or **Contributor** to yourself  
4. `az provider register --namespace Microsoft.Sql` if SQL creates fail with provider errors  
