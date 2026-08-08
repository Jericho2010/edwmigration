# Using Cursor with this repo

Follow these three steps: open the root, type **`start`**, pick a number.

← [Getting started](getting-started.md) · [Agent setup](agent-setup.md) · [Capture storyboard](media/storyboard.md)

---

## 1. Open the repository root

**File → Open Folder…** and choose the folder that contains `README.md`, `Makefile`, and `.cursor/` — not a subfolder.

![Open the repo root in Cursor](img/cursor_open_repo.png)

If you open a nested folder, agents under `.cursor/agents/` may not load.

---

## 2. Type `start` (or pick an agent)

Open **Chat** or **Agent** mode. Type **`start`**, or select:

- **`edw-start`** — status + phrase menu (recommended)  
- **`edw-demo-guide`** for the [guided demo](guided-demo.md)  
- **`edw-coordinator`** for [your database](your-database.md)  

![Agent picker — prefer edw-start, or edw-demo-guide / edw-coordinator](img/cursor_pick_agent.png)

*Screenshot may still show an older agent pick; the recommended first message is simply `start`.*

Missing agents? Run `make sync-prompts` at the repo root, then reload the window.

---

## 3. Choose from the menu (or paste a kickoff)

Reply with **`1`** for Track A, or paste:

> Set up the EDW demo and walk me through the migration.

Allow terminal / tool use when Cursor asks so the agent can run `make` and repo scripts.

![Chat after start — reply with 1 or paste the demo phrase](img/cursor_kickoff.png)

*If the screenshot still shows only a pasted kickoff (no menu), that path still works; typing `start` first is preferred.*

---

## What good looks like (first 10 minutes)

- Soft status appears (informational only — not the same as Track A preflight)  
- After you choose **1**, Track A preflight (`preflight_track_a.sh`) may ask for a single login or install — do that, then say continue  
- It writes or updates `.env`  
- Later it prints **Control Plane** and **Genie** URLs (`make print-urls`)  

Full walkthrough: [guided-demo.md](guided-demo.md) · Copilot: [agent-setup.md](agent-setup.md#github-copilot)

---

## UI labels move

Cursor renames Chat / Agent panels between versions. The idea stays: **open repo root → type `start` → pick a menu item → allow tools**.
