#!/usr/bin/env python3
# usage: append_reports.py <journal.jsonl> <reports.md> <label> [<label> ...]
# Appends one '## <label>' section (the agent's full final report from the workflow journal) to an EXISTING reports file
# (extract_reports.py overwrites; this one does not), skips labels that are already in the file, and prints the line
# range of every '## ' section so they can be passed as pointers in the 'reports' argument of the sprint script.
import json, sys
jp, out = sys.argv[1], sys.argv[2]
want = sys.argv[3:]
label = {}; res = {}
for l in open(jp):
    try: j = json.loads(l)
    except Exception: continue
    if j.get("type") == "started": label[j["agentId"]] = j.get("label")
    elif j.get("type") == "result":
        r = j.get("result"); res[j["agentId"]] = r if isinstance(r, str) else json.dumps(r, indent=1)
text = open(out).read()
have = {ln[3:].strip() for ln in text.splitlines() if ln.startswith("## ")}
added = []
with open(out, "a") as f:
    for a, r in res.items():
        lab = label.get(a, a)
        if lab in want and lab not in have:
            f.write(f"\n\n## {lab}\n\n{r}\n")
            added.append(lab)
lines = open(out).read().splitlines()
heads = [(i + 1, ln[3:].strip()) for i, ln in enumerate(lines) if ln.startswith("## ")]
print("added:", added)
for k, (n, lab) in enumerate(heads):
    end = heads[k + 1][0] - 1 if k + 1 < len(heads) else len(lines)
    print(f"{lab}: lines {n}-{end}")
