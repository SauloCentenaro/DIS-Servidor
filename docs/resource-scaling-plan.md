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

- [x] Executado — data: 11/11/2026 / estado: `HEALTH_FAILURE` / pasta: `S01-20261111-223858`
- Paridade: nao executada | C++ media/p95: N/A | Elixir media/p95: N/A
- Throughput C++/Elixir: N/A | erros: N/A | dropped: N/A
- CPU media/pico C++: N/A | Elixir: N/A
- RAM media/pico C++: N/A | Elixir: N/A
- Observacoes: repetido com preflight tolerante a reinicios e janela de 5 minutos. C++ permaneceu saudavel sem reinicios; Elixir reiniciou 13 vezes, nunca estabilizou e terminou com `OOMKilled=true`. Confirmado: 800 MiB e inviavel para o Elixir neste workload. A carga pareada foi corretamente bloqueada, portanto tempos e metricas de benchmark permanecem N/A.

### S02 — memoria minima com meia CPU

```bash
bash ./scripts/run-resource-scenario.sh S02 0.5 1500m 1 2 2m
```

- [x] Executado — data: 11/11/2026 / estado: `COMPLETE` / pasta: `S02-20261111-181041`
- Paridade: equivalente, sem divergencias | C++ media/p95: 3659/3789 ms | Elixir media/p95: 32167/32370 ms
- Throughput C++/Elixir: 0,2733/0,0311 req/s | erros: 0%/0% | dropped: 0/0
- CPU media/pico C++: 0,431/0,459 core | Elixir: 0,482/0,504 core
- RAM media/pico C++: 244/590 MiB | Elixir: 1420/1498 MiB
- Observacoes: medias de 2 repeticoes com ordem alternada. Elixir usou 99,87% dos 1500 MiB e ficou 8,79x mais lento; o throughput do C++ foi 8,79x maior. S02 funciona, mas nao oferece margem segura de memoria ao Elixir. Todas as 75 requisicoes medidas (67 C++ e 8 Elixir) passaram sem erro.

### S03 — referencia de 1 CPU e 2 GiB

```bash
bash ./scripts/run-resource-scenario.sh S03 1 2g 1 2 2m
```

- [x] Executado — data: 11/11/2026 / estado: `COMPLETE` / pasta: `S03-20261111-224453`
- Paridade: equivalente, sem divergencias | C++ media/p95: 3146/3213 ms | Elixir media/p95: 16308/17579 ms
- Throughput C++/Elixir: 0,3179/0,0614 req/s | erros: 0%/0% | dropped: 0/0
- CPU media/pico C++: 0,519/0,575 core | Elixir: 0,964/1,002 core
- RAM media/pico C++: 205/590 MiB | Elixir: 1966/2046 MiB
- Observacoes: medias de 2 repeticoes com ordem alternada. Foram 93 requisicoes medidas (77 C++ e 16 Elixir), todas validas. C++ apresentou 5,18x mais throughput e o Elixir ficou 5,18x mais lento. O Elixir atingiu 99,91% do limite de 2 GiB; o cenario funciona, mas ainda sem margem confortavel de memoria.

### S04 — memoria isolada

```bash
bash ./scripts/run-resource-scenario.sh S04 1 4g 1 2 2m
```

- [x] Executado — data: 12/11/2026 / estado: `COMPLETE` / pasta: `S04-20261112-115729`
- Paridade: equivalente, sem divergencias | C++ media/p95: 3077/3222 ms | Elixir media/p95: 16679/17979 ms
- Throughput C++/Elixir: 0,3249/0,0600 req/s | erros: 0%/0% | dropped: 0/0
- CPU media/pico C++: 0,526/0,582 core | Elixir: 0,963/1,002 core
- RAM media/pico C++: 217/590 MiB | Elixir: 2310/2394 MiB
- Observacoes: 95 requisicoes medidas, todas validas. Dobrar a RAM de S03 para S04, mantendo 1 CPU e 1 worker, nao melhorou a velocidade: os resultados ficaram dentro da variacao entre repeticoes. A pressao contra o limite desapareceu, confirmando que 4 GiB oferecem seguranca, mas RAM adicional sozinha nao acelera o calculo.

### S05 — CPU isolada com um worker

```bash
bash ./scripts/run-resource-scenario.sh S05 2 4g 1 2 2m
```

- [x] Executado — data: 12/11/2026 / estado: `COMPLETE` / pasta: `S05-20261112-121244`
- Paridade: equivalente, sem divergencias | C++ media/p95: 3121/3240 ms | Elixir media/p95: 14053/14581 ms
- Throughput C++/Elixir: 0,3204/0,0712 req/s | erros: 0%/0% | dropped: 0/0
- CPU media/pico C++: 0,529/0,588 core | Elixir: 1,122/1,202 core
- RAM media/pico C++: 262/590 MiB | Elixir: 2308/2394 MiB
- Observacoes: 96 requisicoes medidas, todas validas. A segunda CPU nao alterou materialmente o C++, mas reduziu a latencia media do Elixir em cerca de 15,7% e elevou seu throughput em 18,7% contra S04. Com um worker, ambos permanecem longe de consumir as 2 CPUs completas.

### S06 — dois workers

```bash
bash ./scripts/run-resource-scenario.sh S06 2 4g 2 2 2m
```

