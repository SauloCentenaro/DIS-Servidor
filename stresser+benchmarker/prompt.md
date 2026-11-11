Quero criar neste repositório uma plataforma completa e reproduzível para benchmarking e testes de carga de aplicações HTTP executadas em containers Docker.

O repositório não deve conter a aplicação avaliada. Ele será responsável apenas por:

1. gerar carga HTTP;
2. coletar métricas dos containers avaliados;
3. armazenar os resultados de cada execução;
4. disponibilizar dashboards;
5. automatizar execuções repetidas;
6. permitir comparar diferentes implementações, como C++ e Elixir.

Implemente efetivamente todos os arquivos necessários. Não entregue apenas uma explicação ou um plano.

# Objetivo

A plataforma deve permitir testar diferentes aplicações usando exatamente os mesmos:

- payloads;
- endpoints;
- taxas de requisição;
- duração;
- aquecimento;
- limites de concorrência;
- critérios de sucesso;
- coleta de métricas;
- períodos de cooldown;
- formato de resultados.

Os endereços, portas, endpoints, payloads e parâmetros não podem ficar hardcoded nos scripts.

A plataforma deve funcionar prioritariamente em Linux com Docker Engine e Docker Compose. Também deve incluir instruções para uso no Windows com Docker Desktop e PowerShell, documentando limitações do cAdvisor no Docker Desktop.

# Stack desejada

Utilize:

- Docker Compose;
- Grafana k6 para geração de carga;
- cAdvisor para métricas dos containers;
- Prometheus para armazenamento das métricas;
- Grafana para visualização;
- scripts de automação em PowerShell e Bash;
- arquivos YAML ou JSON para configuração dos experimentos.

Fixe versões explícitas das imagens Docker. Não utilize tags `latest`.

# Arquitetura

A arquitetura deve ser aproximadamente:

    runner
       |
       +--> k6 --> aplicação alvo
       |
       +--> Prometheus API
                    ^
                    |
                cAdvisor
                    ^
                    |
             containers Docker

    Prometheus --> Grafana

A aplicação alvo pode estar:

1. publicada em uma porta do host;
2. em outro Docker Compose;
3. em uma Docker network externa;
4. em outra máquina.

O endereço deve ser configurável por uma URL completa, por exemplo:

    http://host.docker.internal:8080
    http://cpp-server:8080
    http://192.168.1.100:8080

No Linux, configure quando necessário:

    extra_hosts:
      - "host.docker.internal:host-gateway"

# Estrutura esperada

Crie uma organização semelhante a:

    .
    ├── compose.yaml
    ├── .env.example
    ├── Makefile
    ├── README.md
    ├── configs/
    │   ├── targets.example.yaml
    │   ├── experiments.example.yaml
    │   └── thresholds.example.yaml
    ├── k6/
    │   ├── lib/
    │   │   ├── request.js
    │   │   ├── validation.js
    │   │   └── configuration.js
    │   ├── scenarios/
    │   │   ├── smoke.js
    │   │   ├── baseline.js
    │   │   ├── load.js
    │   │   ├── stress.js
    │   │   ├── spike.js
    │   │   ├── soak.js
    │   │   └── breakpoint.js
    │   └── payloads/
    │       └── example.json
    ├── prometheus/
    │   ├── prometheus.yml
    │   └── rules.yml
    ├── grafana/
    │   ├── provisioning/
    │   │   ├── dashboards/
    │   │   └── datasources/
    │   └── dashboards/
    │       ├── containers.json
    │       └── benchmark.json
    ├── scripts/
    │   ├── run-experiment.sh
    │   ├── run-experiment.ps1
    │   ├── run-suite.sh
    │   ├── run-suite.ps1
    │   ├── collect-metrics.sh
    │   ├── collect-metrics.ps1
    │   ├── validate-environment.sh
    │   └── validate-environment.ps1
    ├── mock/
    │   └── aplicação HTTP mínima para validar o laboratório
    ├── results/
    │   └── .gitkeep
    └── docs/
        ├── methodology.md
        ├── metrics.md
        └── troubleshooting.md

