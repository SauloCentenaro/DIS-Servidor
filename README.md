# DIS — C++, Elixir, client e benchmark

O Compose raiz sobe os dois servidores, o client e toda a observabilidade. O k6 está no profile `tools` e só executa quando você dispara um benchmark; subir a stack nunca inicia carga automaticamente.

## O que você precisa fornecer

Os dados científicos não estão no repositório. Antes de construir a stack, coloque:

```text
data/matrices/H-1.csv
data/matrices/H-2.csv
DIS-Cliente/src/assets/model1/MODEL1.csv
DIS-Cliente/src/assets/model1/MODEL2.csv
DIS-Cliente/src/assets/model1/MODEL3.csv
DIS-Cliente/src/assets/model2/MODEL1.csv
DIS-Cliente/src/assets/model2/MODEL2.csv
DIS-Cliente/src/assets/model2/MODEL3.csv
```

Os dois backends montam as mesmas matrizes de `data/matrices`. `model=true` usa `H-1.csv` (50.816 amostras, saída 60×60) e `model=false` usa `H-2.csv` (27.904 amostras, saída 30×30). Os pequenos arquivos em `data/samples` são preservados, mas não têm as dimensões exigidas por estas matrizes.

## Subir tudo

Pré-requisitos: Docker Desktop/Engine com Docker Compose 2.20 ou superior (para `include`) e Python 3 para o runner do benchmark.

```powershell
Copy-Item .env.example .env
# troque GRAFANA_ADMIN_PASSWORD em .env
docker compose -f compose.dis.yaml up -d --build
./verify-docker.ps1
```

Linux/macOS:

```bash
cp .env.example .env
docker compose -f compose.dis.yaml up -d --build
```

Serviços: client `http://localhost:4200`, C++ `:8080`, Elixir `:8081`, Grafana `:3000`, Prometheus `:9090` e cAdvisor `:8082`. As portas ficam restritas a localhost por padrão.

Os backends recebem exatamente `BACKEND_CPUS`, `BACKEND_MEMORY`, `BACKEND_MEMORY_RESERVATION`, `BACKEND_PIDS_LIMIT` e `BACKEND_WORKERS`. O padrão é uma reconstrução por vez, 1 CPU e 2 GiB para cada um. O client envia cada pedido aos dois servidores e só aceita a resposta quando `user`, `iteracoes` e `imageVector` são iguais; tempos são deliberadamente ignorados nessa paridade.

## Preparar e disparar benchmark nos dois

Gere um único payload a partir do mesmo CSV usado pelo client:

```powershell
py -3 stresser+benchmarker/scripts/generate-payload.py `
  --vector DIS-Cliente/src/assets/model2/MODEL1.csv --model 2
```

Enquanto os vetores reais não estiverem disponíveis, gere um payload sintético determinístico para validar infraestrutura e executar carga técnica (não use seus números como resultado científico):

```powershell
py -3 stresser+benchmarker/scripts/generate-payload.py --synthetic --model 2
```

Para reproduzir a preparação do front sem usar o Angular e comparar diretamente C++ e Elixir:

```powershell
py -3 scripts/compare_backends.py `
  --payload stresser+benchmarker/k6/payloads/dis-request.json `
  --output stresser+benchmarker/results/backend-parity.json
```

Com um vetor real, o script lê os valores, valida a dimensão e monta o mesmo JSON que o front:

```powershell
py -3 scripts/compare_backends.py --vector caminho/medicao.csv --model 2
```

Arquivos separados por `;` ou `,` são achatados, mas nunca completados ou interpolados. Assim um arquivo incompatível falha antes de alcançar os servidores.

Depois execute sempre a suíte C++/Elixir pelo trigger raiz:

```powershell
./run-benchmark.ps1 -Experiment smoke
./run-benchmark.ps1 -Experiment load -Rate 5 -Repetitions 5
./run-benchmark.ps1 -Experiment stress -Repetitions 3
```

```bash
./run-benchmark.sh smoke
./run-benchmark.sh load 5 5
./run-benchmark.sh stress "" 3
```

As execuções são sequenciais e alternam a ordem dos backends. Resultados independentes ficam em `stresser+benchmarker/results/`. O relatório consolidado é gerado ao final da suíte. Grafana e Prometheus já estão ativos antes do trigger.

## Testes

- O build C++ compila e executa `tests/regression.cpp`.
- O build Elixir executa `mix test`.
- O build do client executa a suíte Karma/Chrome headless, incluindo o teste de fan-out e detecção de divergência.
- `verify-docker.ps1` confirma health, igualdade dos limites Docker e igualdade lógica de uma reconstrução real.

Execute tudo com `docker compose -f compose.dis.yaml build` e depois `./verify-docker.ps1`. Para desligar: `docker compose -f compose.dis.yaml down`.

Para uma sessão autônoma de aproximadamente uma hora no WSL, com snapshots de relatório após cada etapa:

```bash
bash ./run-afk-hour.sh
```

Os logs, status por etapa e relatórios ficam em `stresser+benchmarker/results/afk-<data>/`.

Detalhes metodológicos e troubleshooting do laboratório ficam em `stresser+benchmarker/README.md` e `stresser+benchmarker/docs/`.
