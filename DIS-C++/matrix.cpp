#include "matrix.hpp"

ModlMat::ModlMat()
{
  matRef = new MatrixXd;
}

ModlMat::~ModlMat()
{
  delete matRef;
}

void ModlMat::loadMat(MatrixXd &mat, string path)
{
  ifstream file;
  file.open(path);
  if (!file.is_open())
  {
    cerr << file.is_open() << "Erro ao abrir o arquivo." << endl;
    return;
  }

  vector<vector<double>> data;
  string line, cell;

  while (getline(file, line))
  {
    stringstream lineStream(line);
    vector<double> row;

    while (getline(lineStream, cell, ','))
    {
      try
      {
        row.push_back(stod(cell));
      }
      catch (const invalid_argument &e)
      {
        cerr << "Erro ao converter para double: " << e.what() << endl;
        return;
      }
      catch (const out_of_range &e)
      {
        cerr << "Valor fora do alcance: " << e.what() << endl;
        return;
      }
    }

    data.push_back(row);
  }

  file.close();

  size_t cols = data.empty() ? 0 : data[0].size();
  for (const auto &row : data)
  {
    if (row.size() != cols)
    {
      cerr << "Número inconsistente de colunas." << endl;
      return;
    }
  }

  mat = MatrixXd::Zero(data.size(), cols);
  for (size_t i = 0; i < data.size(); ++i)
  {
    for (size_t j = 0; j < cols; ++j)
    {
      mat(i, j) = data[i][j];
    }
  }

  *matRef = mat;
}
