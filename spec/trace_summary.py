#!/usr/bin/env python3
"""Turn a TLC counterexample (results/<config>.txt) into a compact step table.

    python3 trace_summary.py results/AutoLaunch_race.txt

Each row is one TLC step: the action that fired and only the variables it changed.
For AutoLaunch the single PlusCal process picks one of several event branches, so
the branch is named from its position in the translated spec.
"""
import re
import sys
from pathlib import Path

BRANCHES = ["Plug", "Unplug", "PostureChange", "PerformLaunch",
            "UserOpen", "UserHome", "UserClose"]

def branch_names(tla: Path):
    """line number of each `\\/ /\\` branch of World -> its name"""
    names, in_world = {}, False
    n = 0
    for no, line in enumerate(tla.read_text().splitlines(), 1):
        if line.startswith("World =="):
            in_world = True
        elif in_world and line.startswith(("Spec ==", "Next ==")):
            break
        if in_world and re.match(r"\s*(\\/ )?\\/ /\\|^World == \\/ /\\", line):
            if n < len(BRANCHES):
                names[no] = BRANCHES[n]
                n += 1
    return names

def main(path):
    text = Path(path).read_text()
    module = "AutoLaunch" if "AutoLaunch" in text.split("\n", 3)[-1][:400] or "World" in text else "PostureLogic"
    tla = Path(__file__).with_name(module + ".tla")
    names = branch_names(tla) if module == "AutoLaunch" else {}
    head = re.search(r"^Error: (.*)$", text, re.M)
    print(head.group(1) if head else "(no error in this run)")
    parts = re.split(r"\nState (\d+): ", text)
    prev = {}
    for i in range(1, len(parts), 2):
        n, body = parts[i], parts[i + 1]
        first = body.split("\n")[0]
        m = re.match(r"<(\w+) line (\d+)", first)
        if first.startswith("<Initial"):
            action = "(start)"
        elif m:
            action = m.group(1)
            if module == "AutoLaunch" and action == "World":
                # a TLC step names the line where the branch starts
                action = names.get(int(m.group(2)), "World@" + m.group(2))
        else:
            action = first.strip("<> ")[:24]
        kv = dict(re.findall(r"/\\ (\w+) = (\S+)", body))
        kv.pop("pc", None)
        if n == "1":
            show = {k: v for k, v in kv.items() if v not in ("FALSE", "-1", '"none"', "1", "0")}
        else:
            show = {k: v for k, v in kv.items() if prev.get(k) != v}
        prev = kv
        print(f"  {n:>2}  {action:<14} {' '.join(f'{k}={v}' for k, v in show.items())}")

if __name__ == "__main__":
    main(sys.argv[1])
