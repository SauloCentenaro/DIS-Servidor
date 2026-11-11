#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d-%H%M%S)"
RESULTS="$ROOT/stresser+benchmarker/results"
SESSION="$RESULTS/afk-$STAMP"
LOG="$SESSION/session.log"
STATUS="$SESSION/stages.csv"
mkdir -p "$SESSION"
printf 'stage,start,end,exit_code\n' > "$STATUS"
exec > >(tee -a "$LOG") 2>&1

echo "AFK benchmark session: $STAMP"
echo "Artifacts: $SESSION"

snapshot_report() {
  local label="$1"
  python3 stresser+benchmarker/scripts/benchmark.py report || true
  if [[ -f "$RESULTS/consolidated.csv" ]]; then
    cp "$RESULTS/consolidated.csv" "$SESSION/${label}-consolidated.csv"
  fi
  if [[ -f "$RESULTS/consolidated.json" ]]; then
    cp "$RESULTS/consolidated.json" "$SESSION/${label}-consolidated.json"
  fi
}

run_stage() {
  local label="$1"
  shift
  local started ended code
  started="$(date -Iseconds)"
  echo
  echo "===== START $label at $started ====="
  "$@"
  code=$?
  ended="$(date -Iseconds)"
  printf '%s,%s,%s,%s\n' "$label" "$started" "$ended" "$code" >> "$STATUS"
  echo "===== END $label exit=$code at $ended ====="
  snapshot_report "$label"
  return 0
}

echo "Checking services..."
for url in \
  http://localhost:8080/health \
  http://localhost:8081/health \
  http://localhost:9090/-/healthy \
  http://localhost:3000/api/health; do
  curl --fail --silent --show-error --max-time 15 "$url" > /dev/null || {
    echo "Preflight failed: $url"
    exit 2
  }
done

echo "Checking backend equivalence before load..."
python3 scripts/compare_backends.py \
  --payload stresser+benchmarker/k6/payloads/dis-request.json \
  --output "$SESSION/preflight-parity.json" || exit 2

run_stage unit-tests \
  python3 -m unittest discover -s tests -p 'test_*.py' -v

run_stage smoke \
  python3 stresser+benchmarker/scripts/benchmark.py suite \
    --targets cpp,elixir --experiments smoke --repetitions 1 --order alternate

run_stage baseline-r2 \
  python3 stresser+benchmarker/scripts/benchmark.py suite \
    --targets cpp,elixir --experiments baseline --repetitions 2 --order alternate

run_stage load-1-per-30s-r2 \
  python3 stresser+benchmarker/scripts/benchmark.py suite \
    --targets cpp,elixir --experiments load --rate 1 --duration 5m \
    --repetitions 2 --order alternate --set 'experiment.time_unit="30s"'

run_stage load-1-per-15s-r1 \
  python3 stresser+benchmarker/scripts/benchmark.py suite \
    --targets cpp,elixir --experiments load --rate 1 --duration 5m \
    --repetitions 1 --order alternate --set 'experiment.time_unit="15s"'

snapshot_report final
docker stats --no-stream dis-cpp dis-elixir > "$SESSION/final-docker-stats.txt" 2>&1 || true
docker compose -f compose.dis.yaml ps > "$SESSION/final-compose-ps.txt" 2>&1 || true

echo
echo "AFK session complete."
echo "Log: $LOG"
echo "Stages: $STATUS"
echo "Final report: $SESSION/final-consolidated.csv"
