# Capture storyboard — hero video + real Cursor screenshots

Use this sheet to record assets once. Drop files into the paths below; an agent (or human) can then **replace mocks**, wire the README hero, and trim copy without re-thinking the narrative.

**Goal of the package**

1. **Three real Cursor screenshots** → replace illustrative art in [`docs/cursor-ui.md`](../cursor-ui.md) / [`docs/img/cursor_*.png`](../img/).  
2. **One hero video** (and optional GIF) → README “proof” strip under the Status line.

**Do not invent UI.** Capture your real Cursor + Databricks Free Edition session on **Track A**.

---

## Before you start (15–20 min)

| # | Prep | Done? |
|---|---|---|
| P1 | Repo open at **git root** in Cursor (`README.md`, `.cursor/` visible) | ☐ |
| P2 | `make sync-prompts` if agents missing; confirm `edw-demo-guide` appears | ☐ |
| P3 | `az login` + `databricks auth login` (or PAT in `.env`) | ☐ |
| P4 | Serverless warehouse exists; you can open Databricks UI in a browser | ☐ |
| P5 | Prefer a **clean** desktop: hide bookmarks bar noise, bump UI zoom to 110–125% | ☐ |
| P6 | Redaction plan: blur subscription IDs, PATs, full account emails if needed | ☐ |
| P7 | Create drop folder on your machine: `~/edw-capture-YYYYMMDD/` | ☐ |

**Recommended capture day:** run Track A far enough that Control Plane + Genie already exist (`make setup` / prior demo). Full bacpac import is optional for the *hero* cut if URLs already work — but a Gate-pass ending is stronger if you have time.

---

## Part A — Screenshots (Cursor UI)

Replace these exact filenames (keep names so docs links stay valid):

| Shot | Filename to overwrite | Used in |
|---|---|---|
| S1 | `docs/img/cursor_open_repo.png` | [cursor-ui.md](../cursor-ui.md) §1, getting-started |
| S2 | `docs/img/cursor_pick_agent.png` | [cursor-ui.md](../cursor-ui.md) §2 |
| S3 | `docs/img/cursor_kickoff.png` | [cursor-ui.md](../cursor-ui.md) §3 |

### Specs (all three)

- **Format:** PNG  
- **Aspect:** ~16:9 (e.g. 1920×1080 or 1600×900)  
- **Content:** Cursor window only (or lightly cropped). No second monitor junk.  
- **Text must be readable** at ~800px wide on GitHub.  
- Optional: also save uncropped masters as `docs/img/_masters/cursor_S1_raw.png` etc. (gitignored if huge — or keep local only).

### Shot S1 — Open repo root

| | |
|---|---|
| **Beat** | Prove the folder is the repo root |
| **Frame** | Cursor with **Explorer / file tree** visible |
| **Must show** | `README.md`, `Makefile`, `.cursor/` (expanded enough to see `agents` if possible) |
| **Nice** | Editor tab on `README.md` or empty welcome — not a random nested subfolder |
| **Avoid** | Secrets in open `.env`; terminal dumping passwords |
| **How** | File → Open Folder → repo root → screenshot |

### Shot S2 — Pick agent

| | |
|---|---|
| **Beat** | Prove custom agents load |
| **Frame** | Agent / Chat panel with agent list or selector |
| **Must show** | **`edw-demo-guide`** selected or clearly highlighted |
| **Nice** | `edw-coordinator` visible in the list |
| **Avoid** | Unrelated agent selected; empty list |
| **How** | Open Agent mode → open agent picker → select `edw-demo-guide` → screenshot |

### Shot S3 — Kickoff sentence

| | |
|---|---|
| **Beat** | Prove the one-sentence start |
| **Frame** | Composer / chat input with text pasted (not yet fully finished run) |
| **Must show** | Exact text: `Set up the EDW demo and walk me through the migration.` |
| **Nice** | Agent name `edw-demo-guide` visible above; “run tools” / terminal permission affordance if shown |
| **Avoid** | Mid-failure stack traces; huge wall of prior chat |
| **How** | New chat with demo-guide → paste kickoff → screenshot **before** or right as you send |

### Screenshot handoff checklist

Drop into the repo (or a zip for the agent):

```text
docs/img/cursor_open_repo.png      # S1 final
docs/img/cursor_pick_agent.png     # S2 final
docs/img/cursor_kickoff.png        # S3 final
```

Optional note file: `docs/media/CAPTURE_NOTES.md` with Cursor version + OS + date.

---

## Part B — Hero video (storyboard)

**Primary deliverable:** `docs/media/hero.mp4` (or `.webm`)  
**Optional for README inline:** `docs/img/hero.gif` (15–25s, &lt;8–12 MB if possible)

**Length target:** **35–50 seconds** (cuttable to 25s for GIF).  
**Audio:** optional voiceover; if silent, on-screen captions help.

### Sequence (record in one take or stitch)

