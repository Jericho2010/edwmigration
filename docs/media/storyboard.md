# How to capture screenshots and the hero video

You need **two things**:

1. **Three Cursor screenshots** (overwrite the stand-in images in the docs).
2. **One short screen video**, then a **small GIF** for the README (GitHub does not play MP4 in the README usefully).

When files are in place, tell the agent: *Insert per docs/media/storyboard.md*.

Use **Track A**. Real UI only.

---

## Do this today

### Setup (once)

- [ ] Repo **root** open in Cursor (`README.md`, `Makefile`, `.cursor` visible).
- [ ] **`edw-demo-guide`** available (`make sync-prompts` if missing).
- [ ] `az login` + Databricks login (or PAT in `.env`).
- [ ] Browser can open Databricks (serverless warehouse exists).
- [ ] Control Plane + Genie already exist from a prior `make setup`.  
  If not: finish [guided demo](../guided-demo.md) setup, **then** come back to record.  
  Gate does **not** have to be green.

### Screenshots (~15 min)

- [ ] S1 → `docs/img/cursor_open_repo.png`
- [ ] S2 → `docs/img/cursor_pick_agent.png`
- [ ] S3 → `docs/img/cursor_kickoff.png`

### Video (~20–40 min)

**Pick one method. Do not mix instructions.**

- [ ] **Preferred:** one continuous recording (steps below).  
- [ ] **Or:** four clips, then join them in any editor (iMovie, Clips, CapCut, etc.).
- [ ] Export `docs/media/hero.mp4`
- [ ] Make `docs/img/hero.gif` from that MP4 (required for README — see GIF step). Keep GIF under ~12 MB if you can.

### Hand off

- [ ] Send the handoff block at the bottom.

---

## Screenshots

**All three:** PNG, roughly widescreen, Cursor only, readable when small. No `.env`, tokens, or passwords.

### S1 — Repo root → `docs/img/cursor_open_repo.png`

1. File → Open Folder → this repo root.  
2. Show the file tree.  
3. Visible: `README.md`, `Makefile`, `.cursor`.  
4. Screenshot.

### S2 — Agent selected → `docs/img/cursor_pick_agent.png`

1. Open Agent / Chat.  
2. Select **`edw-demo-guide`** so it is clearly the active agent.  
3. Screenshot. (Cursor’s picker UI varies by version — selection must be obvious.)

### S3 — Kickoff text → `docs/img/cursor_kickoff.png`

1. Clean chat with `edw-demo-guide`.  
2. Paste exactly: `Set up the EDW demo and walk me through the migration.`  
3. Screenshot with that text visible.  
4. For the **screenshot**, you can cancel/stop before a long run starts. The video section has its own rule for send vs cut.

---

## Video

**Files**

| File | Role |
|---|---|
| `docs/media/hero.mp4` | Full short video (for download / release / YouTube if large) |
| `docs/img/hero.gif` | What the README will show |

**Length after edits:** ~35–50 seconds. Silent is fine.

### Preferred: one continuous take

1. Start screen recorder (Cursor + browser on one screen or easy to switch).  
2. Cursor: `edw-demo-guide` visible → paste kickoff → **send**.  
3. Show tools starting for a few seconds, then **stop the agent / jump-cut**. Do **not** film bacpac, long bootstrap, or waiting.  
4. Terminal or Cursor: run `make print-urls` and show Control Plane + Genie links on screen (~3–5 seconds).  
5. Browser: open Control Plane → widgets visible.  
6. Browser: Genie → ask **Did the last run ship?** → answer visible.  
7. Stop recording. Trim to ~35–50s. Save as `docs/media/hero.mp4`.

### Alternative: four clips, then join

Record four separate files, then join **in this order** in any video editor:

| # | Record | Stop when |
|---|---|---|
| 1 | Cursor: paste + send kickoff | Tools just started |
| 2 | Terminal: `make print-urls` | Both URLs visible |
| 3 | Browser: Control Plane | Dashboard widgets visible |
| 4 | Browser: Genie Q&A | Answer visible |

Export the join as `docs/media/hero.mp4`.

**How to join (pick what you have):** macOS iMovie / QuickTime append, Windows Clipchamp, phone CapCut, or `ffmpeg` if you already use it. The storyboard will not teach every editor.

### Gate not green

Still film Control Plane + Genie. A real blocked/not-shipped answer is fine.

### Make the README GIF (required)

GitHub README will not usefully autoplay your MP4. You need a GIF:

```bash
ffmpeg -i docs/media/hero.mp4 -vf "fps=12,scale=960:-1:flags=lanczos" -loop 0 docs/img/hero.gif
```

No ffmpeg? Export a GIF from your editor, or ask the agent after you hand off the MP4.

If `hero.mp4` is huge (>50 MB), keep the GIF in git; put the MP4 on a GitHub Release or unlisted YouTube and say so in handoff Notes.

---

## Privacy

**Hide:** tokens, passwords, connection strings, subscription IDs.  
**OK:** agent names, kickoff sentence, catalog name, demo answers.

---

## Handoff

```text
CAPTURE COMPLETE
Date:
Cursor version:
Gate green: yes/no

Files:
- docs/img/cursor_open_repo.png
- docs/img/cursor_pick_agent.png
- docs/img/cursor_kickoff.png
- docs/media/hero.mp4
- docs/img/hero.gif          # or: agent please generate from MP4

Notes:
```

Then: *Insert per docs/media/storyboard.md*

---

## For the editor (after handoff)

1. Confirm the three PNGs overwritten.  
2. Confirm `docs/img/hero.gif` exists (generate from MP4 if missing).  
3. Under README Status, add:

```markdown
### See it

![Track A hero](docs/img/hero.gif)

*Track A · Cursor → Control Plane → Genie*  
[Full video](docs/media/hero.mp4) <!-- or Release / YouTube URL if MP4 not in git -->
```

4. In `docs/cursor-ui.md` and `docs/getting-started.md`, remove “illustration / stand-in / fake” wording.  
5. Set Status verification date to capture day.

---

## Related

- [Guided demo](../guided-demo.md)
- [Using Cursor](../cursor-ui.md)
