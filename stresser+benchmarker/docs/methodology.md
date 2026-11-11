# Metodologia

## Cenários

- **Smoke:** poucas iterações para verificar conectividade, payload e checks. Não serve para comparar desempenho.
- **Baseline:** um VU em modelo fechado para medir o comportamento sem pressão relevante e orientar thresholds.
- **Load:** taxa constante (modelo aberto) em patamares representativos.
- **Stress:** eleva progressivamente a taxa para observar saturação e recuperação.
- **Spike:** mudança abrupta de taxa para testar filas, autoscaling e recuperação.
- **Soak:** carga estável longa para revelar vazamentos, degradação e efeitos de GC/cache.
- **Breakpoint:** aumenta até violar thresholds ou atingir saturação. O maior RPS aprovado só é comparável sob a mesma matriz.
- **Cold start:** mede inicialização em execução separada. Não misture com testes aquecidos.

## Modelo aberto, fechado, VUs e RPS

`constant-vus` é fechado: cada VU só inicia a próxima iteração quando termina a anterior; a latência limita o RPS e pode esconder sobrecarga. Arrival rate é aberto: agenda requisições independentemente da resposta e representa melhor chegadas externas. VUs são concorrência, não taxa. `dropped_iterations` indica que k6 não conseguiu iniciar o trabalho agendado, normalmente por falta de VUs ou recursos do próprio gerador.

Throughput é trabalho concluído por unidade de tempo. A taxa solicitada não é a taxa obtida. Registre ambas, erros e descartes. Saturação aparece quando mais carga deixa de elevar throughput e aumenta fila/latência/erros ou throttling.

## Distribuições e repetição

Percentis descrevem caudas: p95 é o limite abaixo do qual ficam 95% das observações; não significa que cada janela terá exatamente 5% acima. Média isolada esconde multimodalidade e outliers. Preserve pontos brutos e reporte p50, p90, p95, p99 e máximo.

Warmup prepara JIT, caches, pools e conexões; seus dados não entram na janela medida. Cooldown permite observar recuperação e evita contaminar a execução seguinte. Repita várias vezes, apresente dispersão/intervalos e alterne a ordem dos alvos para reduzir viés térmico e temporal.

## Controle de variáveis

Use o mesmo host, limites de CPU/memória, payload, endpoint, dataset, validação, observabilidade, duração e política de cache. Execute somente um alvo por vez. Registre commits, imagens/digests, ambiente e relógios. Não otimize uma implementação de forma diferente. Checks funcionais são obrigatórios: HTTP 200 sozinho não prova resultado correto.

CPU em cores é derivada da taxa de segundos de CPU; 1,0 significa aproximadamente um core ocupado. Compare média, pico, throttling e CPU total por trabalho bem-sucedido. Memória deve separar usage, working set e cache; pico e tendência importam mais que uma fotografia. Crescimento entre início/fim é apenas um sinal, não prova vazamento.

Em uma só máquina, k6, alvo, Docker, Prometheus e Grafana disputam CPU, memória, rede e disco. No Docker Desktop disputam recursos dentro de uma VM. O arranjo recomendado separa o gerador (máquina A) do alvo e monitoramento (máquina B), com rede estável e sincronização de relógio.
