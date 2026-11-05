#include "session.hpp"
#include "Gain.hpp"
Session::Session(asio::ip::tcp::socket &&socket, asio::thread_pool &workers)
    : stream_(std::move(socket)), workers_(workers) {}
void Session::start()
{
  auto self = shared_from_this();
  http::async_read(stream_, buffer_, request_, [self](boost::system::error_code ec, std::size_t) {
    if (ec) return;
    if (self->request_.method() == http::verb::post && self->request_.target() == "/")
      asio::post(self->workers_, [self] { self->processRequest(); });
    else self->processRequest();
  });
}
void Session::processRequest()
{
  response_.version(request_.version());
  response_.keep_alive(false);
  response_.set(http::field::access_control_allow_origin, "*");
  response_.set(http::field::access_control_allow_methods, "GET, POST, OPTIONS");
  response_.set(http::field::access_control_allow_headers, "content-type");
  response_.set(http::field::content_type, "application/json");
  response_.result(http::status::ok);
  if (request_.method() == http::verb::options)
    response_.result(http::status::no_content);
  else if (request_.method() == http::verb::get && request_.target() == "/health")
    response_.body() = "{\"status\":\"ok\"}";
  else if (request_.method() != http::verb::post || request_.target() != "/")
  {
    response_.result(http::status::not_found);
    response_.body() = "{\"error\":\"Endpoint inexistente.\"}";
  }
  else
  {
    const auto start = std::chrono::system_clock::now();
    const auto tick = std::chrono::steady_clock::now();
    try
    {
      const auto j = nlohmann::json::parse(request_.body());
      if (!j.at("model").is_boolean() || !j.at("ganho").is_boolean() || !j.at("user").is_number_integer())
        throw std::invalid_argument("Modelo, ganho ou usuario invalido.");
      const bool model = j.at("model").get<bool>(), gain = j.at("ganho").get<bool>();
      const int user = j.at("user").get<int>();
      const auto values = j.at("vector").get<std::vector<std::string>>();
      if (values.empty()) throw std::invalid_argument("Vetor vazio.");
      Eigen::VectorXd vector(values.size());
      for (size_t i = 0; i < values.size(); ++i)
      {
        size_t consumed = 0;
        const double value = std::stod(values[i], &consumed);
        if (consumed != values[i].size() || !std::isfinite(value))
          throw std::invalid_argument("Vetor contem valor invalido.");
        vector[i] = value;
      }
      ModlMat matrix;
      matrix.loadMat(*matrix.getMat(), model ? "utils/MatrizesRef/H-1.csv" : "utils/MatrizesRef/H-2.csv");
      if (matrix.getMat()->rows() != vector.size() || (matrix.getMat()->cols() != 900 && matrix.getMat()->cols() != 3600))
        throw std::invalid_argument("Dimensoes da matriz e do vetor incompativeis.");
      if (gain) applyGain(vector, model);
      auto [f, iterations] = ConjugateGradienteNR(*matrix.getMat(), vector).solve();
      ImageGeneration::makeImage(f, std::to_string(user));
      const double duration = std::chrono::duration<double>(std::chrono::steady_clock::now() - tick).count();
      const double startTime = std::chrono::duration<double>(start.time_since_epoch()).count();
      response_.body() = nlohmann::json({
          {"imageVector", ImageGeneration::ImgVector(f)}, {"user", user}, {"iteracoes", iterations},
          {"startTime", startTime}, {"endTime", startTime + duration}, {"durationSeconds", duration}}).dump();
    }
    catch (const nlohmann::json::exception &e)
    {
      response_.result(http::status::bad_request);
      response_.body() = nlohmann::json({{"error", e.what()}}).dump();
    }
    catch (const std::logic_error &e)
    {
      response_.result(http::status::bad_request);
      response_.body() = nlohmann::json({{"error", e.what()}}).dump();
    }
    catch (const std::exception &e)
    {
      response_.result(http::status::internal_server_error);
      response_.body() = nlohmann::json({{"error", e.what()}}).dump();
    }
  }
  response_.prepare_payload();
  auto self = shared_from_this();
  asio::post(stream_.get_executor(), [self] { self->writeResponse(); });
}
void Session::writeResponse()
{
  auto self = shared_from_this();
  http::async_write(stream_, response_, [self](boost::system::error_code, std::size_t) {
    boost::system::error_code ignored;
    self->stream_.shutdown(asio::ip::tcp::socket::shutdown_send, ignored);
  });
}
