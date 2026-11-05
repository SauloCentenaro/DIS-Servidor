#include "CGNR.hpp"
ConjugateGradienteNR::ConjugateGradienteNR(const MatrixXd &mat, const VectorXd &g) : H(mat), g(g) {}
ConjugateGradienteNR::~ConjugateGradienteNR() {}
std::pair<Eigen::VectorXd, unsigned int> ConjugateGradienteNR::solve()
{
  if (H.rows() != g.size() || !H.allFinite() || !g.allFinite())
    throw std::invalid_argument("Matriz ou vetor invalido.");
  VectorXd f = VectorXd::Zero(H.cols()), r = g;
  VectorXd z = H.transpose() * r, p = z;
  const double initial = z.norm();
  if (initial == 0) return {f, 0};
  unsigned int iterations = 0;
  while (iterations < 20)
  {
    VectorXd w = H * p;
    const double denominator = w.squaredNorm(), numerator = z.squaredNorm();
    if (!std::isfinite(denominator) || !std::isfinite(numerator) || denominator <= 0 || numerator <= 0)
      throw std::runtime_error("Falha numerica no CGNR.");
    const double alpha = numerator / denominator;
    f += alpha * p;
    r -= alpha * w;
    ++iterations;
    if (!f.allFinite() || !r.allFinite()) throw std::runtime_error("Resultado nao finito no CGNR.");
    z = H.transpose() * r;
    if (z.norm() <= Tolerance * initial) break;
    p = z + (z.squaredNorm() / numerator) * p;
  }
  return {f, iterations};
}
