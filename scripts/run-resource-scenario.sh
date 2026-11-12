#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Uso: bash ./scripts/run-resource-scenario.sh ID CPUS MEMORIA WORKERS [REPETICOES] [DURACAO]

Exemplo:
  bash ./scripts/run-resource-scenario.sh S01 0.5 800m 1 2 2m

Os mesmos limites sao aplicados aos backends C++ e Elixir. A stack de
monitoramento sobe automaticamente e a carga so comeca depois do preflight.
EOF
}

if [[ $# -lt 4 || $# -gt 6 ]]; then
  usage
  exit 64
fi

SCENARIO_ID="$1"
BACKEND_CPUS="$2"
BACKEND_MEMORY="$3"
BACKEND_WORKERS="$4"
REPETITIONS="${5:-2}"
DURATION="${6:-2m}"

if [[ ! "$SCENARIO_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ID invalido: use apenas letras, numeros, ponto, hifen ou sublinhado."
  exit 64
fi
if [[ ! "$BACKEND_CPUS" =~ ^[0-9]+([.][0-9]+)?$ ]] || [[ "$BACKEND_CPUS" == "0" ]]; then
  echo "CPUS invalido: use um numero positivo, por exemplo 0.5 ou 2."
  exit 64
fi
if [[ ! "$BACKEND_MEMORY" =~ ^[0-9]+([.][0-9]+)?[kKmMgG]$ ]]; then
  echo "MEMORIA invalida: use, por exemplo, 800m, 2g ou 12g."
  exit 64
fi
if [[ ! "$BACKEND_WORKERS" =~ ^[1-9][0-9]*$ ]] || (( BACKEND_WORKERS > 256 )); then
  echo "WORKERS invalido: use um inteiro entre 1 e 256."
  exit 64
fi
if [[ ! "$REPETITIONS" =~ ^[1-9][0-9]*$ ]]; then
  echo "REPETICOES invalida: use um inteiro positivo."
  exit 64
fi
if [[ ! "$DURATION" =~ ^[0-9]+([.][0-9]+)?(ms|s|m|h)$ ]]; then
  echo "DURACAO invalida: use, por exemplo, 90s, 2m ou 1h."
  exit 64
fi

export BACKEND_CPUS BACKEND_MEMORY BACKEND_WORKERS
export BACKEND_MEMORY_RESERVATION="${BACKEND_MEMORY_RESERVATION:-512m}"
export BACKEND_PIDS_LIMIT="${BACKEND_PIDS_LIMIT:-512}"

STAMP="$(date +%Y%m%d-%H%M%S)"
RESULTS="$ROOT/stresser+benchmarker/results"
SESSION="$RESULTS/resource-scenarios/${SCENARIO_ID}-${STAMP}"
LOG="$SESSION/session.log"
STATUS="$SESSION/status.env"
mkdir -p "$SESSION"
exec > >(tee -a "$LOG") 2>&1

write_status() {
  local state="$1"
  cat > "$STATUS" <<EOF
SCENARIO_ID=$SCENARIO_ID
STATE=$state
BACKEND_CPUS=$BACKEND_CPUS
BACKEND_MEMORY=$BACKEND_MEMORY
BACKEND_WORKERS=$BACKEND_WORKERS
REPETITIONS=$REPETITIONS
DURATION=$DURATION
UPDATED_AT=$(date -Iseconds)
EOF
}

capture_diagnostics() {
  docker compose -f compose.dis.yaml ps > "$SESSION/compose-ps.txt" 2>&1 || true
  docker inspect dis-cpp dis-elixir > "$SESSION/container-inspect.json" 2>&1 || true
  docker stats --no-stream dis-cpp dis-elixir > "$SESSION/docker-stats.txt" 2>&1 || true
  docker logs dis-cpp > "$SESSION/dis-cpp.log" 2>&1 || true
  docker logs dis-elixir > "$SESSION/dis-elixir.log" 2>&1 || true
}

wait_healthy() {
  local name="$1"
  local deadline=$((SECONDS + 300))
  local health restarts last_state="" stable_since=0
  while (( SECONDS < deadline )); do
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || true)"
    restarts="$(docker inspect --format '{{.RestartCount}}' "$name" 2>/dev/null || echo '?')"
    if [[ "$health/$restarts" != "$last_state" ]]; then
      echo "$name: estado=$health reinicios=$restarts"
      last_state="$health/$restarts"
    fi
    if [[ "$health" == "healthy" ]]; then
      if (( stable_since == 0 )); then
        stable_since=$SECONDS
      elif (( SECONDS - stable_since >= 15 )); then
        echo "$name permaneceu healthy por 15 segundos."
        return 0
      fi
    else
      stable_since=0
    fi
    sleep 3
  done
  echo "$name nao permaneceu healthy por 15 segundos dentro de 300 segundos."
  return 1
}

write_status STARTING
echo "Cenario $SCENARIO_ID: cpu=$BACKEND_CPUS memoria=$BACKEND_MEMORY workers=$BACKEND_WORKERS"
echo "Artefatos: $SESSION"

echo "Subindo observabilidade e recriando os dois backends com limites iguais..."
if ! docker compose -f compose.dis.yaml up -d prometheus grafana cadvisor; then
  write_status INFRA_FAILURE
  capture_diagnostics
  exit 2
fi
if ! docker compose -f compose.dis.yaml up -d --force-recreate servidor elixir; then
  write_status START_FAILURE
  capture_diagnostics
  exit 3
fi

if ! wait_healthy dis-cpp || ! wait_healthy dis-elixir; then
  echo "O limite deste cenario nao sustentou os dois backends; diagnosticos foram preservados."
  write_status HEALTH_FAILURE
  capture_diagnostics
  exit 4
fi

docker compose -f compose.dis.yaml up -d cliente || true
docker compose -f compose.dis.yaml config > "$SESSION/effective-compose.yaml"
capture_diagnostics

echo "Validando equivalencia logica antes da carga..."
if ! python3 scripts/compare_backends.py \
  --payload stresser+benchmarker/k6/payloads/dis-request.json \
  --output "$SESSION/backend-parity.json"; then
  write_status PARITY_FAILURE
  capture_diagnostics
  exit 5
fi

echo "Executando baseline exploratoria nos dois backends..."
set +e
python3 stresser+benchmarker/scripts/benchmark.py suite \
  --targets cpp,elixir \
  --experiments baseline \
  --repetitions "$REPETITIONS" \
  --duration "$DURATION" \
  --warmup 30s \
  --cooldown 30s \
  --order alternate \
  --thresholds-file stresser+benchmarker/configs/thresholds.exploratory.yaml \
  --set "experiment.vus=$BACKEND_WORKERS" \
  --set 'target.timeout="120s"' \
  --restart-target \
  --stabilization-seconds 5 \
  --parameter "resource_scenario=$SCENARIO_ID" \
  --parameter "backend_cpus=$BACKEND_CPUS" \
  --parameter "backend_memory=$BACKEND_MEMORY" \
  --parameter "backend_workers=$BACKEND_WORKERS"
BENCHMARK_EXIT=$?
set -e

python3 stresser+benchmarker/scripts/benchmark.py report || true
[[ -f "$RESULTS/consolidated.csv" ]] && cp "$RESULTS/consolidated.csv" "$SESSION/consolidated.csv"
[[ -f "$RESULTS/consolidated.json" ]] && cp "$RESULTS/consolidated.json" "$SESSION/consolidated.json"
capture_diagnostics

if (( BENCHMARK_EXIT == 0 )); then
  write_status COMPLETE
else
  echo "Benchmark terminou com codigo $BENCHMARK_EXIT; resultados e diagnosticos foram mantidos."
  write_status BENCHMARK_FAILURE
fi

echo "Cenario encerrado. Veja: $SESSION"
exit "$BENCHMARK_EXIT"
