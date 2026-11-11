#pragma once
#include "session.hpp"

class Server
{
public:
  Server(asio::io_context &io_context, unsigned short port, asio::thread_pool &workers);

private:
  void accept();

private:
  asio::thread_pool &workers_;
  asio::ip::tcp::acceptor acceptor_;
  asio::ip::tcp::socket socket_;
};
