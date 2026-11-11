# Plano progressivo de CPU e memoria

Este roteiro mede como C++ e Elixir evoluem sob **os mesmos limites de container**, usando o mesmo payload, a mesma carga e execucao sequencial. O objetivo inicial e mapear o limite de viabilidade e a curva de desempenho; os numeros com payload sintetico validam infraestrutura, mas nao substituem a rodada cientifica com os vetores reais.

## Preparacao unica

Execute na raiz do projeto pelo WSL:

```bash
cd /mnt/c/Users/lucas/Documents/mestrado/elixir/traballho/DIS-Servidor
docker compose -f compose.dis.yaml build servidor elixir cliente
docker compose -f compose.dis.yaml up -d prometheus grafana cadvisor
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

O rebuild e obrigatorio nesta primeira rodada: o Elixir agora usa `BACKEND_WORKERS` como limite real de reconstrucoes simultaneas. Cada comando abaixo recria ambos os backends com limites iguais, espera o health check, compara a resposta logica, executa o benchmark e salva tudo em `stresser+benchmarker/results/resource-scenarios/`.

Os thresholds exploratorios rejeitam erro funcional, divergencia e iteracao descartada, mas **nao reprovam latencia alta**. Aqui a latencia e justamente o que esta sendo medido.
O timeout por requisicao foi elevado para 120 segundos, evitando confundir lentidao esperada nos containers pequenos com falha de transporte.

## Regras para comparacao justa

- Nao execute jogos, builds, atualizacoes ou outras cargas pesadas em paralelo.
- Mantenha Docker/WSL, versao do codigo, payload e configuracao termica do computador constantes.
- Execute um cenario de cada vez, na ordem proposta; o runner alterna qual backend roda primeiro.
- Use pelo menos 2 repeticoes para exploracao. Nos cenarios finalistas, use 5.
- Registre temperatura ou throttling do host nas observacoes se houver.
- Falha de health/OOM em pouca memoria e um resultado de viabilidade, nao uma rodada perdida.
- Pare a progressao e investigue se houver divergencia logica, erro acima de 1%, iteracoes descartadas, OOM ou uso sustentado muito proximo do limite.

## Matriz de 10 cenarios

O comando aceita: `ID CPU MEMORIA WORKERS [REPETICOES] [DURACAO]`.

| ID | CPU por backend | RAM por backend | Workers/VUs | Intencao |
|---|---:|---:|---:|---|
| S01 | 0,5 | 800 MiB | 1 | Encontrar o piso; Elixir pode nao iniciar ou sofrer OOM |
| S02 | 0,5 | 1,5 GiB | 1 | Isolar o minimo de memoria com meia CPU |
| S03 | 1 | 2 GiB | 1 | Referencia equivalente ao ambiente anterior |
| S04 | 1 | 4 GiB | 1 | Isolar ganho de memoria em relacao ao S03 |
| S05 | 2 | 4 GiB | 1 | Isolar ganho de CPU com uma requisicao por vez |
| S06 | 2 | 4 GiB | 2 | Medir ganho de concorrencia contra o S05 |
| S07 | 4 | 8 GiB | 2 | Aumentar recursos mantendo concorrencia fixa |
| S08 | 4 | 8 GiB | 4 | Medir ganho de concorrencia contra o S07 |
| S09 | 6 | 12 GiB | 6 | Escala intermediaria para a CPU de 12 nucleos |
| S10 | 8 | 16 GiB | 8 | Escala alta sem consumir toda a maquina |

## Comandos e ficha de resultados

### S01 — piso de memoria

```bash
bash ./scripts/run-resource-scenario.sh S01 0.5 800m 1 2 2m
```

- [ ] Executado — data: ____ / estado: ____ / pasta: ____
- Paridade: ____ | C++ media/p95: ____/____ ms | Elixir media/p95: ____/____ ms
- Throughput C++/Elixir: ____/____ req/s | erros: ____/____ | dropped: ____/____
- CPU media/pico C++: ____/____ | Elixir: ____/____
- RAM media/pico C++: ____/____ | Elixir: ____/____
- Observacoes: ____

### S02 — memoria minima com meia CPU

```bash
bash ./scripts/run-resource-scenario.sh S02 0.5 1500m 1 2 2m
```

- [ ] Executado — data: ____ / estado: ____ / pasta: ____
- Paridade: ____ | C++ media/p95: ____/____ ms | Elixir media/p95: ____/____ ms
- Throughput C++/Elixir: ____/____ req/s | erros: ____/____ | dropped: ____/____
- CPU media/pico C++: ____/____ | Elixir: ____/____
- RAM media/pico C++: ____/____ | Elixir: ____/____
- Observacoes: ____

### S03 — referencia de 1 CPU e 2 GiB

```bash
bash ./scripts/run-resource-scenario.sh S03 1 2g 1 2 2m
```

- [ ] Executado — data: ____ / estado: ____ / pasta: ____
- Paridade: ____ | C++ media/p95: ____/____ ms | Elixir media/p95: ____/____ ms
- Throughput C++/Elixir: ____/____ req/s | erros: ____/____ | dropped: ____/____
- CPU media/pico C++: ____/____ | Elixir: ____/____
- RAM media/pico C++: ____/____ | Elixir: ____/____
- Observacoes: ____

### S04 — memoria isolada

```bash
bash ./scripts/run-resource-scenario.sh S04 1 4g 1 2 2m
```

- [ ] Executado — data: ____ / estado: ____ / pasta: ____
- Paridade: ____ | C++ media/p95: ____/____ ms | Elixir media/p95: ____/____ ms
- Throughput C++/Elixir: ____/____ req/s | erros: ____/____ | dropped: ____/____
- CPU media/pico C++: ____/____ | Elixir: ____/____
- RAM media/pico C++: ____/____ | Elixir: ____/____
- Observacoes: ____

### S05 — CPU isolada com um worker

```bash
bash ./scripts/run-resource-scenario.sh S05 2 4g 1 2 2m
```

- [ ] Executado — data: ____ / estado: ____ / pasta: ____
- Paridade: ____ | C++ media/p95: ____/____ ms | Elixir media/p95: ____/____ ms
- Throughput C++/Elixir: ____/____ req/s | erros: ____/____ | dropped: ____/____
- CPU media/pico C++: ____/____ | Elixir: ____/____
- RAM media/pico C++: ____/____ | Elixir: ____/____
- Observacoes: ____

### S06 — dois workers

```bash
bash ./scripts/run-resource-scenario.sh S06 2 4g 2 2 2m
```

- [ ] Executado — data: ____ / estado: ____ / pasta: ____
- Paridade: ____ | C++ media/p95: ____/____ ms | Elixir media/p95: ____/____ ms
- Throughput C++/Elixir: ____/____ req/s | erros: ____/____ | dropped: ____/____
- CPU media/pico C++: ____/____ | Elixir: ____/____
- RAM media/pico C++: ____/____ | Elixir: ____/____
- Observacoes: ____

### S07 — quatro CPUs e dois workers

```bash
bash ./scripts/run-resource-scenario.sh S07 4 8g 2 2 2m
```

- [ ] Executado — data: ____ / estado: ____ / pasta: ____
- Paridade: ____ | C++ media/p95: ____/____ ms | Elixir media/p95: ____/____ ms
- Throughput C++/Elixir: ____/____ req/s | erros: ____/____ | dropped: ____/____
- CPU media/pico C++: ____/____ | Elixir: ____/____
- RAM media/pico C++: ____/____ | Elixir: ____/____
- Observacoes: ____

### S08 — quatro workers

```bash
bash ./scripts/run-resource-scenario.sh S08 4 8g 4 2 2m
```

- [ ] Executado — data: ____ / estado: ____ / pasta: ____
- Paridade: ____ | C++ media/p95: ____/____ ms | Elixir media/p95: ____/____ ms
- Throughput C++/Elixir: ____/____ req/s | erros: ____/____ | dropped: ____/____
- CPU media/pico C++: ____/____ | Elixir: ____/____
- RAM media/pico C++: ____/____ | Elixir: ____/____
- Observacoes: ____

### S09 — escala intermediaria

```bash
bash ./scripts/run-resource-scenario.sh S09 6 12g 6 2 2m
```

- [ ] Executado — data: ____ / estado: ____ / pasta: ____
- Paridade: ____ | C++ media/p95: ____/____ ms | Elixir media/p95: ____/____ ms
- Throughput C++/Elixir: ____/____ req/s | erros: ____/____ | dropped: ____/____
- CPU media/pico C++: ____/____ | Elixir: ____/____
- RAM media/pico C++: ____/____ | Elixir: ____/____
- Observacoes: ____

### S10 — escala alta controlada

```bash
bash ./scripts/run-resource-scenario.sh S10 8 16g 8 2 2m
```

- [ ] Executado — data: ____ / estado: ____ / pasta: ____
- Paridade: ____ | C++ media/p95: ____/____ ms | Elixir media/p95: ____/____ ms
- Throughput C++/Elixir: ____/____ req/s | erros: ____/____ | dropped: ____/____
- CPU media/pico C++: ____/____ | Elixir: ____/____
- RAM media/pico C++: ____/____ | Elixir: ____/____
- Observacoes: ____

## Como interpretar

Compare primeiro os pares S03/S04 (efeito de RAM), S05/S06 (efeito de concorrencia) e S07/S08 (concorrencia com mais folga). Em cada par, observe mediana/p95, throughput, CPU, pico de memoria, erros e iteracoes descartadas. Mais RAM sem queda de latencia indica que memoria ja nao e o gargalo; mais workers sem maior throughput indica saturacao de CPU ou paralelismo interno limitado.

Depois de executar alguns cenarios, envie as pastas `resource-scenarios/Sxx-*` ou deixe-as no projeto. Os campos deste documento podem ser preenchidos a partir de `consolidated.csv`, `backend-parity.json`, `container-inspect.json` e `status.env`.
