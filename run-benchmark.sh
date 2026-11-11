#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")"
experiment="${1:-smoke}"
rate="${2:-}"
repetitions="${3:-1}"
set -- python3 stresser+benchmarker/scripts/benchmark.py suite \
  --targets cpp,elixir --experiments "$experiment" --repetitions "$repetitions" --order alternate
if [ -n "$rate" ]; then set -- "$@" --rate "$rate"; fi
exec "$@"
