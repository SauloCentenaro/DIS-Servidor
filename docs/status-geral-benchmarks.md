# Estado geral do DIS e resumo dos benchmarks

Atualizado em 12/11/2026.

## Resumo executivo

O ambiente integrado esta funcional e pronto para ser versionado. A stack sobe os servidores C++ e Elixir, o client Angular e a observabilidade com Prometheus, Grafana e cAdvisor. A carga nao inicia junto com os servicos: benchmarks e stress tests continuam sob demanda.

Os dois backends recebem o mesmo payload, montam as mesmas matrizes, usam limites de container equivalentes e passam por uma comparacao logica antes de cada cenario. A matriz exploratoria S01-S10 foi concluida. S01 confirmou que 800 MiB sao inviaveis para o Elixir; S02-S10 completaram sem divergencias, erros HTTP ou iteracoes descartadas.

No total, foram medidas 1.906 requisicoes validas nos cenarios concluidos. O principal resultado e que mais recursos aumentam a capacidade de atender operacoes simultaneas, mas nao tornam automaticamente uma unica reconstrucao mais rapida. A partir de S08, o throughput continuou crescendo, enquanto a latencia individual tambem aumentou por contencao entre workers.

## O que esta implementado

- Compose raiz para C++, Elixir, client, Prometheus, Grafana e cAdvisor.
- k6 no profile `tools`, executado somente por trigger explicito.
- Mesmas matrizes montadas nos dois backends a partir de `data/matrices`.
- Mesmos limites de CPU, memoria, reserva, PIDs e workers para C++ e Elixir.
- `BACKEND_WORKERS` como limite real de reconstrucoes simultaneas no Elixir.
- Geracao de payload a partir de CSV ou de dados sinteticos deterministicos.
- Comparador backend-to-backend que reproduz a preparacao feita pelo front e verifica `user`, `iteracoes` e `imageVector`.
- Suite pareada que alterna a ordem C++/Elixir para reduzir vies de aquecimento.
- Coleta de latencia, throughput, erros, CPU, memoria, rede e metadados do ambiente.
- Runner progressivo de recursos com preflight, janela de estabilidade, diagnostico de OOM e preservacao dos artefatos.
- Relatorio consolidado em CSV/JSON e pastas imutaveis para cada execucao.

## Integridade e equivalencia

Antes da carga, cada cenario chama `scripts/compare_backends.py`. Nos cenarios S02-S10, os resultados foram equivalentes, sem divergencias. A validacao usa o modelo 2, com 27.904 amostras, e executa 20 iteracoes em cada backend.

As execucoes pareadas usam:

- o mesmo payload e hash;
- a mesma duracao e quantidade de workers/VUs;
- limites iguais de container;
- execucao sequencial, sem concorrencia entre os dois backends;
- duas repeticoes, alternando qual implementacao roda primeiro;
- timeout de 120 segundos por requisicao;
- rejeicao de erro funcional, divergencia e iteracao descartada.

O coletor agora escapa corretamente nomes de containers nas consultas PromQL. Se todas as metricas criticas de CPU e memoria falharem, a execucao tambem falha, evitando um resultado falso-positivo.

## Resultados S01-S10

Latencia e p95 estao em milissegundos. Throughput esta em requisicoes por segundo. Os valores sao medias de duas repeticoes, exceto S01, que falhou corretamente antes da carga.

| ID | CPU/RAM por backend | Workers | C++ media/p95 | C++ req/s | Elixir media/p95 | Elixir req/s | Resultado |
|---|---:|---:|---:|---:|---:|---:|---|
| S01 | 0,5 / 800 MiB | 1 | N/A | N/A | N/A | N/A | Elixir OOM; 13 reinicios; carga bloqueada |
| S02 | 0,5 / 1,5 GiB | 1 | 3659 / 3789 | 0,2733 | 32167 / 32370 | 0,0311 | Completo |
| S03 | 1 / 2 GiB | 1 | 3146 / 3213 | 0,3179 | 16308 / 17579 | 0,0614 | Completo |
| S04 | 1 / 4 GiB | 1 | 3077 / 3222 | 0,3249 | 16679 / 17979 | 0,0600 | Completo |
| S05 | 2 / 4 GiB | 1 | 3121 / 3240 | 0,3204 | 14053 / 14581 | 0,0712 | Completo |
| S06 | 2 / 4 GiB | 2 | 3224 / 3397 | 0,6191 | 17044 / 17740 | 0,1173 | Completo |
| S07 | 4 / 8 GiB | 2 | 3295 / 3538 | 0,6041 | 16345 / 17539 | 0,1223 | Completo |
| S08 | 4 / 8 GiB | 4 | 3575 / 3994 | 1,1115 | 22260 / 22871 | 0,1795 | Completo |
| S09 | 6 / 12 GiB | 6 | 4236 / 4904 | 1,4043 | 27078 / 27661 | 0,2214 | Completo |
| S10 | 8 / 16 GiB | 8 | 4971 / 5763 | 1,5925 | 31193 / 31926 | 0,2560 | Completo |

O detalhamento de CPU, memoria, quantidade de requisicoes e pasta de cada sessao esta em [`resource-scaling-plan.md`](resource-scaling-plan.md).

## Interpretacao dos resultados

### Memoria

S01 falhou por falta de memoria no Elixir. S02 iniciou, mas atingiu praticamente todo o limite de 1,5 GiB. S03 tambem operou muito proximo dos 2 GiB. Em S04, aumentar de 2 para 4 GiB removeu a pressao de memoria, mas nao melhorou o tempo de processamento. Depois que o working set cabe com folga no container, RAM adicional evita OOM, mas nao acelera o calculo.

