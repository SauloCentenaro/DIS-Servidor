#include "server.hpp"
#include <cstdlib>

namespace {
int positiveEnv(const char *name, int fallback, int maximum)
{
  const char *raw = std::getenv(name);
  if (!raw) return fallback;
  try {
    const int value = std::stoi(raw);
    if (value < 1 || value > maximum) throw std::out_of_range(name);
    return value;
  } catch (...) {
    throw std::invalid_argument(std::string("Variavel invalida: ") + name);
  }
}
}

int main()
{
  try
  {
    asio::io_context io_context;
    asio::thread_pool workers(positiveEnv("WORKER_THREADS", 1, 256));
    Server server(io_context, static_cast<unsigned short>(positiveEnv("PORT", 8080, 65535)), workers);
    io_context.run();
  }
  catch (const std::exception &e)
  {
    std::cerr << "Exception: " << e.what() << std::endl;
    return 1;
  }

  return 0;
}
