#!/usr/bin/env python3
# usage: extract_reports.py <journal.jsonl> <out.md> <title>  -> one markdown section per finished agent (full report text)
import json, sys
jp, out, title = sys.argv[1], sys.argv[2], sys.argv[3]
label = {}; res = {}
for l in open(jp):
    try: j = json.loads(l)
    except Exception: continue
    if j.get("type") == "started": label[j["agentId"]] = j.get("label")
    elif j.get("type") == "result":
        r = j.get("result"); res[j["agentId"]] = r if isinstance(r, str) else json.dumps(r, indent=1)
with open(out, "w") as f:
    f.write(f"# {title}\n\nFull final reports of the agents of this wave, copied from the workflow journal (the integrator reads this file).\n")
    for a, r in res.items():
        f.write(f"\n\n## {label.get(a, a)}\n\n{r}\n")
print("wrote", out, "sections:", [label.get(a, a) for a in res])
