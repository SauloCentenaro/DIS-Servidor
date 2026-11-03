FROM elixir:1.18-otp-27-slim
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates && rm -rf /var/lib/apt/lists/*
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
CMD ["mix", "run", "--no-halt"]
