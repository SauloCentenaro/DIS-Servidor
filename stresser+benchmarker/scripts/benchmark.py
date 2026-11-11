#!/usr/bin/env python3
"""Dependency-free orchestration for the HTTP benchmark laboratory."""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import gzip
import hashlib
import json
import os
import platform
import random
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "results"
SENSITIVE = re.compile(r"authorization|auth|token|secret|password|passwd|api[-_]?key|cookie", re.I)
DEFAULT_COMPOSE = ROOT.parent / "compose.dis.yaml" if (ROOT.parent / "compose.dis.yaml").is_file() else ROOT / "compose.yaml"


def run(command, *, check=True, capture=True, timeout=None):
    result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8", errors="replace",
                            capture_output=capture, timeout=timeout)
    if check and result.returncode:
        detail = (result.stderr or result.stdout or "command failed").strip()
        raise RuntimeError(f"{' '.join(command)}: {detail}")
    return result


def docker_compose(*args, **kwargs):
    compose_file = Path(os.getenv("BENCH_COMPOSE_FILE", DEFAULT_COMPOSE)).resolve()
    return run(["docker", "compose", "-f", str(compose_file), *args], **kwargs)


def read_yaml_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"{path} must use JSON-compatible YAML: {exc}") from exc


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def redact(value):
    if isinstance(value, dict):
        return {key: ("<redacted>" if SENSITIVE.search(str(key)) else redact(item)) for key, item in value.items()}
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, str) and "=" in value and SENSITIVE.search(value.split("=", 1)[0]):
        return value.split("=", 1)[0] + "=<redacted>"
    return value


def redact_text(value):
    value = re.sub(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+", r"\1<redacted>", value)
    return re.sub(r"(?im)^([^\r\n=:]*(?:auth|token|secret|password|passwd|api[-_]?key|cookie)[^\r\n=:]*[=:])[^\r\n]*", r"\1<redacted>", value)


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git_commit():
    result = run(["git", "rev-parse", "HEAD"], check=False)
    return result.stdout.strip() if result.returncode == 0 else None


def command_version(command):
    result = run(command, check=False)
    return (result.stdout or result.stderr).strip().splitlines()[0] if result.returncode == 0 else None


def duration_seconds(value):
    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*(ms|s|m|h)\s*", str(value))
    if not match:
        raise ValueError(f"invalid duration: {value}")
    number, unit = float(match.group(1)), match.group(2)
    return number * {"ms": .001, "s": 1, "m": 60, "h": 3600}[unit]


def config_paths(args):
    return (
        Path(args.targets_file or os.getenv("BENCH_TARGETS_FILE", ROOT / "configs/targets.example.yaml")),
        Path(args.experiments_file or os.getenv("BENCH_EXPERIMENTS_FILE", ROOT / "configs/experiments.example.yaml")),
        Path(args.thresholds_file or os.getenv("BENCH_THRESHOLDS_FILE", ROOT / "configs/thresholds.example.yaml")),
    )


def deep_merge(base, updates):
    for key, value in updates.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict): deep_merge(base[key], value)
        else: base[key] = value


def apply_override(config, expression):
    if "=" not in expression: raise ValueError(f"override must be path=value: {expression}")
    path, raw = expression.split("=", 1)
    try: value = json.loads(raw)
    except json.JSONDecodeError: value = raw
    current = config
    parts = path.split(".")
    if not parts or parts[0] not in ("target", "experiment", "thresholds"):
        raise ValueError("override path must start with target, experiment, or thresholds")
    for key in parts[:-1]: current = current.setdefault(key, {})
    current[parts[-1]] = value


