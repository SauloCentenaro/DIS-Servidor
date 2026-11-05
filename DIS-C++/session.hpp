#pragma once
#include "util.hpp"
#include "ImageGeneration.hpp"
class Session : public std::enable_shared_from_this<Session>
{
public:
  Session(asio::ip::tcp::socket &&socket, asio::thread_pool &workers);
  void start();
private:
  void processRequest();
  void writeResponse();
  asio::streambuf buffer_;
  asio::ip::tcp::socket stream_;
  asio::thread_pool &workers_;
  http::request<http::string_body> request_;
  http::response<http::string_body> response_;
};