| Time (approx) | Scene | Where | Action | On-screen focus / caption |
|---|---|---|---|---|
| **0:00–0:05** | Title beat | Cursor | Static or slow zoom on repo + agent name | Caption: *EDW → Databricks with an agent* |
| **0:05–0:12** | Kickoff | Cursor | Paste + send: *Set up the EDW demo…* | Show `edw-demo-guide` + sentence |
| **0:12–0:22** | Agent working | Cursor | Allow tools; scroll lightly as `make setup` / federation runs | Caption: *Agent wires catalog + Federation* — **skip long waits** (cut jump) |
| **0:22–0:32** | Control Plane | Browser Databricks | Open dashboard from `make print-urls` / Dashboards | Caption: *Control Plane* — Gate / inventory widgets visible |
| **0:32–0:42** | Genie | Browser Genie room | Ask: **Did the last run ship?** Show answer | Caption: *Genie: Did the last run ship?* |
| **0:42–0:50** | Close | Either | Brief return to Cursor or Gate summary counts | Caption: *Demo-ready · tear down when done* |

### If Gate isn’t green yet

Still record Control Plane + Genie. Prefer Genie answering about run status / blockers over a fake pass. Honesty &gt; fake ship.

### If bootstrap is too slow for one sitting

| Segment | Record separately | Stitch order |
|---|---|---|
| A | Cursor kickoff + tools starting | 1 |
| B | Jump cut to “Setup complete” + print-urls in terminal | 2 |
| C | Browser Control Plane | 3 |
| D | Browser Genie Q&A | 4 |

Name clips:

```text
docs/media/_raw/01_cursor_kickoff.mp4
docs/media/_raw/02_terminal_urls.mp4
docs/media/_raw/03_control_plane.mp4
docs/media/_raw/04_genie.mp4
```

(`_raw/` can stay local / gitignored — only finals need to be committed.)

### Video export specs

| Setting | Prefer |
|---|---|
| Resolution | 1920×1080 (or 1280×720 min) |
| Codec | H.264 MP4 |
| Frame rate | 30 fps |
| Cursor highlight | On (macOS/Windows built-in or Loom) |
| Browser zoom | 110–125% so Gate/Genie text reads on GIF |

### Optional GIF path

From the final MP4 (you or agent later):

```bash
# Example — adjust fps/width to keep size sane
ffmpeg -i docs/media/hero.mp4 -vf "fps=12,scale=960:-1:flags=lanczos" -loop 0 docs/img/hero.gif
```

---

## Part C — What goes on the README (for the editor later)

After assets land, the insert plan is:

1. Replace `docs/img/cursor_*.png` (no markdown path changes).  
2. Add under README **Status** block something like:

```markdown
### See it

[![Hero demo](docs/img/hero.gif)](docs/media/hero.mp4)

*35s · Track A · Cursor → Control Plane → Genie*
```

3. Link “full video” to `docs/media/hero.mp4` **or** unlisted YouTube if MP4 is too large for git (&gt;50–100MB → use release asset / YouTube, keep GIF in repo).  
4. Remove or demote illustrative language in `cursor-ui.md` (“illustration” → real UI).  
5. Bump Status date to capture day.

---

## Part D — Privacy / redaction

| Redact or crop | OK to show |
|---|---|
| `DATABRICKS_TOKEN`, passwords, connection strings | Catalog name like `edw_migration` |
| Full email if uncomfortable | Agent names, kickoff sentence |
| Subscription GUID in Azure portal | Databricks host *hostname* only if you’re fine with it |
| Customer data in Genie answers | Sample WWI / demo ops answers |

---

## Part E — Handoff to agent (“ready to edit and insert”)

When finished, send (or commit) this message shape:

```text
CAPTURE COMPLETE
Date: YYYY-MM-DD
Cursor version: …
Databricks: Free Edition
Track A Gate green: yes/no

Files ready:
- docs/img/cursor_open_repo.png
- docs/img/cursor_pick_agent.png
- docs/img/cursor_kickoff.png
- docs/media/hero.mp4   (and/or docs/img/hero.gif)
- (optional) docs/media/_raw/...

Notes for editor:
- …
```

Then ask: *Insert capture assets into README + cursor-ui per docs/media/storyboard.md*

---

## Quick day-of run sheet (print this)

1. ☐ Prep P1–P7  
2. ☐ S1 open root → save `cursor_open_repo.png`  
3. ☐ S2 pick `edw-demo-guide` → `cursor_pick_agent.png`  
4. ☐ S3 paste kickoff → `cursor_kickoff.png`  
5. ☐ Start screen recorder  
6. ☐ 0:00 title → kickoff → tools (jump cut waits)  
7. ☐ Browser Control Plane  
8. ☐ Genie: *Did the last run ship?*  
9. ☐ End card / teardown mention  
10. ☐ Export `hero.mp4` (+ optional `hero.gif`)  
11. ☐ Handoff checklist  

---

## Related

- [Guided demo](../guided-demo.md) — definition of done  
- [Using Cursor](../cursor-ui.md) — where screenshots land  
- [record_demo.sh](record_demo.sh) — terminal-only asciinema alternative (optional companion, not a substitute for UI hero)
