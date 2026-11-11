#!/usr/bin/env python3
"""Reproduce the frontend request preparation and compare both backends directly."""
from __future__ import annotations

import argparse
import csv
import json
import math
import time
import urllib.error
import urllib.request
from pathlib import Path

EXPECTED_SAMPLES = {1: 50_816, 2: 27_904}
EXPECTED_PIXELS = {1: 3_600, 2: 900}


def parse_vector(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8-sig")
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        raise ValueError(f"arquivo vazio: {path}")

    # The Angular frontend expects one value per line. Accepting ; or , tables here
    # is intentionally more permissive, but values are only flattened, never padded.
    delimiter = ";" if any(";" in line for line in lines) else "," if any("," in line for line in lines) else None
    values = []
    if delimiter:
        for row in csv.reader(lines, delimiter=delimiter):
            values.extend(cell.strip() for cell in row if cell.strip())
    else:
        values = lines

    for index, value in enumerate(values, 1):
        try:
            number = float(value)
        except ValueError as exc:
            raise ValueError(f"valor inválido na posição {index}: {value!r}") from exc
        if not math.isfinite(number):
            raise ValueError(f"valor não finito na posição {index}: {value!r}")
    return values


def build_payload(vector_path: Path, model: int, gain: bool, user: int) -> dict:
    values = parse_vector(vector_path)
    expected = EXPECTED_SAMPLES[model]
    if len(values) != expected:
        raise ValueError(
            f"modelo {model} exige {expected} amostras, mas {vector_path} contém {len(values)}; "
            "o frontend original não fazia expansão ou interpolação"
        )
    return {"model": model == 1, "ganho": gain, "user": user, "vector": values}


def load_payload(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    required = {"model", "ganho", "user", "vector"}
    if not isinstance(payload, dict) or not required.issubset(payload):
        raise ValueError(f"payload deve conter {sorted(required)}")
    model = 1 if payload["model"] is True else 2 if payload["model"] is False else None
    if model is None:
        raise ValueError("payload.model deve ser booleano")
    expected = EXPECTED_SAMPLES[model]
    if not isinstance(payload["vector"], list) or len(payload["vector"]) != expected:
        raise ValueError(f"modelo {model} exige vetor com {expected} amostras")
    return payload


def request_json(url: str, payload: dict, timeout: float) -> tuple[dict, float]:
    body = json.dumps(payload, separators=(",", ":")).encode()
    request = urllib.request.Request(url, data=body, method="POST", headers={"Content-Type": "application/json"})
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
            if response.status != 200:
                raise RuntimeError(f"{url}: HTTP {response.status}: {raw[:500]!r}")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise RuntimeError(f"{url}: HTTP {exc.code}: {detail}") from exc
    elapsed = time.perf_counter() - start
    return json.loads(raw), elapsed


def compare(cpp: dict, elixir: dict, model: int) -> dict:
    mismatches = []
    for field in ("user", "iteracoes"):
        if cpp.get(field) != elixir.get(field):
            mismatches.append(f"{field}: C++={cpp.get(field)!r}, Elixir={elixir.get(field)!r}")
    cpp_pixels, elixir_pixels = cpp.get("imageVector"), elixir.get("imageVector")
    if not isinstance(cpp_pixels, list) or not isinstance(elixir_pixels, list):
        mismatches.append("imageVector ausente ou inválido")
    elif cpp_pixels != elixir_pixels:
        first = next((index for index, pair in enumerate(zip(cpp_pixels, elixir_pixels)) if pair[0] != pair[1]), None)
        mismatches.append(
            f"imageVector diverge; tamanhos C++={len(cpp_pixels)}, Elixir={len(elixir_pixels)}, primeira diferença={first}"
        )
    elif len(cpp_pixels) != EXPECTED_PIXELS[model]:
        mismatches.append(f"imagem possui {len(cpp_pixels)} pixels; esperado={EXPECTED_PIXELS[model]}")
    return {"equivalent": not mismatches, "mismatches": mismatches}


def main() -> int:
    parser = argparse.ArgumentParser(description="Send the same reconstruction to C++ and Elixir and compare outputs")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--vector", type=Path, help="measurement CSV (one value per line; ;/, tables are flattened)")
    source.add_argument("--payload", type=Path, help="existing JSON request")
    parser.add_argument("--model", type=int, choices=(1, 2), help="required with --vector")
    parser.add_argument("--gain", action="store_true")
    parser.add_argument("--user", type=int, default=990001)
    parser.add_argument("--cpp-url", default="http://localhost:8080/reconstruct")
    parser.add_argument("--elixir-url", default="http://localhost:8081/reconstruct")
    parser.add_argument("--timeout", type=float, default=900)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    try:
        if args.vector:
            if args.model is None:
                parser.error("--model is required with --vector")
            payload = build_payload(args.vector, args.model, args.gain, args.user)
            model = args.model
        else:
            payload = load_payload(args.payload)
            model = 1 if payload["model"] else 2

        cpp, cpp_seconds = request_json(args.cpp_url, payload, args.timeout)
        elixir, elixir_seconds = request_json(args.elixir_url, payload, args.timeout)
        result = {
            "equivalence": compare(cpp, elixir, model),
            "model": model,
            "samples": len(payload["vector"]),
            "cpp_client_seconds": cpp_seconds,
            "elixir_client_seconds": elixir_seconds,
            "cpp_server_seconds": cpp.get("durationSeconds"),
            "elixir_server_seconds": elixir.get("durationSeconds"),
            "iterations": {"cpp": cpp.get("iteracoes"), "elixir": elixir.get("iteracoes")},
        }
        rendered = json.dumps(result, indent=2, ensure_ascii=False)
        print(rendered)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(rendered + "\n", encoding="utf-8")
        return 0 if result["equivalence"]["equivalent"] else 1
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
