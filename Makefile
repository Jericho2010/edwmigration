# EDW migration — engine + optional guided demo
#
#   Track A (demo):   az login && databricks auth login → edw-demo-guide
#   Track B (MySQL):  SOURCE_TYPE=mysql in .env → make setup → edw-coordinator
#   Track B (SQL):    SOURCE_TYPE=sqlserver → make setup → edw-coordinator
#
SHELL := /usr/bin/env bash

-include .env
export

BUNDLE_VAR_warehouse_id := $(DATABRICKS_WAREHOUSE_ID)
BUNDLE_VAR_catalog := $(DATABRICKS_CATALOG)
export BUNDLE_VAR_warehouse_id
export BUNDLE_VAR_catalog

SOURCE_TYPE ?= sqlserver
TOOLS_CORE := databricks jq curl python3
TOOLS_AZURE := az sqlcmd SqlPackage

.PHONY: check check-core check-azure check-source render bootstrap setup federation secrets deploy run demo teardown genie materialize-demo sync-prompts discover print-urls

check: check-source

check-core:
	@for t in $(TOOLS_CORE); do \
		command -v $$t >/dev/null 2>&1 || { echo "missing tool: $$t — see docs/prerequisites.md" >&2; exit 1; }; \
	done
	@test -f .env || { echo ".env missing — run make materialize-demo or copy infra/azure/.env.example" >&2; exit 1; }
	@test -n "$(DATABRICKS_HOST)" -a -n "$(DATABRICKS_WAREHOUSE_ID)" -a -n "$(DATABRICKS_CATALOG)" || \
		{ echo "DATABRICKS_HOST, DATABRICKS_WAREHOUSE_ID, DATABRICKS_CATALOG required in .env" >&2; exit 1; }
	@echo "core prereqs OK"

# SqlPackage/sqlcmd/az — demo bootstrap and bacpac only (not required for make setup).
check-azure: check-core
	@for t in $(TOOLS_AZURE); do \
		command -v $$t >/dev/null 2>&1 || { echo "missing tool: $$t — see docs/prerequisites.md (needed for bootstrap/demo only)" >&2; exit 1; }; \
	done
	@test -n "$(AZ_SUBSCRIPTION_ID)$(AZ_SQL_SERVER)" || \
		{ echo "AZ_SUBSCRIPTION_ID (and AZ_SQL_SERVER) required for bootstrap" >&2; exit 1; }
	@echo "azure bootstrap prereqs OK"

# Connection fields only — no SqlPackage for either source type on setup.
check-source: check-core
	@st=$$(printf '%s' "$(SOURCE_TYPE)" | tr '[:upper:]' '[:lower:]'); \
	if [ "$$st" = "mysql" ]; then \
	  test -n "$(SOURCE_HOST)" -a -n "$(SOURCE_DATABASE)" -a -n "$(SOURCE_USER)" -a -n "$(SOURCE_PASSWORD)" || \
	    { echo "MySQL requires SOURCE_HOST, SOURCE_DATABASE, SOURCE_USER, SOURCE_PASSWORD in .env" >&2; exit 1; }; \
	  echo "mysql source prereqs OK"; \
	else \
	  host="$(SOURCE_HOST)"; \
	  if [ -z "$$host" ] && [ -n "$(AZ_SQL_HOST)" ]; then host="$(AZ_SQL_HOST)"; fi; \
	  if [ -z "$$host" ] && [ -n "$(AZ_SQL_SERVER)" ]; then host="$(AZ_SQL_SERVER).database.windows.net"; fi; \
	  pw="$(SOURCE_PASSWORD)"; \
	  if [ -z "$$pw" ]; then pw="$(AZ_SQL_PASSWORD)"; fi; \
	  db="$(SOURCE_DATABASE)"; \
	  if [ -z "$$db" ]; then db="$(AZ_SQL_DB)"; fi; \
	  user="$(SOURCE_USER)"; \
	  if [ -z "$$user" ]; then user="$(AZ_SQL_ADMIN)"; fi; \
	  test -n "$$host" -a -n "$$db" -a -n "$$user" -a -n "$$pw" || \
	    { echo "sqlserver requires SOURCE_HOST (or AZ_SQL_HOST/SERVER), SOURCE_DATABASE (or AZ_SQL_DB), SOURCE_USER (or AZ_SQL_ADMIN), SOURCE_PASSWORD (or AZ_SQL_PASSWORD)" >&2; exit 1; }; \
	  echo "sqlserver source prereqs OK (SqlPackage not required for setup)"; \
	fi

materialize-demo: ## Build .env from az + databricks login (guided demo)
	./agents/tools/materialize_demo_env.sh

render: check-core ## Render SQL templates into databricks/_rendered
	./agents/tools/render_sql.sh

secrets: check-core ## Upsert source password into Databricks secret scope
	./agents/tools/upsert_source_secret.sh

bootstrap: check-azure ## Provision free Azure SQL + WWI bacpac (demo pack)
	./infra/azure/bootstrap.sh

federation: secrets render ## UC federation + ops
	./agents/tools/run_sql.sh --file databricks/_rendered/uc/01_federation_setup.sql
	./agents/tools/run_sql.sh --file databricks/_rendered/uc/03_ops_and_views.sql
	./agents/tools/run_sql.sh --file databricks/_rendered/uc/02_federation_smoke.sql

print-urls: check-core ## Print Control Plane dashboard + Genie URLs
	./agents/tools/print_observability_urls.sh

setup: check-source federation deploy genie print-urls ## Wire sink + dashboard + genie
	@echo
	@echo "Setup complete. Catalog=$(DATABRICKS_CATALOG) SOURCE_TYPE=$(SOURCE_TYPE)"
	@echo "Next: launch edw-coordinator (or edw-demo-guide for the full walkthrough)."

deploy: render ## Bundle validate --strict + deploy
	@test -n "$(DATABRICKS_WAREHOUSE_ID)" || { echo "DATABRICKS_WAREHOUSE_ID required" >&2; exit 1; }
	databricks bundle validate --strict -t dev
	@USER=$$(databricks current-user me --output json | jq -r .userName); \
	databricks workspace mkdirs "/Workspace/Users/$$USER/.bundle/edw_migration/dev/resources" 2>/dev/null || true
	databricks bundle deploy -t dev

run: ## Run medallion job (requires generated land SQL)
	databricks bundle run edw_migration_medallion -t dev

demo: check-azure bootstrap setup ## Scripted demo path (non-interactive)
	@echo
	@echo "Demo infra ready. Open Cursor and launch edw-demo-guide or edw-coordinator."

genie: check-core ## Create/update Genie control-plane space
	./databricks/genie/create_genie_space.sh

teardown: check-azure ## Delete Azure resource group
	./infra/azure/teardown.sh

sync-prompts: ## Regenerate Cursor + Copilot agent files
	./agents/tools/sync_prompts.sh

discover: check-core ## Discover inventory for RUN_ID (usage: make discover RUN_ID=...)
	@test -n "$(RUN_ID)" || { echo "RUN_ID required" >&2; exit 1; }
	python3 agents/tools/discover_inventory.py --run-id "$(RUN_ID)"
	python3 agents/tools/generate_from_inventory.py --run-id "$(RUN_ID)"
	./agents/tools/render_sql.sh
