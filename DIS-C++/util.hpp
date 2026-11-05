#pragma once
#include <iostream>
#include <Eigen/Dense>
#include <mutex>
#include <chrono>
#include <ctime>
#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
#include <pdh.h>
#endif
#include <queue>
#include "CGNE.hpp"
#include "CGNR.hpp"
#include "matrix.hpp"
#include "json.hpp"
#define BOOST_ASIO_DISABLE_IOCP

#include <boost/asio.hpp>
#include <boost/beast.hpp>
#include <boost/beast/http.hpp>
#include <boost/asio/coroutine.hpp>

namespace asio = boost::asio;
namespace http = boost::beast::http;
#define path_modlMat_1 "C:/Users/saulo/Desktop/Des_Integrado/utils/MatrizesRef/H-1.csv"
#define path_modlMat_2 "C:/Users/saulo/Desktop/Des_Integrado/utils/MatrizesRef/H-2.csv"

#define Tolerance 1e-4
