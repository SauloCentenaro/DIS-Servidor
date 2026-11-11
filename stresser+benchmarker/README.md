# HTTP Container Benchmark Lab

Laboratório reproduzível para comparar aplicações HTTP em containers com a mesma carga, validação e observabilidade. A aplicação avaliada não faz parte deste repositório: o runner dirige o k6 até uma URL configurável, o cAdvisor observa os containers, o Prometheus mantém as séries e o Grafana as apresenta.

```text
runner → k6 → aplicação alvo
   └────────→ API do Prometheus ← cAdvisor ← Docker
                              └────────────→ Grafana
```

## Pré-requisitos e início rápido

- Docker Engine com Compose v2; Python 3.10+ no host.
- Linux é o ambiente de referência. No Windows, use Docker Desktop com containers Linux e PowerShell 7 ou Windows PowerShell 5.1.
- Copie `.env.example` para `.env` e troque `GRAFANA_ADMIN_PASSWORD`.

Para provar todo o fluxo com o mock (que não é uma aplicação de benchmark real):

```bash
cp .env.example .env
docker compose --profile mock up -d
./scripts/validate-environment.sh
./scripts/run-experiment.sh --target mock --experiment smoke
python3 scripts/benchmark.py report
```

No PowerShell:

```powershell
Copy-Item .env.example .env
docker compose --profile mock up -d
./scripts/validate-environment.ps1
./scripts/run-experiment.ps1 -Target mock -Experiment smoke
python scripts/benchmark.py report
```

Prometheus fica em <http://localhost:9090>, Grafana em <http://localhost:3000> e cAdvisor em <http://localhost:8082>. O datasource e os dashboards `Benchmark - Containers` e `Benchmark - HTTP` são provisionados automaticamente. As portas escutam apenas em `127.0.0.1` por padrão.

## Configuração

Os arquivos `configs/*.yaml` usam sintaxe JSON, que é um subconjunto válido de YAML. Isso permite ao runner funcionar sem `yq`, PyYAML ou módulo PowerShell. Copie os exemplos para arquivos locais se quiser mantê-los fora do Git e selecione-os com `--targets-file`, `--experiments-file`, `--thresholds-file` ou `BENCH_*_FILE`.

Um target aceita `base_url`, `endpoint`, `method`, `headers`, `payload`, `container_name`, `expected_status`, `timeout`, `health_endpoint`, `required_fields`, `minimum_response_bytes`, `array_lengths`, `response_equals`, `maximum_duration_ms`, `tags`, `full_validation` e `insecure_tls`. Sem `health_endpoint`, a prontidão é verificada no endpoint principal usando método, payload e status configurados. Não grave tokens no arquivo versionado; arquivos efetivos redigem nomes de headers sensíveis.

Para adicionar um target, duplique uma entrada em `configs/targets.example.yaml`. A URL pode apontar para o host (`host.docker.internal`), uma rede Docker externa ou outra máquina. Para nomes em uma network externa, conecte `http-benchmark-lab_default` à rede ou adapte `compose.yaml` declarando a rede externa.

Payloads ficam em `k6/payloads/` e são enviados sem transformação. O hash SHA-256 é registrado. Para payloads/datasets grandes, passe `--dataset` para registrar também seu hash.

Experimentos ficam em `configs/experiments.example.yaml`. Para adicionar um cenário que use um dos executores suportados, crie a configuração e um arquivo em `k6/scenarios/` reexportando `common.js`. Os tipos disponíveis são `shared-iterations`, `constant-vus`, `constant-arrival-rate` e `ramping-arrival-rate`.

Thresholds são critérios de aceite, não valores universais. Execute primeiro a baseline, observe a variabilidade e só então defina SLOs realistas. Um threshold violado produz saída k6 diferente de zero e a execução fica marcada como falha.

## Execução

```bash
make up
make smoke TARGET=cpp
make load TARGET=cpp RATE=5
make suite TARGET=cpp,elixir REPETITIONS=5
make report
make down
```

Forma completa:

```bash
./scripts/run-experiment.sh \
  --target cpp --experiment load --rate 5 \
  --payload k6/payloads/example.json --repetition 1

./scripts/run-suite.sh \
  --targets cpp,elixir --experiments smoke,baseline,load,stress \
  --repetitions 5 --order alternate
```

```powershell
./scripts/run-experiment.ps1 -Target cpp -Experiment load -Rate 5 `
  -Payload k6/payloads/example.json -Repetition 1
./scripts/run-suite.ps1 -Targets cpp,elixir `
  -Experiments smoke,baseline,load,stress -Repetitions 5 -Order alternate
```

