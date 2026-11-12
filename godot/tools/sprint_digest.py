#!/usr/bin/env python3
"""Writes a short, committed digest of what every agent of the running sprint workflow has done, so a new session can resume mid-wave.

  python3 godot/tools/sprint_digest.py [hours]       (default: workflow runs touched in the last 12 hours)

Output (small text files, safe to commit; the raw transcripts are far too big and live only in the container):
  docs/sprint/progress/AUTO_INDEX.md        every agent: label, status, first and last activity, events
  docs/sprint/progress/auto_<label>.md      per agent: last notes, recent steps, files it edited, final report when it finished

Agents also keep their own notes in docs/sprint/progress/<label>.md (rule in docs/ROUND6.md). godot/tools/wip_snapshot.sh runs this first.
"""
import glob
import json
import os
import sys
import time

HOURS = float(sys.argv[1]) if len(sys.argv) > 1 else 12.0
HOME = os.path.expanduser("~")
ROOT = os.path.join(HOME, ".claude", "projects")
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(REPO, "docs", "sprint", "progress")


def short(s, n):
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[: n - 3] + "..."


def agent_rows(path):
    rows = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    rows.append(json.loads(line))
                except Exception:
                    pass
    except OSError:
        pass
    return rows


def digest_agent(run_dir, agent_id, label, status, result):
    rows = agent_rows(os.path.join(run_dir, "agent-%s.jsonl" % agent_id))
    notes, steps, files = [], [], []
    first_ts = last_ts = ""
    for r in rows:
        ts = r.get("timestamp", "") or ""
        if ts:
            first_ts = first_ts or ts
            last_ts = ts
        m = r.get("message", {}) or {}
        c = m.get("content")
        if not isinstance(c, list):
            continue
        for b in c:
            if b.get("type") == "text" and m.get("role") == "assistant":
                notes.append((ts[11:19], short(b.get("text", ""), 420)))
            elif b.get("type") == "tool_use":
                inp = b.get("input", {}) or {}
                desc = inp.get("description") or inp.get("command") or inp.get("file_path") or inp.get("query") or ""
                steps.append((ts[11:19], short(desc, 170)))
                fp = inp.get("file_path")
                if fp and b.get("name") in ("Edit", "Write") and fp not in files:
                    files.append(fp)
    lines = ["# %s (%s)" % (label, status), "",
             "agent id %s, %d events, first activity %s, last activity %s" % (agent_id, len(rows), first_ts, last_ts), ""]
    if result:
        lines += ["## Final report", "", short(result, 3000), ""]
    lines += ["## Last notes of the agent", ""]
    lines += ["- %s %s" % t for t in notes[-6:]] or ["- (none)"]
    lines += ["", "## Recent steps (last 40)", ""]
    lines += ["- %s %s" % t for t in steps[-40:]] or ["- (none)"]
    lines += ["", "## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)", ""]
    lines += ["- " + f.replace(REPO + "/", "") for f in files[-80:]] or ["- (none)"]
    body = "\n".join(lines) + "\n"
    safe = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in label)
    with open(os.path.join(OUT, "auto_%s.md" % safe), "w", encoding="utf-8") as f:
        f.write(body[:14000])
    return len(rows), first_ts, last_ts


def main():
    os.makedirs(OUT, exist_ok=True)
    cutoff = time.time() - HOURS * 3600
    index = ["# Sprint agents (automatic digest)", "",
             "Written by godot/tools/sprint_digest.py at %s. Status 'running' means no final report had been written when the digest was made." % time.strftime("%Y-%m-%d %H:%MZ", time.gmtime()), ""]
    runs = sorted(glob.glob(os.path.join(ROOT, "*", "*", "subagents", "workflows", "wf_*")), key=os.path.getmtime)
    n = 0
    for run in runs:
        jp = os.path.join(run, "journal.jsonl")
        if not os.path.exists(jp) or os.path.getmtime(jp) < cutoff:
            continue
        started, results = {}, {}
        with open(jp, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                if d.get("type") == "started":
                    started[d["agentId"]] = (d.get("label", "?"), d.get("phase", ""))
                elif d.get("type") == "result":
                    results[d["agentId"]] = d.get("result")
        index += ["## workflow run %s" % os.path.basename(run), ""]
        for aid, (label, phase) in started.items():
            status = "done" if aid in results else "running"
            ev, a, b = digest_agent(run, aid, label, status, results.get(aid) if isinstance(results.get(aid), str) else (json.dumps(results.get(aid)) if aid in results else ""))
            index.append("- %s [%s] %s: %d events, %s -> %s" % (label, phase, status, ev, a[11:19], b[11:19]))
            n += 1
        index.append("")
    with open(os.path.join(OUT, "AUTO_INDEX.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(index) + "\n")
    print("digest written for %d agents into %s" % (n, OUT))


if __name__ == "__main__":
    main()
