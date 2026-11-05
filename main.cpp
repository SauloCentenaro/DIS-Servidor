#include "server.hpp"

int main()
{
  try
  {
    asio::io_context io_context;
    asio::thread_pool workers(1);
    Server server(io_context, 8080, workers);
    io_context.run();
  }
  catch (const std::exception &e)
  {
    std::cerr << "Exception: " << e.what() << std::endl;
    return 1;
  }

  return 0;
}
