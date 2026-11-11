# Métricas

O k6 fornece `http_reqs`, fases de `http_req_duration` (`waiting`, `connecting`, `sending`, `receiving`, `blocked`), `http_req_failed`, `iterations`, `iteration_duration`, `dropped_iterations`, `data_sent`, `data_received` e `checks`. `successful_requests` e `functional_failures` contam o resultado da validação. A latência primária é medida pelo cliente k6, nunca pelo tempo declarado pela aplicação.

O cAdvisor é consultado para CPU total/user/system (segundos acumulados transformados em cores), throttling, usage/working set/cache/pico/limite/falhas de memória/OOM, rede RX/TX, block I/O, processos, threads e uptime. Algumas séries não existem em todos os kernels, cgroups ou Docker Desktop; o exportador preserva arrays vazios em vez de inventar zero.

`container-metrics.json` preserva séries e labels; o CSV normaliza timestamp, nome, valor e labels. Totais de rede e disco no resumo são integrais aproximadas das taxas amostradas. `memory_first_to_last_delta_bytes` é indicador simples de estabilidade. `successful_requests_per_cpu_second` mede eficiência; `throughput_per_allocated_cpu` só existe quando o runtime informa um limite de CPU.

O Prometheus usa scrape de 1 s por padrão. Janelas muito curtas e `rate(...[10s])` têm efeito de borda; mantenha warmup fora da janela e testes suficientemente longos. O `run_id` existe nas métricas k6 via remote write. Métricas cAdvisor não recebem esse label; são correlacionadas pelos timestamps exatos e nome do container.
