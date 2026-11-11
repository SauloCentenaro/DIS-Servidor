FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends g++ pkg-config libboost-dev libeigen3-dev libopencv-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY . .
RUN g++ -std=c++17 -O2 -pthread -I/usr/include/eigen3 main.cpp server.cpp session.cpp matrix.cpp CGNR.cpp CGNE.cpp $(pkg-config --cflags --libs opencv4) -o dis-servidor
RUN mkdir -p imagens && g++ -std=c++17 -O2 -pthread -I. -I/usr/include/eigen3 tests/regression.cpp CGNR.cpp CGNE.cpp $(pkg-config --cflags --libs opencv4) -o regression && ./regression
FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends libopencv-imgcodecs406 curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/dis-servidor ./dis-servidor
RUN mkdir -p imagens utils/MatrizesRef
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD curl --fail --silent http://127.0.0.1:8080/health || exit 1
CMD ["./dis-servidor"]