def load_effective(args):
    targets_path, experiments_path, thresholds_path = config_paths(args)
    targets = read_yaml_json(targets_path).get("targets", {})
    experiments = read_yaml_json(experiments_path).get("experiments", {})
    thresholds = read_yaml_json(thresholds_path).get("thresholds", {})
    if args.target not in targets:
        raise ValueError(f"unknown target '{args.target}'; choices: {', '.join(targets)}")
    if args.experiment not in experiments:
        raise ValueError(f"unknown experiment '{args.experiment}'; choices: {', '.join(experiments)}")
    target = dict(targets[args.target])
    experiment = dict(experiments[args.experiment])
    combined = {"target": target, "experiment": experiment, "thresholds": thresholds}
    if os.getenv("BENCH_OVERRIDES"):
        overrides = json.loads(os.environ["BENCH_OVERRIDES"])
        deep_merge(combined, overrides)
    for expression in getattr(args, "overrides", None) or []: apply_override(combined, expression)
    target, experiment, thresholds = combined["target"], combined["experiment"], combined["thresholds"]
    if args.rate is not None: experiment["rate"] = args.rate
    if args.duration: experiment["duration"] = args.duration
    if args.warmup: experiment["warmup"] = args.warmup
    if args.cooldown: experiment["cooldown"] = args.cooldown
    if args.payload: target["payload"] = args.payload.replace("\\", "/")
    if args.base_url: target["base_url"] = args.base_url
    if args.insecure_tls: target["insecure_tls"] = True
    payload = ROOT / target["payload"]
    if not payload.is_file():
        raise ValueError(f"payload does not exist: {payload}")
    return target, experiment, thresholds, (targets_path, experiments_path, thresholds_path)


def validate_config_data(targets, experiments, thresholds):
    errors = []
    for name, target in targets.items():
        for field in ("base_url", "endpoint", "method", "expected_status"):
            if field not in target: errors.append(f"target {name}: missing {field}")
        if not str(target.get("base_url", "")).startswith(("http://", "https://")):
            errors.append(f"target {name}: base_url must be an HTTP(S) URL")
    supported = {"shared-iterations", "constant-vus", "constant-arrival-rate", "ramping-arrival-rate"}
    for name, exp in experiments.items():
        if exp.get("executor") not in supported: errors.append(f"experiment {name}: unsupported executor")
        for key in ("duration", "warmup", "cooldown"):
            if key in exp:
                try: duration_seconds(exp[key])
                except ValueError as exc: errors.append(f"experiment {name}: {exc}")
    if not isinstance(thresholds, dict): errors.append("thresholds must be an object")
    if errors: raise ValueError("configuration errors:\n- " + "\n- ".join(errors))


def validate_environment(args):
    targets_path, experiments_path, thresholds_path = config_paths(args)
    targets = read_yaml_json(targets_path).get("targets", {})
    experiments = read_yaml_json(experiments_path).get("experiments", {})
    thresholds = read_yaml_json(thresholds_path).get("thresholds", {})
    validate_config_data(targets, experiments, thresholds)
    checks = {"python": sys.version.split()[0], "platform": platform.platform()}
    checks["docker"] = command_version(["docker", "--version"])
    checks["compose"] = command_version(["docker", "compose", "version"])
    if not checks["docker"] or not checks["compose"]:
        raise RuntimeError("Docker Engine and Docker Compose v2 are required")
    docker_compose("config", "--quiet")
    info = run(["docker", "info", "--format", "{{json .}}"], check=False)
    if info.returncode: raise RuntimeError("Docker daemon is not available")
    checks["compose_config"] = "valid"
    for service, url in (("prometheus", prometheus_url(args) + "/-/healthy"),
                         ("grafana", f"http://localhost:{os.getenv('GRAFANA_PORT', '3000')}/api/health"),
                         ("cadvisor", f"http://localhost:{os.getenv('CADVISOR_PORT', '8082')}/healthz")):
        try:
            with urllib.request.urlopen(url, timeout=3) as response:
                checks[service] = f"healthy ({response.status})"
        except Exception as exc:
            checks[service] = f"unreachable: {exc}"
    print(json.dumps(checks, indent=2, ensure_ascii=False))
    return checks


def prometheus_url(args=None):
    return getattr(args, "prometheus_url", None) or os.getenv("PROMETHEUS_URL", f"http://localhost:{os.getenv('PROMETHEUS_PORT', '9090')}")


