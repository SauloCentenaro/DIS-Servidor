#pragma once
#include <fstream>
#include <sstream>
#include "util.hpp"

using namespace Eigen;
using namespace std;

class ModlMat
{
private:
  MatrixXd *matRef;

public:
  void loadMat(MatrixXd &mat, string path);

  MatrixXd *getMat()
  {
    return matRef;
  };

  void printMat()
  {
    cout << "carregada" << endl;
    // cout << *matRef << endl;
  }

  MatrixXd getMatT()
  {
    return matRef->transpose();
  }

  ModlMat();

  ~ModlMat();
};
