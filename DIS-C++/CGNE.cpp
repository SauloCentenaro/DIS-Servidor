#include "CGNE.hpp"
ConjugateGradientNE::ConjugateGradientNE(const MatrixXd &H, const VectorXd &g) : H(H), g(g) {}
std::pair<VectorXd, int> ConjugateGradientNE::solve()
{
  if (H.rows() != g.size() || !H.allFinite() || !g.allFinite())
    throw std::invalid_argument("Matriz ou vetor invalido.");
  VectorXd f = VectorXd::Zero(H.cols()), r = g;
  VectorXd p = H.transpose() * r;
  const double initial = r.norm();
  if (initial == 0) return {f, 0};
  int iterations = 0;
  while (iterations < 100)
  {
    const double numerator = r.squaredNorm(), denominator = p.squaredNorm();
    if (!std::isfinite(numerator) || !std::isfinite(denominator) || numerator <= 0 || denominator <= 0)
      throw std::runtime_error("Falha numerica no CGNE: sistema singular ou incompativel.");
    const double alpha = numerator / denominator;
    f += alpha * p;
    r -= alpha * (H * p);
    ++iterations;
    if (!f.allFinite() || !r.allFinite()) throw std::runtime_error("Resultado nao finito no CGNE.");
    if (r.norm() <= Tolerance * initial) break;
    p = H.transpose() * r + (r.squaredNorm() / numerator) * p;
  }
  return {f, iterations};
}