def target_health(target):
    health = target.get("health_endpoint")
    url = target["base_url"].rstrip("/") + (health or target["endpoint"])
    method = "GET" if health else target.get("method", "GET")
    body = "" if health or method.upper() in ("GET", "HEAD") else (ROOT / target["payload"]).read_text(encoding="utf-8")
    envs = {
        "HEALTH_URL": url, "HEALTH_METHOD": method, "HEALTH_BODY": body,
        "HEALTH_HEADERS": json.dumps(target.get("headers", {})), "HEALTH_TIMEOUT": target.get("timeout", "10s"),
        "EXPECTED_STATUS": str(target.get("expected_status", 200)), "INSECURE_TLS": str(bool(target.get("insecure_tls"))).lower(),
    }
    command = ["--profile", "tools", "run", "--rm"]
    for key, value in envs.items(): command += ["-e", f"{key}={value}"]
    command += ["k6", "run", "/workspace/k6/health.js"]
    docker_compose(*command, capture=False)


def inspect_container(name):
    if not name: return {}
    result = run(["docker", "inspect", name], check=False)
    if result.returncode: return {"error": result.stderr.strip(), "requested_name": name}
    return json.loads(result.stdout)[0]


def host_environment():
    docker_info = run(["docker", "info", "--format", "{{json .}}"], check=False)
    try: info = json.loads(docker_info.stdout) if docker_info.returncode == 0 else {}
    except json.JSONDecodeError: info = {}
    return {
        "captured_at": dt.datetime.now(dt.timezone.utc).isoformat(), "platform": platform.platform(),
        "python": sys.version, "cpu_count": os.cpu_count(),
        "docker_version": command_version(["docker", "--version"]),
        "compose_version": command_version(["docker", "compose", "version"]),
        "docker_info": {key: info.get(key) for key in ("OperatingSystem", "OSType", "Architecture", "NCPU", "MemTotal", "DockerRootDir")},
        "component_images": {"k6": "grafana/k6:0.57.0", "prometheus": "prom/prometheus:v3.2.1", "grafana": "grafana/grafana:11.6.0", "cadvisor": "gcr.io/cadvisor/cadvisor:v0.49.2"},
    }


def k6_run(runtime_config, result_name, scenario, *, warmup=False):
    container_config = f"/results/{runtime_config.name}"
    result_dir = f"/results/{result_name}"
    output = f"/results/{result_name}/k6-metrics.json"
    command = ["--profile", "tools", "run", "--rm", "-e", f"CONFIG_PATH={container_config}",
               "-e", f"RESULT_DIR={result_dir}", "-e", f"PAYLOAD_PATH={runtime_config_payload(runtime_config)}", "k6", "run"]
    if not warmup:
        command += ["--out", f"json={output}", "--out", "experimental-prometheus-rw"]
    command += [f"/workspace/k6/scenarios/{scenario}.js"]
    return docker_compose(*command, check=False, capture=False).returncode


def runtime_config_payload(path):
    return json.loads(path.read_text(encoding="utf-8"))["target"]["payload"]


