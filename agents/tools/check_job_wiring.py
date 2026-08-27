#!/usr/bin/env python3
"""Warn when backlog target_paths are not wired into the medallion job YAML.

By default prints WARN + a proposed YAML patch (dry-run). With --apply, writes a
safe patch: new silver/gold tasks inserted before reconcile. Parents come from
Assess reads/writes plus bronze_land. Independent tasks are packed so peak
concurrency stays ≤ 5.

Exit 0 on WARN / successful propose or apply. Exit 1 on usage errors, a cycle
in reads/writes, or when --apply would violate the concurrency limit.

Usage:
  python3 agents/tools/check_job_wiring.py --run-id UUID
  python3 agents/tools/check_job_wiring.py --backlog path/to/migration_backlog.json
  python3 agents/tools/check_job_wiring.py --run-id UUID --apply
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from slugify import _clean, slugify_ident  # noqa: E402

JOB_YAML = ROOT / "databricks" / "jobs" / "edw_migration_medallion.yml"
MAX_CONCURRENCY = 5
ENGINE_TASKS = frozenset(
    {"federation_smoke", "bronze_land", "stage_fixtures", "reconcile", "lineage_check"}
)
PATH_RE = re.compile(
    r"(?:databricks|_rendered)/(?:silver|gold)/[A-Za-z0-9_.-]+\.sql"
)
TASK_KEY_LINE_RE = re.compile(r"^([ \t]*)- task_key:\s*(\S+)[ \t]*$", re.M)
DEPENDS_ITEM_RE = re.compile(r"^[ \t]*- task_key:\s*(\S+)[ \t]*$", re.M)


class ConcurrencyLimitError(ValueError):
    """Raised when a proposed patch would exceed Free Edition concurrency."""


class CycleError(ValueError):
    """Raised when Assess reads/writes form a cycle."""


@dataclass
class ProposedTask:
    task_key: str
    repo_path: str
    job_path: str
    depends_on: list[str]
    timeout_seconds: int = 1800


@dataclass
class PatchProposal:
    tasks: list[ProposedTask] = field(default_factory=list)
    reconcile_depends_on: list[str] = field(default_factory=list)
    noop: bool = False

    def render_preview(self) -> str:
        if self.noop or not self.tasks:
            return ""
        lines = ["# proposed tasks (insert before reconcile):"]
        for t in self.tasks:
            lines.append(format_task_yaml(t).rstrip())
        lines.append("# reconcile.depends_on will include:")
        for key in self.reconcile_depends_on:
            lines.append(f"  - task_key: {key}")
        return "\n".join(lines)


def normalize_repo_path(raw: str) -> str:
    """Map job ../_rendered/silver/X.sql → databricks/silver/X.sql."""
    s = raw.strip().strip('"').strip("'")
    s = s.replace("../_rendered/", "databricks/")
    if s.startswith("_rendered/"):
        s = "databricks/" + s[len("_rendered/") :]
    if "/silver/" in s or "/gold/" in s:
        m = re.search(r"(silver|gold)/([^/]+\.sql)$", s)
        if m:
            return f"databricks/{m.group(1)}/{m.group(2)}"
    return s


def repo_path_to_job_path(repo_path: str) -> str:
    """Map databricks/gold/X.sql → ../_rendered/gold/X.sql."""
    p = normalize_repo_path(repo_path)
    m = re.search(r"(silver|gold)/([^/]+\.sql)$", p)
    if not m:
        raise ValueError(f"not a silver/gold path: {repo_path}")
    return f"../_rendered/{m.group(1)}/{m.group(2)}"


def task_key_for_path(repo_path: str, existing_keys: set[str]) -> str:
    """Build a unique task_key from databricks/<layer>/<file>.sql."""
    p = normalize_repo_path(repo_path)
    m = re.search(r"(silver|gold)/([^/]+)\.sql$", p)
    if not m:
        raise ValueError(f"not a silver/gold path: {repo_path}")
    layer, stem = m.group(1), m.group(2)
    stem = re.sub(r"[^A-Za-z0-9_]+", "_", stem).strip("_").lower()
    base = f"{layer}_{stem}"
    if base not in existing_keys:
        return base
    n = 2
    while f"{base}_{n}" in existing_keys:
        n += 1
    return f"{base}_{n}"


def job_wired_paths(job_path: Path | str) -> set[str]:
    text = job_path if isinstance(job_path, str) else Path(job_path).read_text()
    found: set[str] = set()
    for match in PATH_RE.findall(text):
        found.add(normalize_repo_path(match))
    for m in re.finditer(r"path:\s*(\S+\.sql)", text):
        found.add(normalize_repo_path(m.group(1)))
    return found


def backlog_targets(backlog: list[dict]) -> list[str]:
    paths: list[str] = []
    for item in backlog:
        status = (item.get("status") or "").lower()
        layer = (item.get("target_layer") or "").lower()
        if status == "blocked" or layer == "n/a":
            continue
        tp = item.get("target_path") or ""
        if tp:
            paths.append(str(tp))
    return paths


def table_tokens(raw: str) -> set[str]:
    """Normalize Assess reads/writes into comparable landing-name tokens."""
    out: set[str] = set()
    for part in re.split(r"[,;]+", raw or ""):
        part = part.strip().strip("`[]'\"")
        if not part:
            continue
        bits = [b.strip().strip("`[]'\"") for b in re.split(r"\.", part) if b.strip()]
        if not bits:
            continue
        if len(bits) >= 2:
            schema, name = bits[-2], bits[-1]
            out.add(slugify_ident(schema, name))
            out.add(_clean(name))
            out.add(_clean(f"{schema}_{name}"))
        else:
            out.add(_clean(bits[0]))
    return {t for t in out if t}


def _task_blocks(job_text: str) -> list[tuple[str, str, int, int]]:
    """Return (task_key, block_text, start, end) for each top-level task."""
    matches = list(TASK_KEY_LINE_RE.finditer(job_text))
    task_matches = [m for m in matches if m.group(0).lstrip().startswith("- task_key:")]
    if not task_matches:
        return []
    indents = {len(m.group(1)) for m in task_matches}
    task_indent = min(indents)
    task_matches = [m for m in task_matches if len(m.group(1)) == task_indent]

    blocks: list[tuple[str, str, int, int]] = []
    for i, m in enumerate(task_matches):
        start = m.start()
        end = task_matches[i + 1].start() if i + 1 < len(task_matches) else len(job_text)
        block = job_text[start:end]
        key = m.group(2)
        blocks.append((key, block, start, end))
    return blocks


def parse_tasks(job_text: str) -> list[dict]:
    """Parse task_key + depends_on from job YAML text (stdlib, best-effort)."""
    tasks: list[dict] = []
    for key, block, _s, _e in _task_blocks(job_text):
        deps: list[str] = []
        dep_m = re.search(r"depends_on:\s*\n((?:\s+- task_key:\s*\S+\s*\n)+)", block)
        if dep_m:
            deps = DEPENDS_ITEM_RE.findall(dep_m.group(1))
        path_m = re.search(r"path:\s*(\S+\.sql)", block)
        tasks.append(
            {
                "task_key": key,
                "depends_on": deps,
                "path": path_m.group(1) if path_m else None,
            }
        )
    return tasks


def peak_concurrency(tasks: list[dict]) -> int:
    """Estimate peak parallel tasks assuming unit-time waves."""
    waves = compute_ready_waves(tasks)
    return max((len(w) for w in waves), default=0)


def compute_ready_waves(tasks: list[dict]) -> list[list[str]]:
    """Unit-time ready sets (same assumptions as peak_concurrency)."""
    if not tasks:
        return []
    keys = {t["task_key"] for t in tasks}
    deps: dict[str, set[str]] = {
        t["task_key"]: {d for d in t.get("depends_on") or [] if d in keys}
        for t in tasks
    }
    remaining = set(keys)
    waves: list[list[str]] = []
    while remaining:
        ready = sorted(k for k in remaining if not deps[k])
        if not ready:
            waves.append(sorted(remaining))
            break
        waves.append(ready)
        for k in ready:
            remaining.remove(k)
        done = set(ready)
        for k in remaining:
            deps[k] -= done
    return waves


def existing_task_keys(job_text: str) -> set[str]:
    return {t["task_key"] for t in parse_tasks(job_text)}


def reconcile_depends_on(job_text: str) -> list[str]:
    for key, block, _s, _e in _task_blocks(job_text):
        if key == "reconcile":
            dep_m = re.search(
                r"depends_on:\s*\n((?:\s+- task_key:\s*\S+\s*\n)+)", block
            )
            if dep_m:
                return DEPENDS_ITEM_RE.findall(dep_m.group(1))
            return []
    return []


def path_to_task_key(job_text: str, repo_path: str) -> str | None:
    want = normalize_repo_path(repo_path)
    for t in parse_tasks(job_text):
        p = t.get("path")
        if p and normalize_repo_path(p) == want:
            return t["task_key"]
    return None


def convert_leaves(tasks: list[dict]) -> list[str]:
    conv_keys = {t["task_key"] for t in tasks if t["task_key"] not in ENGINE_TASKS}
    used_as_parent: set[str] = set()
    for t in tasks:
        if t["task_key"] in ENGINE_TASKS:
            continue
        for d in t.get("depends_on") or []:
            if d in conv_keys:
                used_as_parent.add(d)
    return sorted(k for k in conv_keys if k not in used_as_parent)


def _item_by_path(backlog: list[dict] | None) -> dict[str, dict]:
    out: dict[str, dict] = {}
    if not backlog:
        return out
    for item in backlog:
        tp = item.get("target_path") or ""
        if tp:
            out[normalize_repo_path(str(tp))] = item
    return out


def _convert_parents_for_path(
    path: str,
    *,
    job_text: str,
    backlog: list[dict] | None,
    path_keys: dict[str, str],
) -> set[str]:
    """Task keys this convert item must wait on (excluding bronze_land)."""
    parents: set[str] = set()
    by_path = _item_by_path(backlog)
    item = by_path.get(normalize_repo_path(path))
    if item is None or not backlog:
        return parents
    reads = table_tokens(str(item.get("reads") or ""))
    if not reads:
        return parents
    for other in backlog:
        otp = other.get("target_path") or ""
        if not otp or normalize_repo_path(str(otp)) == normalize_repo_path(path):
            continue
        writes = table_tokens(str(other.get("writes") or ""))
        if not (reads & writes):
            continue
        key = path_keys.get(normalize_repo_path(str(otp)))
        if key is None:
            key = path_to_task_key(job_text, str(otp))
        if key:
            parents.add(key)
    return parents


def _assert_no_cycle(nodes: dict[str, set[str]]) -> None:
    remaining = {k: set(v) for k, v in nodes.items()}
    while remaining:
        ready = [k for k, deps in remaining.items() if not deps]
        if not ready:
            raise CycleError(
                "reads/writes cycle among convert items: " + ", ".join(sorted(remaining))
            )
        done = set(ready)
        for k in done:
            del remaining[k]
        for deps in remaining.values():
            deps -= done


def propose_patch(
    job_text: str,
    missing_paths: list[str],
    *,
    serialize: bool = True,
    backlog: list[dict] | None = None,
) -> PatchProposal:
    wired = job_wired_paths(job_text)
    missing = [
        p
        for p in sorted(
            {normalize_repo_path(x) for x in missing_paths},
            key=lambda p: (0 if "/silver/" in p else 1, p),
        )
        if p not in wired
    ]

    if not missing:
        return PatchProposal(noop=True)

    keys = existing_task_keys(job_text)
    path_keys: dict[str, str] = {}
    for t in parse_tasks(job_text):
        if t.get("path"):
            path_keys[normalize_repo_path(t["path"])] = t["task_key"]
    for path in missing:
        key = task_key_for_path(path, keys)
        keys.add(key)
        path_keys[path] = key

    logical: dict[str, set[str]] = {}
    for path in missing:
        key = path_keys[path]
        logical[key] = _convert_parents_for_path(
            path, job_text=job_text, backlog=backlog, path_keys=path_keys
        )
        # Only keep deps that are other convert keys we know (new or already wired)
        logical[key] = {d for d in logical[key] if d in keys or d in logical}

    _assert_no_cycle(logical)

    bronze = "bronze_land" if "bronze_land" in existing_task_keys(job_text) else None
    tasks: list[ProposedTask] = []

    if not serialize:
        for path in missing:
            key = path_keys[path]
            depends = sorted(logical[key])
            if bronze:
                depends = [bronze] + [d for d in depends if d != bronze]
            tasks.append(
                ProposedTask(
                    task_key=key,
                    repo_path=path,
                    job_path=repo_path_to_job_path(path),
                    depends_on=depends,
                    timeout_seconds=1800,
                )
            )
    else:
        remaining = set(path_keys[p] for p in missing)
        done: set[str] = {
            t["task_key"]
            for t in parse_tasks(job_text)
            if t["task_key"] not in ENGINE_TASKS
        }
        prev_wave: list[str] = []
        while remaining:
            ready = sorted(
                k for k in remaining if logical.get(k, set()) <= done
            )
            if not ready:
                raise CycleError(
                    "cannot schedule convert tasks (unresolved parents): "
                    + ", ".join(sorted(remaining))
                )
            wave = ready[:MAX_CONCURRENCY]
            key_to_path = {path_keys[p]: p for p in missing}
            for key in wave:
                path = key_to_path[key]
                depends = set(logical.get(key, set()))
                if bronze:
                    depends.add(bronze)
                if prev_wave:
                    depends.update(prev_wave)
                tasks.append(
                    ProposedTask(
                        task_key=key,
                        repo_path=path,
                        job_path=repo_path_to_job_path(path),
                        depends_on=sorted(depends),
                        timeout_seconds=1800,
                    )
                )
            for key in wave:
                remaining.remove(key)
                done.add(key)
            prev_wave = list(wave)

    # Reconcile waits on convert leaves of the patched graph
    proposed_as_tasks = [
        {"task_key": t.task_key, "depends_on": t.depends_on, "path": t.job_path}
        for t in tasks
    ]
    combined = [
        t
        for t in parse_tasks(job_text)
        if t["task_key"] not in ENGINE_TASKS
    ] + proposed_as_tasks
    leaves = convert_leaves(combined)
    if not leaves:
        new_recon = [bronze] if bronze else list(reconcile_depends_on(job_text))
    else:
        new_recon = leaves

    return PatchProposal(tasks=tasks, reconcile_depends_on=new_recon, noop=False)


def format_task_yaml(task: ProposedTask) -> str:
    lines = [f"        - task_key: {task.task_key}"]
    if task.depends_on:
        lines.append("          depends_on:")
        for dep in task.depends_on:
            lines.append(f"            - task_key: {dep}")
    lines.append(f"          timeout_seconds: {task.timeout_seconds}")
    lines.append("          sql_task:")
    lines.append("            file:")
    lines.append(f"              path: {task.job_path}")
    lines.append("            warehouse_id: ${var.warehouse_id}")
    lines.append("")
    lines.append("")
    return "\n".join(lines)


def _replace_reconcile_depends(job_text: str, new_deps: list[str]) -> str:
    blocks = _task_blocks(job_text)
    recon = next((b for b in blocks if b[0] == "reconcile"), None)
    if recon is None:
        raise ValueError("job YAML has no reconcile task")
    key, block, start, end = recon
    dep_block = "          depends_on:\n"
    for d in new_deps:
        dep_block += f"            - task_key: {d}\n"

    if re.search(r"[ \t]*depends_on:\s*\n(?:[ \t]*- task_key:\s*\S+[ \t]*\n)+", block):
        new_block = re.sub(
            r"[ \t]*depends_on:\s*\n(?:[ \t]*- task_key:\s*\S+[ \t]*\n)+",
            dep_block,
            block,
            count=1,
        )
    else:
        new_block = re.sub(
            r"(^\s*- task_key:\s*reconcile\s*\n)",
            r"\1" + dep_block,
            block,
            count=1,
            flags=re.M,
        )
    return job_text[:start] + new_block + job_text[end:]


def apply_patch(
    job_text: str,
    missing_paths: list[str],
    *,
    serialize: bool = True,
    backlog: list[dict] | None = None,
) -> str:
    """Return job YAML with missing paths wired; raises ConcurrencyLimitError."""
    proposal = propose_patch(
        job_text, missing_paths, serialize=serialize, backlog=backlog
    )
    if proposal.noop or not proposal.tasks:
        return job_text

    blocks = _task_blocks(job_text)
    recon = next((b for b in blocks if b[0] == "reconcile"), None)
    if recon is None:
        raise ValueError("job YAML has no reconcile task")
    _key, _block, recon_start, _end = recon

    insertion = "".join(format_task_yaml(t) for t in proposal.tasks)
    if not insertion.endswith("\n\n"):
        insertion = insertion.rstrip() + "\n\n"

    patched = job_text[:recon_start] + insertion + job_text[recon_start:]
    patched = _replace_reconcile_depends(patched, proposal.reconcile_depends_on)

    tasks = parse_tasks(patched)
    peak = peak_concurrency(tasks)
    if peak > MAX_CONCURRENCY:
        raise ConcurrencyLimitError(
            f"patch would raise peak concurrency to {peak} (max {MAX_CONCURRENCY})"
        )
    return patched


def print_proposal(missing: list[str], proposal: PatchProposal) -> None:
    for path in missing:
        print(f"  WARN not in job: {path}")
    preview = proposal.render_preview()
    if preview:
        print("[check_job_wiring] proposed patch (dry-run; pass --apply to write):")
        print(preview)


def main_with_args(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-id", help="Load agents/out/<run_id>/migration_backlog.json")
    ap.add_argument("--backlog", help="Path to migration_backlog.json")
    ap.add_argument(
        "--job",
        default=str(JOB_YAML.relative_to(ROOT)),
        help="Job YAML path (default: medallion job)",
    )
    ap.add_argument(
        "--apply",
        action="store_true",
        help="Write a safe YAML patch wiring missing paths into the job",
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="Print proposal only (default when --apply is omitted)",
    )
    args = ap.parse_args(argv)

    if args.backlog:
        backlog_path = Path(args.backlog)
        if not backlog_path.is_absolute():
            backlog_path = ROOT / backlog_path
    elif args.run_id:
        backlog_path = ROOT / "agents" / "out" / args.run_id / "migration_backlog.json"
    else:
        print(
            "[check_job_wiring] provide --run-id or --backlog",
            file=sys.stderr,
        )
        return 1

    if not backlog_path.is_file():
        print(f"[check_job_wiring] backlog not found: {backlog_path}", file=sys.stderr)
        return 1

    job_path = Path(args.job)
    if not job_path.is_absolute():
        job_path = ROOT / job_path
    if not job_path.is_file():
        print(f"[check_job_wiring] job YAML not found: {job_path}", file=sys.stderr)
        return 1

    backlog = json.loads(backlog_path.read_text())
    if not isinstance(backlog, list):
        print("[check_job_wiring] backlog must be a JSON array", file=sys.stderr)
        return 1

    job_text = job_path.read_text()
    wired = job_wired_paths(job_text)
    targets = backlog_targets(backlog)
    missing = sorted({t for t in targets if t not in wired})

    if not targets:
        print("[check_job_wiring] OK no convertible backlog paths to check")
        return 0

    if not missing:
        print(
            f"[check_job_wiring] OK all {len(targets)} backlog path(s) "
            f"appear in {job_path.relative_to(ROOT) if job_path.is_relative_to(ROOT) else job_path}"
        )
        return 0

    rel_job = (
        job_path.relative_to(ROOT) if job_path.is_relative_to(ROOT) else job_path
    )
    print(
        f"[check_job_wiring] WARN {len(missing)} backlog path(s) not wired "
        f"into {rel_job} — Gate may pass SQL files the job "
        f"does not run (see docs/limits.md):"
    )

    try:
        proposal = propose_patch(job_text, missing, backlog=backlog)
    except (ValueError, CycleError) as exc:
        print(f"[check_job_wiring] ERROR {exc}", file=sys.stderr)
        return 1

    if args.apply:
        try:
            patched = apply_patch(job_text, missing, backlog=backlog)
        except ConcurrencyLimitError as exc:
            print(f"[check_job_wiring] ERROR {exc}", file=sys.stderr)
            print_proposal(missing, proposal)
            return 1
        except (ValueError, CycleError) as exc:
            print(f"[check_job_wiring] ERROR {exc}", file=sys.stderr)
            return 1
        tmp = job_path.with_suffix(job_path.suffix + ".tmp")
        tmp.write_text(patched)
        tmp.replace(job_path)
        print(
            f"[check_job_wiring] APPLIED {len(proposal.tasks)} task(s) → {rel_job}"
        )
        for t in proposal.tasks:
            print(f"  + {t.task_key}: {t.job_path}")
        return 0

    print_proposal(missing, proposal)
    return 0


def main() -> int:
    return main_with_args()


if __name__ == "__main__":
    raise SystemExit(main())
