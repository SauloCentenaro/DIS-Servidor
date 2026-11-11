# Troubleshooting

1. Execute `docker compose config --quiet` e `python scripts/benchmark.py validate`.
2. Veja `docker compose ps` e `docker compose logs prometheus cadvisor grafana`.
3. Em `http://localhost:9090/targets`, confirme `cadvisor` como UP.
4. Consulte `container_last_seen` e confira o label `name` usado em `container_name`.
5. Teste a URL do target de dentro do namespace do k6 com uma execução smoke; `localhost` dentro do k6 não é o host.

No Linux, falta de `/dev/kmsg`, cgroups não montados ou Docker com rootless mode pode reduzir a coleta. Ajuste mounts apenas entendendo o impacto de segurança. Em Docker Desktop/WSL2, caminhos e séries disponíveis dependem do backend e da versão. Se cAdvisor não enxergar containers individuais, rode o laboratório em Docker Engine Linux; não trate métricas da VM como se fossem do alvo.

Se a execução falhar, leia `metadata.json.failure_reason`, `checks.json`, `target-logs.txt` e o resumo k6. Resultados parciais nunca são removidos. Se o Prometheus ficou indisponível apenas durante a exportação, restaure-o e rode `scripts/collect-metrics.*` antes de expirar a retenção.
