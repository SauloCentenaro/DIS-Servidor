#!/usr/bin/env python3
"""Generate the identical k6 request body used against C++ and Elixir."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--vector", required=True, help="CSV with one numeric sample per row")
parser.add_argument("--model", choices=("1", "2"), required=True)
parser.add_argument("--gain", action="store_true")
parser.add_argument("--user", type=int, default=900001)
default_output = Path(__file__).resolve().parents[1] / "k6/payloads/dis-request.json"
parser.add_argument("--output", default=str(default_output))
args = parser.parse_args()

source = Path(args.vector)
values = [line.strip() for line in source.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
if not values:
    raise SystemExit("vector CSV is empty")
for index, value in enumerate(values, 1):
    try: float(value)
    except ValueError as exc: raise SystemExit(f"invalid number at line {index}: {value}") from exc

output = Path(args.output)
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps({"model": args.model == "1", "ganho": args.gain, "user": args.user, "vector": values}, separators=(",", ":")), encoding="utf-8")
print(f"wrote {output} with {len(values)} samples")
