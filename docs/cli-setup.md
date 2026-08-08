# Cursor CLI & GitHub Copilot CLI

Same migration engine — different cockpits. Type **`start`**, pick a menu item, fix only what the agent asks.

← [Getting started](getting-started.md) · [Using Cursor (IDE)](cursor-ui.md) · [Agent setup](agent-setup.md)

**Prefer pictures in the IDE?** → [cursor-ui.md](cursor-ui.md)  
**Track A walkthrough:** → [guided-demo.md](guided-demo.md)

---

## What’s different

| | Cursor IDE | Cursor CLI (`agent`) | Copilot CLI (`copilot`) |
|---|---|---|---|
| **Install** | [Cursor](https://cursor.com) app | [cursor.com/install](https://cursor.com/install) → `agent` | [Copilot CLI](https://github.com/github/copilot-cli) → `copilot` |
| **Auth** | Cursor account in the app | `agent login` (or `CURSOR_API_KEY`) | `/login` + Copilot subscription |
| **How this repo loads** | Named agents in `.cursor/agents/`; bare `start` via project rule | Open **repo root**; type `start` (no IDE agent picker) | Loads [`.github/copilot-instructions.md`](../.github/copilot-instructions.md); stage bodies in [`agents/github-copilot/`](../agents/github-copilot/) |
| **Parallel Convert** | Best UX (subagent fan-out) | Works; may be more sequential | Same caveat — follow coordinator prompt |
| **Best for** | First guided demo | Terminal / SSH / scripts (`agent -p`) | Terminal on a Copilot plan |
| **Unchanged** | Makefile, `.env`, preflight, disk under `agents/out/<run_id>/` | Same | Same |

**Track A is easiest in Cursor IDE.** CLIs are fine once you `cd` to the repo root and allow shell/tools.

Soft status from `start` is informational. Track A **preflight** (SqlPackage, sqlcmd, logins) runs only after you choose menu **1**.

---

## Shared first steps

1. Clone / open the folder that contains `README.md`, `Makefile`, and `.cursor/`.  
2. From that directory, start the CLI (below).  
3. Type **`start`** (or paste a [kickoff phrase](agent-setup.md#front-door--kickoff-sentences)).  
4. Allow terminal / tool use when prompted.  
5. Do **only** the remediation named (e.g. `az login`), then say **continue**.

Regenerate agent prompt copies anytime: `make sync-prompts`.

---

## Cursor CLI setup

```bash
# macOS / Linux / WSL
curl https://cursor.com/install -fsS | bash
# ensure ~/.local/bin is on PATH, then:
agent login
cd /path/to/edwmigration   # repo root
agent
```

Then type:

```text
start
```

Choose **1** for the guided demo. Non-interactive / scripts (use with care):

```bash
agent -p "start"
# file changes in print mode usually need --force — prefer interactive for Track A
```

Official docs: [Cursor CLI](https://cursor.com/docs/cli/overview) · [headless](https://cursor.com/docs/cli/headless).

---

## GitHub Copilot CLI setup

```bash
# macOS / Linux (see GitHub docs for brew / npm / WinGet)
curl -fsSL https://gh.io/copilot-install | bash
cd /path/to/edwmigration   # repo root
copilot
```

Authenticate when asked (`/login`). Trust the folder. Then type **`start`**.

If the model needs an explicit stage file:

```text
Follow agents/github-copilot/edw-start.md — run status and show the phrase menu.
```

After a choice, the same paths as IDE: `edw-demo-guide.md` (menu **1**) or `edw-coordinator.md` (menu **2** / **3**).

Workspace rules already live in [`.github/copilot-instructions.md`](../.github/copilot-instructions.md). Prefer **not** running `copilot init` / `/init` here — it may rewrite that file.

**Custom agents note:** Copilot CLI can also load agents from `.github/agents/`. This repo syncs portable copies to `agents/github-copilot/` via `make sync-prompts`. Point the CLI at those files (or `@` them) unless you later add a `.github/agents` sync.

Official docs: [Copilot CLI overview](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/overview) · [custom agents](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/invoke-custom-agents).

---

## Same phrases everywhere

| # | Say | Goes to |
|---|---|---|
| 1 | Set up the EDW demo and walk me through the migration. | Track A guide |
| 2 | Start an EDW migration run against my Azure SQL. | Coordinator |
| 3 | Migrate my Azure MySQL into catalog `<name>`… | Coordinator |
| 4–6 | URLs / teardown / enterprise | As in [getting-started](getting-started.md) |

---

## Next

→ [Guided demo](guided-demo.md) · [Your database](your-database.md) · [Prerequisites](prerequisites.md) · [Troubleshooting](troubleshooting.md)
