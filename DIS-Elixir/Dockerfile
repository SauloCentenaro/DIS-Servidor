FROM elixir:1.18-otp-27-slim
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates curl && rm -rf /var/lib/apt/lists/*
ENV ERL_FLAGS="+S 4:4" XLA_TARGET=cpu
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
COPY mix.* ./
RUN mix deps.get
RUN mix deps.compile
COPY . .
RUN mix compile
RUN mix test
EXPOSE 8081
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=5 CMD curl --fail --silent http://127.0.0.1:8081/health > /dev/null || exit 1
CMD ["mix", "run", "--no-halt"]