A estrutura pode ser ajustada se houver uma justificativa técnica clara.

# Parametrização dos alvos

Crie um arquivo de configuração com múltiplos alvos, semelhante a:

    targets:
      cpp:
        base_url: "http://host.docker.internal:8080"
        endpoint: "/reconstruct"
        method: "POST"
        container_name: "dis-cpp"
        health_endpoint: "/health"
        expected_status: 200

      elixir:
        base_url: "http://host.docker.internal:8081"
        endpoint: "/reconstruct"
        method: "POST"
        container_name: "dis-elixir"
        health_endpoint: "/health"
        expected_status: 200

O campo `container_name` será utilizado para filtrar métricas do cAdvisor.

O health check deve ser opcional. Caso não exista, o runner deve conseguir validar o alvo por meio de uma requisição configurável ao endpoint principal.

Permita configurar:

- nome lógico do alvo;
- URL base;
- endpoint;
- método HTTP;
- headers;
- arquivo de payload;
- nome ou ID do container;
- status HTTP esperado;
- timeout;
- endpoint de saúde;
- campos obrigatórios na resposta;
- tamanho mínimo da resposta;
- tags adicionais;
- TLS inseguro, desabilitado por padrão.

Segredos não devem ser versionados.

# Configuração dos experimentos

Crie um formato declarativo para os testes:

    experiments:
      smoke:
        executor: "shared-iterations"
        vus: 1
        iterations: 10
        warmup: "10s"
        cooldown: "10s"

      baseline:
        executor: "constant-vus"
        vus: 1
        duration: "3m"
        warmup: "30s"
        cooldown: "30s"

      load:
        executor: "constant-arrival-rate"
        rates: [1, 2, 5, 10, 20]
        time_unit: "1s"
        duration: "5m"
        preallocated_vus: 30
        max_vus: 200
        warmup: "1m"
        cooldown: "1m"

      stress:
        executor: "ramping-arrival-rate"
        stages:
          - target: 1
            duration: "1m"
          - target: 5
            duration: "2m"
          - target: 10
            duration: "2m"
          - target: 20
            duration: "2m"
          - target: 40
            duration: "2m"
          - target: 0
            duration: "1m"

      spike:
        executor: "ramping-arrival-rate"
        stages:
          - target: 2
            duration: "1m"
          - target: 40
            duration: "10s"
          - target: 40
            duration: "1m"
          - target: 2
            duration: "10s"
          - target: 2
            duration: "1m"

      soak:
        executor: "constant-arrival-rate"
        rate: 5
        time_unit: "1s"
        duration: "1h"

      breakpoint:
        executor: "ramping-arrival-rate"
        start_rate: 1
        stages:
          - target: 5
            duration: "2m"
          - target: 10
            duration: "2m"
          - target: 20
            duration: "2m"
          - target: 40
            duration: "2m"
          - target: 80
            duration: "2m"

Todos os valores devem ser sobrescrevíveis por linha de comando ou variáveis de ambiente.

# Testes k6

Implemente scripts reutilizáveis, evitando duplicação entre os cenários.

Os scripts devem coletar pelo menos:

- `http_reqs`;
- `http_req_duration`;
- `http_req_waiting`;
- `http_req_connecting`;
- `http_req_sending`;
- `http_req_receiving`;
- `http_req_blocked`;
- `http_req_failed`;
- `iterations`;
- `iteration_duration`;
- `dropped_iterations`;
- bytes recebidos;
- bytes enviados;
- checks funcionais;
- RPS obtido.

Adicione tags como:

- target;
- implementation;
- experiment;
- scenario;
- run_id;
- model;
- payload;
- rate;
- repetition.

Implemente checks configuráveis para:

