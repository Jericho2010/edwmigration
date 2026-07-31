# Makefile — one-command orchestration for the EDW migration demo.
#
#   make demo         — full path: prereqs → Azure → federation → deploy → job run
#   make demo-offline — same demo without Azure: seeded source_fed → deploy → run
#   make teardown     — delete the Azure resource group
#
# Requires .env (cp infra/azure/.env.example .env and edit). The .env file is
# included below, so its variables are visible to every target; keep values
# free of '#' and trailing spaces (Make comment rules apply).
# Detail and failure modes: docs/runbook.md.

SHELL := /usr/bin/env bash

-include .env
export

# DAB takes the warehouse as a bundle variable, not a plain env var.
BUNDLE_VAR_warehouse_id := $(DATABRICKS_WAREHOUSE_ID)
export BUNDLE_VAR_warehouse_id

TOOLS_CORE := databricks jq curl python3
TOOLS_AZURE := az sqlcmd SqlPackage

.PHONY: check check-core check-azure bootstrap federation deploy run demo demo-offline seed teardown offline-gate genie

check: check-azure ## Verify all tools and .env (core + Azure)

check-core: ## Verify Databricks-side tools and .env (offline mode needs only this)
	@for t in $(TOOLS_CORE); do \
		command -v $$t >/dev/null 2>&1 || { echo "missing tool: $$t — see docs/prerequisites.md" >&2; exit 1; }; \
	done
	@test -f .env || { echo ".env missing — cp infra/azure/.env.example .env and edit it" >&2; exit 1; }
	@test -n "$(DATABRICKS_HOST)" -a -n "$(DATABRICKS_TOKEN)" -a -n "$(DATABRICKS_WAREHOUSE_ID)" || \
		{ echo "DATABRICKS_HOST/TOKEN/WAREHOUSE_ID must be set in .env" >&2; exit 1; }
	@echo "core prereqs OK ($(TOOLS_CORE))"

check-azure: check-core ## Verify Azure-side tools and .env (online mode only)
	@for t in $(TOOLS_AZURE); do \
		command -v $$t >/dev/null 2>&1 || { echo "missing tool: $$t — see docs/prerequisites.md" >&2; exit 1; }; \
	done
	@test -n "$(AZ_SUBSCRIPTION_ID)" || { echo "AZ_SUBSCRIPTION_ID not set (source .env first: set -a; . ./.env; set +a)" >&2; exit 1; }
	@echo "azure prereqs OK ($(TOOLS_CORE) $(TOOLS_AZURE))"

bootstrap: check-azure ## Provision Azure SQL + load the bacpac + export procs/fixtures
	./infra/azure/bootstrap.sh

federation: check-azure ## UC federation setup + ops tables
	./agents/tools/render_federation_sql.sh > /tmp/01_fed.sql
	./agents/tools/run_sql.sh --file /tmp/01_fed.sql
	./agents/tools/run_sql.sh --file databricks/uc/03_ops_and_views.sql

deploy: check-core ## Bundle validate + deploy (dev target)
	databricks bundle validate -t dev
	@# Fresh-workspace quirk: the dashboard resource fails unless the bundle's
	@# resources folder already exists in the workspace.
	@USER=$$(databricks current-user me --output json | jq -r .userName); \
	databricks workspace mkdirs "/Workspace/Users/$$USER/.bundle/edw_migration/dev/resources"
	databricks bundle deploy -t dev

run: ## Run the medallion job
	databricks bundle run edw_migration_medallion -t dev

demo: check-azure bootstrap federation deploy run ## Full end-to-end setup (Azure-backed)
	@echo
	@echo "Infra ready. Next: open this repo in Cursor and launch edw-coordinator"
	@echo "(kickoff text in docs/runbook.md §6). Watch the AI/BI dashboard"
	@echo "'[dev] EDW Migration Agent Events'."

seed: check-core ## Offline source mode: seed source_fed + ops tables (no Azure)
	./databricks/offline/seed_source.sh
	./agents/tools/run_sql.sh --file databricks/uc/03_ops_and_views.sql

demo-offline: check-core seed deploy run ## Full demo without Azure: seed → deploy → run
	@echo
	@echo "Offline infra ready (source_fed seeded, no Azure). Next: edw-coordinator"
	@echo "in Cursor (docs/runbook.md §6), then optionally 'make genie'."

genie: check-core ## Create/update the "EDW Migration Copilot" Genie space (run after `run`)
	./databricks/genie/create_genie_space.sh

teardown: check-azure ## Delete the Azure resource group
	./infra/azure/teardown.sh

offline-gate: ## Seed sample artifacts for the offline Gate demo (no Azure)
	RUN_ID=00000000-0000-4000-8000-000000000001; \
	mkdir -p "agents/out/$$RUN_ID"; \
	cp agents/samples/run/* "agents/out/$$RUN_ID/"; \
	echo "$$RUN_ID" > agents/out/CURRENT_RUN; \
	./agents/tools/render_manifest_table.py "agents/out/$$RUN_ID/migration_manifest.json"