PROM_QUERIES = {
    "cpu_total_cores": 'rate(container_cpu_usage_seconds_total{name=~".*{container}.*"}[10s])',
    "cpu_user_cores": 'rate(container_cpu_user_seconds_total{name=~".*{container}.*"}[10s])',
    "cpu_system_cores": 'rate(container_cpu_system_seconds_total{name=~".*{container}.*"}[10s])',
    "cpu_throttled_seconds": 'rate(container_cpu_cfs_throttled_seconds_total{name=~".*{container}.*"}[10s])',
    "memory_usage_bytes": 'container_memory_usage_bytes{name=~".*{container}.*"}',
    "memory_working_set_bytes": 'container_memory_working_set_bytes{name=~".*{container}.*"}',
    "memory_cache_bytes": 'container_memory_cache{name=~".*{container}.*"}',
    "memory_max_usage_bytes": 'container_memory_max_usage_bytes{name=~".*{container}.*"}',
    "memory_limit_bytes": 'container_spec_memory_limit_bytes{name=~".*{container}.*"}',
    "memory_failures": 'rate(container_memory_failcnt{name=~".*{container}.*"}[10s])',
    "oom_events": 'increase(container_oom_events_total{name=~".*{container}.*"}[10s])',
    "network_receive_bytes_per_second": 'rate(container_network_receive_bytes_total{name=~".*{container}.*"}[10s])',
    "network_transmit_bytes_per_second": 'rate(container_network_transmit_bytes_total{name=~".*{container}.*"}[10s])',
    "block_read_bytes_per_second": 'sum by (name) (rate(container_fs_reads_bytes_total{name=~".*{container}.*"}[10s]))',
    "block_write_bytes_per_second": 'sum by (name) (rate(container_fs_writes_bytes_total{name=~".*{container}.*"}[10s]))',
    "processes": 'container_processes{name=~".*{container}.*"}',
    "threads": 'container_threads{name=~".*{container}.*"}',
    "uptime_seconds": 'time() - container_start_time_seconds{name=~".*{container}.*"}',
}


def prometheus_query_range(base_url, query, start, end, step=1):
    params = urllib.parse.urlencode({"query": query, "start": start, "end": end, "step": step})
    with urllib.request.urlopen(f"{base_url}/api/v1/query_range?{params}", timeout=30) as response:
        payload = json.load(response)
    if payload.get("status") != "success": raise RuntimeError(payload.get("error", "Prometheus query failed"))
    return payload["data"]["result"]


