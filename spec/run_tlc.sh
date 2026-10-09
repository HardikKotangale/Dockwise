#!/usr/bin/env bash
# Translates the PlusCal and runs TLC on every model configuration, saving each
# run's full output to results/<config>.txt. No arguments needed.
#   ./run_tlc.sh            run all
#   ./run_tlc.sh PostureLogic_gaps     run one configuration
# Needs Java 11+. The TLC jar is downloaded once to ~/.cache/tlaplus-tools.
set -uo pipefail
cd "$(dirname "$0")"
JAR="${TLA2TOOLS:-$HOME/.cache/tlaplus-tools/tla2tools.jar}"
if [ ! -f "$JAR" ]; then
  mkdir -p "$(dirname "$JAR")"
  curl -sSL -o "$JAR" https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar
fi
mkdir -p results
STATES="$(mktemp -d)"

# module -> configurations (expected result in the second column)
RUNS=(
  "PostureLogic PostureLogic_nogaps        pass"
  "PostureLogic PostureLogic_gaps          FAIL"
  "PostureLogic PostureLogic_gaps_exit     FAIL"
  "PostureLogic PostureLogic_gaps_fixed    pass"
  "PostureLogic PostureLogic_live_enter    pass"
  "PostureLogic PostureLogic_live_exit     pass"
  "AutoLaunch   AutoLaunch_race               FAIL"
  "AutoLaunch   AutoLaunch_ownership          FAIL"
  "AutoLaunch   AutoLaunch_ownership_partial  FAIL"
  "AutoLaunch   AutoLaunch_fixed              pass"
  "AutoLaunch   AutoLaunch_live_original      FAIL"
  "AutoLaunch   AutoLaunch_live_fixed         pass"
)
for mod in PostureLogic AutoLaunch; do
  [ -f "$mod.tla" ] && java -cp "$JAR" pcal.trans -nocfg "$mod.tla" >/dev/null && rm -f "$mod.old"
done

status=0
for run in "${RUNS[@]}"; do
  read -r mod cfg expect <<<"$run"
  [ -f "$cfg.cfg" ] || continue
  [ $# -gt 0 ] && [ "$1" != "$cfg" ] && continue
  java -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -workers 1 \
       -metadir "$STATES/$cfg" -config "$cfg.cfg" "$mod.tla" > "results/$cfg.txt" 2>&1
  code=$?
  if [ $code -eq 0 ]; then got=pass; else got=FAIL; fi
  mark="ok  "; [ "$got" != "$expect" ] && { mark="WRONG"; status=1; }
  summary=$(grep -m1 -E "^Error: (Invariant|Temporal|Action)|No error has been found" "results/$cfg.txt" | sed 's/^Error: //')
  printf "%-5s %-28s expected %-4s got %-4s  %s\n" "$mark" "$cfg" "$expect" "$got" "$summary"
done
rm -rf "$STATES"
exit $status