- status HTTP esperado;
- corpo não vazio;
- JSON válido;
- presença de campos;
- tamanho esperado de arrays;
- tempo máximo opcional;
- validações específicas definidas na configuração.

Não faça parse completo de respostas grandes em todos os testes caso isso sobrecarregue o gerador de carga. Permita separar:

1. validação funcional completa;
2. validação leve durante carga.

O k6 deve produzir:

- resumo legível no terminal;
- `summary.json`;
- resultado granular compactado, como `metrics.json.gz`;
- metadados da execução;
- código de saída diferente de zero quando thresholds falharem.

# Thresholds

Permita configurar critérios como:

    thresholds:
      http_req_failed:
        - "rate<0.01"
      checks:
        - "rate>0.99"
      http_req_duration:
        - "p(95)<1000"
        - "p(99)<2000"
      dropped_iterations:
        - "count==0"

Não presuma inicialmente que esses limites são adequados ao sistema. Documente que devem ser definidos depois da execução baseline.

# Métricas dos containers

Configure cAdvisor e Prometheus para coletar:

- CPU total;
- CPU em user mode;
- CPU em system mode;
- throttling de CPU;
- memória atual;
- working set;
- cache;
- pico de memória, quando disponível;
- limite de memória;
- falhas de memória;
- OOM;
- rede recebida e enviada;
- block I/O;
- quantidade de processos e threads, quando disponível;
- reinicializações;
- tempo de atividade.

O Prometheus deve coletar com intervalo pequeno e configurável, usando como padrão 1 ou 2 segundos.

As consultas e dashboards devem permitir filtrar por:

- nome do container;
- target;
- intervalo da execução;
- run ID, quando tecnicamente possível.

O runner deve registrar os timestamps exatos de início e fim para consultar posteriormente no Prometheus.

Depois de cada execução, exporte as métricas relevantes para dentro do diretório do resultado, preferencialmente em JSON e CSV. Os resultados não podem depender exclusivamente da retenção do Prometheus.

# Resultados

Cada execução deve criar uma pasta imutável:

    results/<data>-<run_id>-<target>-<experiment>/

Ela deve conter pelo menos:

    metadata.json
    effective-config.yaml
    k6-summary.json
    k6-metrics.json.gz
    container-metrics.json
    container-metrics.csv
    prometheus-queries.json
    target-inspect.json
    target-logs.txt
    environment.json
    checks.json
    README.txt

O `metadata.json` deve registrar:

- run ID;
- target;
- implementação;
- experimento;
- repetição;
- endpoint;
- taxa desejada;
- taxa efetivamente alcançada;
- início e fim;
- duração;
- warmup;
- cooldown;
- commit da plataforma de benchmark;
- commit da aplicação, se informado;
- imagem Docker;
- digest da imagem, se disponível;
- nome e ID do container;
- limites de CPU e memória;
- número de CPUs do host;
- memória do host;
- sistema operacional;
- versão do Docker;
- versão do Docker Compose;
- versão do k6;
- versões de Prometheus, Grafana e cAdvisor;
- arquivo e hash do payload;
- arquivo e hash das matrizes ou dataset, quando informados;
- parâmetros customizados.

Não registre tokens ou headers secretos.

# Métricas derivadas

Gere um resumo comparável contendo:

- média, p50, p90, p95, p99 e máximo da latência;
- throughput médio;
- requisições concluídas;
- requisições bem-sucedidas;
- taxa de erro;
- iterações descartadas;
- CPU média;
- CPU máxima;
- segundos totais de CPU;
- memória média;
- pico de memória;
- rede transmitida e recebida;
- block I/O;
- requisições bem-sucedidas por segundo de CPU;
- throughput por CPU alocada;
- maior RPS que respeitou os thresholds;
- estabilidade da memória ao longo do teste.

Crie um script que consolide diversas repetições em CSV e JSON para futura análise estatística.

Não tente esconder variabilidade usando apenas médias. Preserve os dados brutos.

# Execução de suítes