def collect_metrics(result_dir, container, start, end, prom_url):
    query_record, series, rows = {}, {}, []
    for name, template in PROM_QUERIES.items():
        query = template.format(container=re.escape(container))
        query_record[name] = query
        try: values = prometheus_query_range(prom_url, query, start, end)
        except Exception as exc: values = {"error": str(exc)}
        series[name] = values
        if isinstance(values, list):
            for item in values:
                labels = json.dumps(item.get("metric", {}), sort_keys=True)
                for timestamp, value in item.get("values", []):
                    rows.append({"timestamp": timestamp, "metric": name, "value": value, "labels": labels})
    write_json(result_dir / "prometheus-queries.json", query_record)
    write_json(result_dir / "container-metrics.json", series)
    with open(result_dir / "container-metrics.csv", "w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=["timestamp", "metric", "value", "labels"])
        writer.writeheader(); writer.writerows(rows)
    return series


def metric_values(series, name):
    result = []
    values = series.get(name, [])
    if not isinstance(values, list): return result
    for item in values:
        for _, value in item.get("values", []):
            try:
                number = float(value)
                if number == number and abs(number) != float("inf"): result.append(number)
            except (TypeError, ValueError): pass
    return result


def summary_metric(summary, name, field, default=0):
    return summary.get("metrics", {}).get(name, {}).get("values", {}).get(field, default)


def derived_summary(result_dir, series, elapsed):
    try: k6 = read_yaml_json(result_dir / "k6-summary.json")
    except Exception: k6 = {}
    cpu = metric_values(series, "cpu_total_cores")
    memory = metric_values(series, "memory_working_set_bytes") or metric_values(series, "memory_usage_bytes")
    rx = metric_values(series, "network_receive_bytes_per_second")
    tx = metric_values(series, "network_transmit_bytes_per_second")
    reads = metric_values(series, "block_read_bytes_per_second")
    writes = metric_values(series, "block_write_bytes_per_second")
    reqs = summary_metric(k6, "http_reqs", "count")
    rps = summary_metric(k6, "http_reqs", "rate")
    successes = summary_metric(k6, "successful_requests", "count")
    cpu_seconds = (sum(cpu) / len(cpu) * elapsed) if cpu else None
    first_last = (memory[-1] - memory[0]) if len(memory) > 1 else None
    result = {
        "latency_ms": {key: summary_metric(k6, "http_req_duration", field, None) for key, field in
                       (("mean", "avg"), ("p50", "med"), ("p90", "p(90)"), ("p95", "p(95)"), ("p99", "p(99)"), ("max", "max"))},
        "throughput_rps": rps, "requests_completed": reqs, "requests_successful": successes,
        "error_rate": summary_metric(k6, "http_req_failed", "rate", None),
        "dropped_iterations": summary_metric(k6, "dropped_iterations", "count", 0),
        "cpu_mean_cores": sum(cpu) / len(cpu) if cpu else None, "cpu_max_cores": max(cpu) if cpu else None,
        "cpu_total_seconds": cpu_seconds, "memory_mean_bytes": sum(memory) / len(memory) if memory else None,
        "memory_peak_bytes": max(memory) if memory else None, "memory_first_to_last_delta_bytes": first_last,
        "network_received_bytes_estimate": (sum(rx) / len(rx) * elapsed) if rx else None,
        "network_transmitted_bytes_estimate": (sum(tx) / len(tx) * elapsed) if tx else None,
        "block_read_bytes_estimate": (sum(reads) / len(reads) * elapsed) if reads else None,
        "block_write_bytes_estimate": (sum(writes) / len(writes) * elapsed) if writes else None,
        "successful_requests_per_cpu_second": successes / cpu_seconds if successes and cpu_seconds else None,
    }
    write_json(result_dir / "derived-summary.json", result)
    return result


def run_experiment(args):
    target, experiment, thresholds, source_paths = load_effective(args)
    validate_config_data({args.target: target}, {args.experiment: experiment}, thresholds)
    run_id = args.run_id or uuid.uuid4().hex[:12]
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    result_name = f"{stamp}-{run_id}-{args.target}-{args.experiment}"
    result_dir = RESULTS / result_name
    result_dir.mkdir(parents=True, exist_ok=False)
    tags = {"target": args.target, "implementation": target.get("implementation", args.target),
            "experiment": args.experiment, "scenario": args.experiment, "run_id": run_id,
            "payload": Path(target["payload"]).stem, "rate": str(experiment.get("rate", "n/a")),
            "repetition": str(args.repetition), **target.get("tags", {})}
    effective = {"schema_version": 1, "run_id": run_id, "target_name": args.target,
                 "experiment_name": args.experiment, "repetition": args.repetition, "target": target,
                 "experiment": experiment, "thresholds": thresholds, "tags": tags,
                 "source_files": [str(path) for path in source_paths]}
    write_json(result_dir / "effective-config.yaml", redact(effective))
    runtime_path = RESULTS / f".runtime-{run_id}.json"
    write_json(runtime_path, effective)
    environment = host_environment(); write_json(result_dir / "environment.json", environment)
    inspect = inspect_container(target.get("container_name")); write_json(result_dir / "target-inspect.json", redact(inspect))
    payload_path = ROOT / target["payload"]
    metadata = {
        "schema_version": 1, "status": "started", "run_id": run_id, "target": args.target,
        "implementation": target.get("implementation", args.target), "experiment": args.experiment,
        "repetition": args.repetition, "endpoint": target["base_url"].rstrip("/") + target["endpoint"],
        "requested_rate": experiment.get("rate"), "warmup": experiment.get("warmup", "0s"),
        "cooldown": experiment.get("cooldown", "0s"), "platform_commit": git_commit(),
        "application_commit": args.application_commit, "payload_file": target["payload"],
        "payload_sha256": sha256(payload_path), "dataset_file": args.dataset,
        "dataset_sha256": sha256(args.dataset) if args.dataset and Path(args.dataset).is_file() else None,
        "container_name": target.get("container_name"), "container_id": inspect.get("Id"),
        "container_image": inspect.get("Config", {}).get("Image"), "image_digest": inspect.get("Image"),
        "cpu_limit": inspect.get("HostConfig", {}).get("NanoCpus") or inspect.get("HostConfig", {}).get("CpuQuota"),
        "memory_limit_bytes": inspect.get("HostConfig", {}).get("Memory"), "custom_parameters": redact(args.parameter or []),
        "host_cpu_count": environment.get("docker_info", {}).get("NCPU") or environment.get("cpu_count"),
        "host_memory_bytes": environment.get("docker_info", {}).get("MemTotal"),
        "host_operating_system": environment.get("docker_info", {}).get("OperatingSystem") or environment.get("platform"),
        "docker_version": environment.get("docker_version"), "compose_version": environment.get("compose_version"),
        "component_versions": environment.get("component_images"),
    }
    write_json(result_dir / "metadata.json", metadata)
    exit_code = 1; measured_start = measured_end = None; failure = None
    try:
        target_health(target)
        if args.restart_target:
            if not target.get("container_name"): raise RuntimeError("restart requested but container_name is not configured")
            run(["docker", "restart", target["container_name"]], capture=False)
            time.sleep(args.stabilization_seconds)
            target_health(target)
        elif args.stabilization_seconds: time.sleep(args.stabilization_seconds)
        warmup = experiment.get("warmup", "0s")
        if duration_seconds(warmup) > 0:
            warm_config = json.loads(json.dumps(effective))
            warm_config["thresholds"] = {}
            warm_config["experiment"] = {"executor": "constant-vus", "vus": max(1, int(experiment.get("vus", 1))), "duration": warmup}
            write_json(runtime_path, warm_config)
            warm_code = k6_run(runtime_path, result_name, args.experiment, warmup=True)
            if warm_code: raise RuntimeError(f"warmup failed with exit code {warm_code}")
            time.sleep(args.pre_measurement_seconds)
            write_json(runtime_path, effective)
        measured_start = time.time()
        metadata["start_time_utc"] = dt.datetime.fromtimestamp(measured_start, dt.timezone.utc).isoformat()
        write_json(result_dir / "metadata.json", metadata)
        exit_code = k6_run(runtime_path, result_name, args.experiment)
        measured_end = time.time()
        if duration_seconds(experiment.get("cooldown", "0s")) > 0: time.sleep(duration_seconds(experiment["cooldown"]))
    except Exception as exc:
        failure = str(exc)
        measured_end = measured_end or time.time()
    finally:
        runtime_path.unlink(missing_ok=True)
        if (result_dir / "k6-metrics.json").exists():
            with open(result_dir / "k6-metrics.json", "rb") as source, gzip.open(result_dir / "k6-metrics.json.gz", "wb", compresslevel=6) as dest:
                shutil.copyfileobj(source, dest)
            (result_dir / "k6-metrics.json").unlink()
        elif not (result_dir / "k6-metrics.json.gz").exists():
            with gzip.open(result_dir / "k6-metrics.json.gz", "wt", encoding="utf-8") as stream:
                stream.write("")
        if not (result_dir / "k6-summary.json").exists(): write_json(result_dir / "k6-summary.json", {"run_id": run_id, "metrics": {}, "incomplete": True})
        if not (result_dir / "checks.json").exists(): write_json(result_dir / "checks.json", {"run_id": run_id, "incomplete": True})
        if target.get("container_name"):
            logs = run(["docker", "logs", "--timestamps", target["container_name"]], check=False)
            (result_dir / "target-logs.txt").write_text(redact_text((logs.stdout or "") + (logs.stderr or "")), encoding="utf-8")
        else: (result_dir / "target-logs.txt").write_text("container_name not configured\n", encoding="utf-8")
        start = measured_start or time.time(); end = measured_end or time.time()
        try: series = collect_metrics(result_dir, target.get("container_name", "__unconfigured__"), start, end, prometheus_url(args))
        except Exception as exc:
            series = {}; write_json(result_dir / "container-metrics.json", {"error": str(exc)})
            (result_dir / "container-metrics.csv").write_text("timestamp,metric,value,labels\n", encoding="utf-8")
            write_json(result_dir / "prometheus-queries.json", PROM_QUERIES)
            failure = failure or f"metric export failed: {exc}"
        derived = derived_summary(result_dir, series, max(0, end - start))
        host_config = inspect.get("HostConfig", {})
        allocated_cpu = (host_config.get("NanoCpus") or 0) / 1_000_000_000
        if not allocated_cpu and host_config.get("CpuQuota") and host_config.get("CpuPeriod"):
            allocated_cpu = host_config["CpuQuota"] / host_config["CpuPeriod"]
        derived["allocated_cpu_cores"] = allocated_cpu or None
        derived["throughput_per_allocated_cpu"] = derived.get("throughput_rps") / allocated_cpu if allocated_cpu and derived.get("throughput_rps") else None
        derived["highest_rps_meeting_thresholds"] = derived.get("throughput_rps") if exit_code == 0 else None
        write_json(result_dir / "derived-summary.json", derived)
        metadata.update({"status": "passed" if exit_code == 0 and not failure else "failed",
                         "failure_reason": failure or (f"k6/threshold exit code {exit_code}" if exit_code else None),
                         "exit_code": exit_code, "end_time_utc": dt.datetime.fromtimestamp(end, dt.timezone.utc).isoformat(),
                         "duration_seconds": max(0, end - start), "achieved_rate": derived.get("throughput_rps")})
        write_json(result_dir / "metadata.json", metadata)
        (result_dir / "README.txt").write_text(
            f"Benchmark run {run_id}\nStatus: {metadata['status']}\nTarget: {args.target}\nExperiment: {args.experiment}\n"
            "effective-config.yaml is a JSON-compatible YAML snapshot with secrets redacted.\n"
            "Raw k6 points are in k6-metrics.json.gz; exported Prometheus series are in container-metrics.*.\n", encoding="utf-8")
    print(f"Results: {result_dir}")
    if failure: print(f"Failure: {failure}", file=sys.stderr)
    return exit_code if exit_code else (1 if failure else 0)


def flatten(value, prefix=""):
    result = {}
    for key, item in value.items():
        name = f"{prefix}.{key}" if prefix else key
        if isinstance(item, dict): result.update(flatten(item, name))
        elif not isinstance(item, (list, dict)): result[name] = item
    return result


def consolidate(args):
    rows = []
    for metadata_path in sorted(RESULTS.glob("*/metadata.json")):
        try:
            metadata = read_yaml_json(metadata_path)
            summary_path = metadata_path.parent / "derived-summary.json"
            summary = read_yaml_json(summary_path) if summary_path.exists() else {}
            rows.append({"result_directory": metadata_path.parent.name, **flatten(metadata), **flatten(summary, "derived")})
        except Exception as exc: print(f"Skipping {metadata_path}: {exc}", file=sys.stderr)
    output_json = RESULTS / "consolidated.json"; output_csv = RESULTS / "consolidated.csv"
    write_json(output_json, rows)
    fields = sorted({key for row in rows for key in row})
    with open(output_csv, "w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields); writer.writeheader(); writer.writerows(rows)
    print(f"Consolidated {len(rows)} runs: {output_csv} and {output_json}")


def recollect(args):
    result_dir = Path(args.result_dir).resolve()
    if not result_dir.is_dir() or result_dir.parent != RESULTS.resolve():
        raise ValueError("--result-dir must be a direct child of results/")
    metadata = read_yaml_json(result_dir / "metadata.json")
    config = read_yaml_json(result_dir / "effective-config.yaml")
    start = dt.datetime.fromisoformat(metadata["start_time_utc"]).timestamp()
    end = dt.datetime.fromisoformat(metadata["end_time_utc"]).timestamp()
    series = collect_metrics(result_dir, config["target"].get("container_name", "__unconfigured__"), start, end, prometheus_url(args))
    derived_summary(result_dir, series, end - start)
    print(f"Metrics refreshed in {result_dir}")


def run_suite(args):
    validate_environment(args)
    targets = [item.strip() for item in args.targets.split(",") if item.strip()]
    experiments = [item.strip() for item in args.experiments.split(",") if item.strip()]
    _, experiments_path, _ = config_paths(args)
    experiment_catalog = read_yaml_json(experiments_path).get("experiments", {})
    failures = 0
    for repetition in range(1, args.repetitions + 1):
        ordered = targets[:]
        if args.order == "random": random.shuffle(ordered)
        elif args.order == "alternate" and repetition % 2 == 0: ordered.reverse()
        for experiment in experiments:
            configured_rates = experiment_catalog.get(experiment, {}).get("rates", [])
            rates = [args.rate] if args.rate is not None else (configured_rates or [None])
            for rate in rates:
                for target in ordered:
                    child = argparse.Namespace(**vars(args)); child.target = target; child.experiment = experiment
                    child.repetition = repetition; child.run_id = None; child.rate = rate; child.duration = args.duration
                    try: failures += int(run_experiment(child) != 0)
                    except Exception as exc: failures += 1; print(f"{target}/{experiment} rate={rate}: {exc}", file=sys.stderr)
    consolidate(args)
    return 1 if failures else 0


def add_common_files(parser):
    parser.add_argument("--targets-file"); parser.add_argument("--experiments-file"); parser.add_argument("--thresholds-file")
    parser.add_argument("--prometheus-url")


def main():
    parser = argparse.ArgumentParser(description="Reproducible container HTTP benchmark runner")
    sub = parser.add_subparsers(dest="command", required=True)
    validate = sub.add_parser("validate"); add_common_files(validate)
    experiment = sub.add_parser("run"); add_common_files(experiment)
    experiment.add_argument("--target", required=True); experiment.add_argument("--experiment", required=True)
    experiment.add_argument("--rate", type=float); experiment.add_argument("--duration"); experiment.add_argument("--warmup"); experiment.add_argument("--cooldown")
    experiment.add_argument("--payload"); experiment.add_argument("--base-url"); experiment.add_argument("--repetition", type=int, default=1)
    experiment.add_argument("--run-id"); experiment.add_argument("--application-commit"); experiment.add_argument("--dataset")
    experiment.add_argument("--parameter", action="append"); experiment.add_argument("--insecure-tls", action="store_true")
    experiment.add_argument("--set", dest="overrides", action="append", help="override any target/experiment/thresholds path with JSON or text")
    experiment.add_argument("--restart-target", action="store_true"); experiment.add_argument("--stabilization-seconds", type=float, default=0)
    experiment.add_argument("--pre-measurement-seconds", type=float, default=2)
    suite = sub.add_parser("suite"); add_common_files(suite)
    suite.add_argument("--targets", required=True); suite.add_argument("--experiments", required=True); suite.add_argument("--repetitions", type=int, default=1)
    suite.add_argument("--order", choices=("fixed", "alternate", "random"), default="alternate"); suite.add_argument("--rate", type=float); suite.add_argument("--duration")
    suite.add_argument("--warmup"); suite.add_argument("--cooldown"); suite.add_argument("--payload"); suite.add_argument("--base-url")
    suite.add_argument("--application-commit"); suite.add_argument("--dataset"); suite.add_argument("--parameter", action="append")
    suite.add_argument("--set", dest="overrides", action="append")
    suite.add_argument("--insecure-tls", action="store_true"); suite.add_argument("--restart-target", action="store_true")
    suite.add_argument("--stabilization-seconds", type=float, default=0); suite.add_argument("--pre-measurement-seconds", type=float, default=2)
    report = sub.add_parser("report")
    collect = sub.add_parser("collect"); collect.add_argument("--result-dir", required=True); collect.add_argument("--prometheus-url")
    args = parser.parse_args()
    try:
        if args.command == "validate": validate_environment(args); return 0
        if args.command == "run": return run_experiment(args)
        if args.command == "suite": return run_suite(args)
        if args.command == "report": consolidate(args); return 0
        if args.command == "collect": recollect(args); return 0
    except (RuntimeError, ValueError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr); return 2


if __name__ == "__main__": raise SystemExit(main())