CLI sobrescreve taxa, duração, warmup, cooldown, payload e URL. Qualquer outro campo pode ser trocado sem editar scripts com `--set experiment.max_vus=400`, `--set target.timeout=\"45s\"` ou com `BENCH_OVERRIDES='{"experiment":{"max_vus":400}}'`. Variáveis `BENCH_TARGETS_FILE`, `BENCH_EXPERIMENTS_FILE`, `BENCH_THRESHOLDS_FILE` e `PROMETHEUS_URL` selecionam fontes. Sem `--rate`, a suíte percorre todos os valores de `rates`; uma execução individual usa `rate`. A suíte é sequencial; `alternate` inverte os alvos a cada repetição e `random` embaralha. `--restart-target` reinicia explicitamente o container configurado; limites de CPU/memória nunca são alterados.

## Resultados e reprodução

Cada execução cria, sem sobrescrever, `results/<data>-<run-id>-<target>-<experimento>/`. Ela contém metadados, configuração efetiva redigida, resumo e pontos brutos do k6 compactados, checks, inspect/logs, ambiente, queries, séries do container em JSON/CSV e `derived-summary.json`. Falhas preservam tudo que já foi produzido. `python scripts/benchmark.py report` cria `consolidated.csv` e `consolidated.json` sem descartar os dados brutos.

Para reexportar séries enquanto o Prometheus ainda as retém:

```bash
./scripts/collect-metrics.sh --result-dir results/20260101-120000-id-cpp-load
```

Para reproduzir uma execução, copie `target`, `experiment` e `thresholds` de `effective-config.yaml` para arquivos de configuração (repondo apenas segredos redigidos), confira o mesmo commit/imagem/payload e execute o runner com os mesmos overrides. O arquivo é deliberadamente legível como JSON e YAML.

## Isolamento experimental

Execute um alvo por vez, com os mesmos limites, payloads, endpoints, validações, warmup, cooldown e política de cache. Evite tarefas concorrentes no host. O k6 não roda dentro do alvo e suas métricas não entram no filtro do container. Repita os testes, alterne a ordem e separe cold start de testes aquecidos. O desenho ideal usa máquina A para k6 e máquina B para alvo/cAdvisor/Prometheus; no modo local, k6 e alvo competem pela mesma máquina ou VM.

Em duas máquinas, ajuste `base_url` para a máquina do alvo e `K6_PROMETHEUS_RW_SERVER_URL`/`PROMETHEUS_URL` conforme a rede. Proteja o tráfego; a stack não implementa autenticação de rede.

## Linux, Windows e segurança

O cAdvisor monta `/`, `/var/run`, `/sys`, `/var/lib/docker` e `/dev/disk` somente para leitura e recebe `/dev/kmsg` e modo privilegiado para enxergar cgroups, runtime, filesystem e dispositivos. Isso é apropriado apenas a um laboratório local confiável. Não publique cAdvisor, Prometheus ou Grafana na Internet. Mantenha `BIND_ADDRESS=127.0.0.1`, troque a senha do Grafana e use firewall/túnel autenticado se acesso remoto for inevitável.

No Docker Desktop, cAdvisor observa principalmente a VM Linux, pode não expor nomes, limites, processos, block I/O, pico de memória ou OOM da mesma forma que Docker Engine nativo. O mount `/var/lib/docker` também varia conforme a versão/backend. CPU e memória podem refletir limites da VM; WSL2 adiciona outra camada. Para resultados publicáveis, prefira Linux nativo.

Em uma cópia que não preservou permissões Unix, execute uma vez `chmod +x scripts/*.sh`; os alvos do Makefile também podem ser chamados com `sh scripts/<nome>.sh`.

## Problemas comuns

- `host.docker.internal` já recebe `host-gateway` no Compose para Linux. Se o alvo escuta apenas em `127.0.0.1` no host, faça-o escutar em uma interface acessível ao Docker.
- Métricas vazias: confirme `container_name`, abra `http://localhost:9090/targets` e procure `container_last_seen` no Prometheus. Nomes do Compose normalmente incluem projeto e índice.
- Grafana sem painéis: confira logs e os arquivos de provisioning; não é necessário criar datasource manualmente.
- `dropped_iterations`: o gerador não conseguiu sustentar a taxa; aumente `preallocated_vus`/`max_vus` ou reduza carga, sem confundir com latência do alvo.
- Docker Desktop sem cAdvisor saudável: consulte [docs/troubleshooting.md](docs/troubleshooting.md) e use Linux nativo para a coleta completa.

Conceitos e regras de comparação estão em [docs/methodology.md](docs/methodology.md); nomes, unidades e limitações das métricas estão em [docs/metrics.md](docs/metrics.md).