Implemente um runner capaz de executar algo como:

    ./scripts/run-experiment.sh \
      --target cpp \
      --experiment load \
      --rate 5 \
      --payload k6/payloads/h2-sem-ganho.json \
      --repetition 1

E no PowerShell:

    ./scripts/run-experiment.ps1 `
      -Target cpp `
      -Experiment load `
      -Rate 5 `
      -Payload k6/payloads/h2-sem-ganho.json `
      -Repetition 1

Implemente também uma suíte:

    ./scripts/run-suite.sh \
      --targets cpp,elixir \
      --experiments smoke,baseline,load,stress \
      --repetitions 5

A suíte deve:

1. validar o ambiente;
2. verificar se Prometheus, cAdvisor e Grafana estão saudáveis;
3. verificar se o alvo responde;
4. registrar as informações do container;
5. aguardar estabilização;
6. executar warmup;
7. aguardar um pequeno intervalo;
8. executar o teste medido;
9. aguardar cooldown;
10. exportar métricas;
11. capturar logs;
12. gerar o resumo;
13. continuar para a próxima repetição;
14. produzir um relatório consolidado.

Permita alternar ou randomizar a ordem dos targets para reduzir viés térmico e temporal.

Não execute C++ e Elixir simultaneamente por padrão. A execução padrão deve ser sequencial.

Se uma execução falhar, preserve os resultados parciais e registre claramente o motivo.

# Isolamento e justiça experimental

Documente e aplique, quando possível, estas regras:

- somente um alvo deve ser testado por vez;
- todos os alvos devem receber os mesmos limites de CPU e memória;
- os mesmos payloads devem ser usados;
- os mesmos tempos de warmup e cooldown devem ser usados;
- os mesmos endpoints e regras funcionais devem ser usados;
- o host não deve executar tarefas desnecessárias durante os testes;
- o gerador de carga não deve ficar dentro do container avaliado;
- o container do k6 não deve ser incluído nas métricas do alvo;
- aplicações devem ser reiniciadas entre execuções quando configurado;
- caches devem ser tratados de forma idêntica;
- testes de cold start devem ficar separados dos testes aquecidos;
- coleta de observabilidade deve ser idêntica entre implementações;
- o horário e duração de cada execução devem ser registrados;
- os testes devem ser repetidos várias vezes;
- a ordem das implementações deve ser alternada.

Não altere automaticamente limites de CPU ou memória dos containers alvos sem autorização explícita. O runner pode validar e registrar os limites existentes.

Documente que o cenário ideal usa duas máquinas:

    máquina A: k6
    máquina B: aplicação, cAdvisor e Prometheus

Também ofereça um modo local para desenvolvimento, deixando claro que k6 e o alvo disputarão recursos do mesmo host ou da mesma VM do Docker Desktop.

# Aplicação mock

Crie uma aplicação HTTP mínima e leve, habilitada por um profile do Docker Compose, apenas para validar o laboratório.

Ela deve ter:

- `GET /health`;
- `POST /reconstruct`;
- resposta JSON previsível;
- opção de adicionar atraso artificial;
- opção de simular erros.

Ela não deve ser usada como parte real do benchmark. Serve apenas para provar que scripts, dashboards, coleta e exportação funcionam.

# Grafana

Provisione automaticamente:

- datasource do Prometheus;
- dashboard de containers;
- dashboard de benchmark.

O dashboard de containers deve mostrar:

- CPU;
- memória;
- working set;
- rede;
- disco;
- throttling;
- processos;
- reinicializações.

O dashboard de benchmark deve mostrar:

- RPS;
- latência p50, p90, p95 e p99;
- taxa de erros;
- checks;
- iterações descartadas;
- CPU versus throughput;
- memória versus throughput;
- comparação entre targets.

Evite configuração manual depois de `docker compose up`.

# Comandos esperados

Forneça comandos simples, por exemplo:

    make up
    make down
    make validate
    make smoke TARGET=cpp
    make load TARGET=cpp RATE=5
    make suite
    make report

Ofereça alternativas equivalentes para PowerShell quando `make` não estiver disponível.

# Segurança

O cAdvisor pode exigir mounts e permissões elevadas. Documente claramente:

- quais diretórios são montados;
- por que são necessários;
- que o ambiente é destinado a laboratório local;
- que Grafana, Prometheus e cAdvisor não devem ser expostos publicamente;
- como alterar credenciais do Grafana;
- como restringir as portas ao localhost.

Não versionar segredos.

# Documentação

O `README.md` deve explicar:

1. arquitetura;
2. pré-requisitos;
3. início rápido;
4. configuração dos targets;
5. criação de payloads;
6. execução de cada cenário;
7. execução da suíte;
8. leitura dos resultados;
9. acesso ao Grafana;
10. coleta pelo Prometheus;
11. execução local versus máquina separada;
12. uso no Linux;
13. uso no Windows com Docker Desktop;
14. problemas comuns;
15. como adicionar um novo target;
16. como adicionar um novo cenário;
17. como reproduzir uma execução antiga.

Crie também `docs/methodology.md` explicando:

- smoke;
- baseline;
- load;
- stress;
- spike;
- soak;
- breakpoint;
- cold start;
- modelo aberto versus modelo fechado;
- RPS versus VUs;
- percentis;
- throughput;
- saturação;
- warmup;
- cooldown;
- repetição;
- controle de variáveis;
- interpretação de CPU e memória;
- limitações de benchmarks feitos em uma única máquina.

# Qualidade

Antes de concluir:

1. valide o YAML do Docker Compose;
2. valide os arquivos de configuração;
3. execute linters disponíveis;
4. suba a stack;
5. execute um smoke test contra a aplicação mock;
6. confirme que o Prometheus coleta o cAdvisor;
7. confirme que o Grafana recebe o datasource;
8. confirme que uma pasta de resultado é criada;
9. confirme que os resultados contêm métricas do k6 e do container;
10. desligue a stack;
11. informe exatamente o que foi validado.

Se alguma validação não puder ser feita no ambiente atual, explique o bloqueio e deixe os comandos exatos para executá-la.

# Restrições de implementação

- Não use valores importantes hardcoded.
- Não dependa de serviços pagos ou SaaS.
- Não dependa de configuração manual no Grafana.
- Não misture métricas de warmup com a janela principal do teste.
- Não apague resultados antigos automaticamente.
- Não sobrescreva uma execução anterior.
- Não descarte dados brutos.
- Não use apenas médias para comparar desempenho.
- Não execute alvos concorrentes por padrão.
- Não considere uma resposta HTTP 200 como sucesso sem executar os checks configurados.
- Não use o tempo informado pela aplicação como métrica principal de latência; use a medição do cliente k6.
- Não faça otimizações diferentes para cada implementação.
- Mantenha os scripts legíveis, modulares e documentados.

# Critérios de aceite

O trabalho estará concluído quando for possível:

1. executar `docker compose up -d`;
2. acessar Grafana e Prometheus;
3. executar um smoke test contra o mock;
4. cadastrar dois alvos externos apenas alterando um YAML;
5. executar a mesma suíte contra os dois alvos;
6. alterar endpoint, porta, payload, taxa e duração sem editar os scripts;
7. encontrar uma pasta independente para cada execução;
8. consultar latência, RPS, erros, CPU, memória, rede e disco;
9. exportar essas métricas para JSON e CSV;
10. consolidar múltiplas repetições;
11. reproduzir uma execução usando a configuração efetiva armazenada;
12. identificar claramente falhas, thresholds violados e iterações descartadas.

Comece inspecionando o repositório vazio, apresente resumidamente a arquitetura escolhida e então implemente todos os arquivos. Tome decisões razoáveis sem interromper o trabalho para perguntas que possam ser resolvidas com valores padrão parametrizáveis.