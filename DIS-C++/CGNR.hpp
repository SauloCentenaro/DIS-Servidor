#pragma once

#include "util.hpp"

using namespace Eigen;
using namespace std;

class ConjugateGradienteNR
{
private:
  MatrixXd H;
  VectorXd g;

public:
  ConjugateGradienteNR(const MatrixXd &mat, const VectorXd &g);
  ~ConjugateGradienteNR();

  std::pair<Eigen::VectorXd, unsigned int> solve();
};


