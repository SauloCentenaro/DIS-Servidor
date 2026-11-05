#pragma once

#include "util.hpp"


using namespace Eigen;
using namespace std;

class ConjugateGradientNE
{
private:
  MatrixXd H;
  VectorXd g;

public:
  ConjugateGradientNE(const MatrixXd &H, const VectorXd &g);

  std::pair<VectorXd, int> solve();
};