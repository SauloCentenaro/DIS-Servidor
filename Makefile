SHELL := /bin/sh
COMPOSE := docker compose -f compose.dis.yaml
EXPERIMENT ?= smoke
RATE ?=
REPETITIONS ?= 1

.PHONY: up down logs test verify benchmark report
up:
	$(COMPOSE) up -d --build
down:
	$(COMPOSE) down
logs:
	$(COMPOSE) logs -f servidor elixir cliente prometheus cadvisor grafana
test:
	$(COMPOSE) build servidor elixir cliente
verify:
	powershell -ExecutionPolicy Bypass -File ./verify-docker.ps1
benchmark:
	sh ./run-benchmark.sh $(EXPERIMENT) $(RATE) $(REPETITIONS)
report:
	python3 stresser+benchmarker/scripts/benchmark.py report