- [x] Executado — data: 12/11/2026 / estado: `COMPLETE` / pasta: `S06-20261112-122756`
- Paridade: equivalente, sem divergencias | C++ media/p95: 3224/3397 ms | Elixir media/p95: 17044/17740 ms
- Throughput C++/Elixir: 0,6191/0,1173 req/s | erros: 0%/0% | dropped: 0/0
- CPU media/pico C++: 1,032/1,172 core | Elixir: 1,885/2,003 cores
- RAM media/pico C++: 464/1167 MiB | Elixir: 2472/2660 MiB
- Observacoes: 182 requisicoes medidas, todas validas. Contra S05, dois workers quase dobraram o throughput C++ (+93%) e elevaram o Elixir em cerca de 65%. A latencia individual subiu 3% no C++ e 21% no Elixir, troca esperada por mais concorrencia. O Elixir saturou as 2 CPUs, mas permaneceu com folga dentro dos 4 GiB.

### S07 — quatro CPUs e dois workers

```bash
bash ./scripts/run-resource-scenario.sh S07 4 8g 2 2 2m
```

- [x] Executado — data: 12/11/2026 / estado: `COMPLETE` / pasta: `S07-20261112-124310`
- Paridade: equivalente, sem divergencias | C++ media/p95: 3295/3538 ms | Elixir media/p95: 16345/17539 ms
- Throughput C++/Elixir: 0,6041/0,1223 req/s | erros: 0%/0% | dropped: 0/0
- CPU media/pico C++: 1,029/1,159 core | Elixir: 2,025/2,251 cores
- RAM media/pico C++: 514/1167 MiB | Elixir: 2490/2665 MiB
- Observacoes: 179 requisicoes medidas, todas validas. Dobrar CPU/RAM de S06 para S07 com apenas 2 workers nao trouxe ganho material: C++ variou -2,4% em throughput e Elixir +4,3%, dentro da dispersao. O gargalo passou a ser a concorrencia configurada; mais recursos ficaram ociosos.

### S08 — quatro workers

```bash
bash ./scripts/run-resource-scenario.sh S08 4 8g 4 2 2m
```

- [x] Executado — data: 12/11/2026 / estado: `COMPLETE` / pasta: `S08-20261112-131328`
- Paridade: equivalente, sem divergencias | C++ media/p95: 3575/3994 ms | Elixir media/p95: 22260/22871 ms
- Throughput C++/Elixir: 1,1115/0,1795 req/s | erros: 0%/0% | dropped: 0/0
- CPU media/pico C++: 1,958/2,289 cores | Elixir: 3,497/4,007 cores
- RAM media/pico C++: 792/2320 MiB | Elixir: 2871/3231 MiB
- Observacoes: 321 requisicoes medidas, todas validas. Contra S07, elevar de 2 para 4 workers aumentou o throughput C++ em cerca de 84% e o Elixir em 47%, mas elevou a latencia individual em 9% e 36%, respectivamente. Os 4 cores foram efetivamente aproveitados pelo Elixir; ambos permaneceram dentro dos 8 GiB.

### S09 — escala intermediaria

```bash
bash ./scripts/run-resource-scenario.sh S09 6 12g 6 2 2m
```

- [x] Executado — data: 12/11/2026 / estado: `COMPLETE` / pasta: `S09-20261112-132852`
- Paridade: equivalente, sem divergencias | C++ media/p95: 4236/4904 ms | Elixir media/p95: 27078/27661 ms
- Throughput C++/Elixir: 1,4043/0,2214 req/s | erros: 0%/0% | dropped: 0/0
- CPU media/pico C++: 2,728/3,372 cores | Elixir: 4,847/6,006 cores
- RAM media/pico C++: 1341/3474 MiB | Elixir: 3228/3748 MiB
- Observacoes: 407 requisicoes medidas, todas validas. Contra S08, o throughput cresceu 26% no C++ e 23% no Elixir, enquanto a latencia media subiu 18% e 22%. O Elixir atingiu o limite de 6 CPUs; o C++ ainda utilizou menos de 4 cores no pico. Houve ganho de capacidade, mas com eficiencia marginal decrescente.

### S10 — escala alta controlada

```bash
bash ./scripts/run-resource-scenario.sh S10 8 16g 8 2 2m
```

- [x] Executado — data: 12/11/2026 / estado: `COMPLETE` / pasta: `S10-20261112-134450`
- Paridade: equivalente, sem divergencias | C++ media/p95: 4971/5763 ms | Elixir media/p95: 31193/31926 ms
- Throughput C++/Elixir: 1,5925/0,2560 req/s | erros: 0%/0% | dropped: 0/0
- CPU media/pico C++: 3,356/4,746 cores | Elixir: 6,083/8,007 cores
- RAM media/pico C++: 1783/4628 MiB | Elixir: 3550/4211 MiB
- Observacoes: 458 requisicoes medidas, todas validas. Contra S09, o throughput cresceu apenas 13% no C++ e 16% no Elixir, com aumento de 17% e 15% na latencia media. O Elixir saturou as 8 CPUs; o C++ ficou abaixo de 5 cores no pico. A escala continua positiva, mas o custo de CPU, memoria e latencia cresce mais rapido que o throughput.

## Como interpretar

Compare primeiro os pares S03/S04 (efeito de RAM), S05/S06 (efeito de concorrencia) e S07/S08 (concorrencia com mais folga). Em cada par, observe mediana/p95, throughput, CPU, pico de memoria, erros e iteracoes descartadas. Mais RAM sem queda de latencia indica que memoria ja nao e o gargalo; mais workers sem maior throughput indica saturacao de CPU ou paralelismo interno limitado.

Depois de executar alguns cenarios, envie as pastas `resource-scenarios/Sxx-*` ou deixe-as no projeto. Os campos deste documento podem ser preenchidos a partir de `consolidated.csv`, `backend-parity.json`, `container-inspect.json` e `status.env`.
