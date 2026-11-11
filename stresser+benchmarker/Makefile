SHELL := /bin/sh
COMPOSE := docker compose -f ../compose.dis.yaml
TARGET ?= mock
RATE ?= 5
REPETITIONS ?= 1

.PHONY: up down validate smoke baseline load suite report mock-up
up:
	$(COMPOSE) up -d --build
mock-up:
	$(COMPOSE) --profile mock up -d
down:
	$(COMPOSE) --profile mock down
validate:
	sh scripts/validate-environment.sh
smoke:
	sh scripts/run-experiment.sh --target $(TARGET) --experiment smoke
baseline:
	sh scripts/run-experiment.sh --target $(TARGET) --experiment baseline
load:
	sh scripts/run-experiment.sh --target $(TARGET) --experiment load --rate $(RATE)
suite:
	sh scripts/run-suite.sh --targets $(TARGET) --experiments smoke,baseline,load --repetitions $(REPETITIONS)
report:
	python scripts/benchmark.py report