### CPU e concorrencia

S06 quase dobrou o throughput C++ ao passar de um para dois workers. S07 dobrou CPU e RAM mantendo dois workers e nao trouxe ganho material, demonstrando que recursos ociosos nao melhoram uma carga sem paralelismo suficiente.

S08, S09 e S10 aumentaram recursos e concorrencia juntos. O throughput cresceu, mas a latencia individual tambem aumentou:

- S07 para S08: throughput +84% no C++ e +47% no Elixir.
- S08 para S09: throughput +26% no C++ e +23% no Elixir.
- S09 para S10: throughput +13% no C++ e +16% no Elixir.

Os ganhos marginais diminuem conforme workers e recursos aumentam. No S10, o Elixir chegou ao limite de aproximadamente 8 cores; o C++ atingiu cerca de 4,75 cores no pico. Portanto, adicionar ainda mais CPUs provavelmente nao produzira ganho proporcional sem alterar o algoritmo ou o modelo de paralelismo.

### Latencia versus throughput

S10 e o melhor cenario para capacidade total, nao para o menor tempo de uma requisicao. Contra S07, o throughput aumentou 2,64 vezes no C++ e 2,09 vezes no Elixir, mas a latencia media subiu 51% e 91%, respectivamente. Varias reconstrucoes simultaneas disputam os mesmos recursos e demoram mais individualmente, embora mais trabalho seja concluido por unidade de tempo.

Para uma operacao isolada, S04/S05 representam melhor a latencia atual. Para equilibrio entre capacidade, consumo e latencia, S08 ou S09 sao candidatos mais razoaveis que S10.

## Estado dos testes

Na validacao final desta rodada:

- os 7 testes Python passaram;
- as consultas criticas de Prometheus retornaram dados em S08-S10;
- ambos os containers terminaram saudaveis e sem reinicios;
- os limites ativos de S10 ficaram iguais: 8 CPUs e 16 GiB por backend;
- Prometheus, Grafana e cAdvisor terminaram saudaveis.

O projeto tambem possui testes no build de cada componente:

- C++: regressao nativa em `tests/regression.cpp`;
- Elixir: `mix test`;
- client: Karma/Chrome headless, incluindo fan-out e deteccao de divergencia;
- integracao Docker: health, igualdade dos limites e paridade logica.

## Como reproduzir

Execute na raiz do projeto pelo WSL:

```bash
cd /mnt/c/Users/lucas/Documents/mestrado/elixir/traballho/DIS-Servidor
cp .env.example .env
# Ajuste GRAFANA_ADMIN_PASSWORD no .env.
docker compose -f compose.dis.yaml up -d --build
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Validacao direta dos dois backends:

```bash
python3 scripts/compare_backends.py \
  --payload stresser+benchmarker/k6/payloads/dis-request.json \
  --output stresser+benchmarker/results/backend-parity.json
```

Suite pareada sob demanda:

```bash
./run-benchmark.sh smoke
./run-benchmark.sh load 5 5
./run-benchmark.sh stress "" 3
```

Um cenario progressivo especifico:

```bash
bash ./scripts/run-resource-scenario.sh S08 4 8g 4 2 2m
```

Para desligar:

```bash
docker compose -f compose.dis.yaml down
```

## Artefatos

- Plano e ficha completa: `docs/resource-scaling-plan.md`.
- Sessoes progressivas: `stresser+benchmarker/results/resource-scenarios/Sxx-*`.
- Cada rodada medida: `stresser+benchmarker/results/<data>-<run-id>-<target>-<experimento>`.
- Consolidado geral: `stresser+benchmarker/results/consolidated.csv` e `consolidated.json`.
- Observabilidade: Grafana em `http://localhost:3000`, Prometheus em `http://localhost:9090` e cAdvisor em `http://localhost:8082`.

Cada pasta de execucao preserva configuracao efetiva, ambiente, logs, inspect do container, resumo k6, metricas brutas e metricas derivadas. Os resultados nao sao sobrescritos.

## Limitacoes e proximos passos

1. Esta matriz e exploratoria e usa apenas duas repeticoes. Os cenarios finalistas devem ser repetidos pelo menos cinco vezes.
2. Os numeros atuais validam a infraestrutura e a curva tecnica. A rodada cientifica final deve usar explicitamente os vetores reais selecionados e registrar seus hashes.
3. Temperatura, frequencia e throttling do host ainda nao foram registrados junto aos resultados.
4. O WSL enxergou aproximadamente 31 GiB, apesar dos 64 GiB fisicos. Isso nao afetou S01-S10, pois o consumo observado ficou abaixo de 5 GiB por backend, mas deve ser ajustado antes de cenarios maiores.
5. O proximo ganho relevante tende a vir de profiling e otimizacao do algoritmo, especialmente no Elixir, e nao apenas de mais CPU ou RAM.
6. Para a comparacao final, selecionar S05 para latencia isolada e S08/S09 para capacidade, executar cinco ou mais repeticoes e aplicar analise estatistica sobre as rodadas.

## Estado no encerramento

O ambiente permanece no perfil S10: 8 CPUs, 16 GiB e 8 workers por backend. C++ e Elixir estao saudaveis, com limites iguais e sem reinicios. A stack pode ser derrubada normalmente ou reutilizada para novas rodadas sob demanda.
