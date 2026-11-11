#include "matrix.hpp"
#include <cmath>

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
  ifstream file(path);
  if (!file.is_open())
    throw runtime_error("Nao foi possivel abrir a matriz: " + path);

  vector<vector<double>> data;
  string line, cell;
  size_t expectedColumns = 0;

  while (getline(file, line))
  {
    stringstream lineStream(line);
    vector<double> row;
    while (getline(lineStream, cell, ','))
    {
      try
      {
        size_t consumed = 0;
        const double value = stod(cell, &consumed);
        if (consumed != cell.size() || !std::isfinite(value))
          throw invalid_argument("Matriz contem valor invalido.");
        row.push_back(value);
      }
      catch (const invalid_argument &)
      {
        throw invalid_argument("Matriz contem valor invalido.");
      }
      catch (const out_of_range &)
      {
        throw invalid_argument("Matriz contem valor fora do alcance.");
      }
    }
    if (row.empty()) throw invalid_argument("Matriz contem linha vazia.");
    if (expectedColumns == 0) expectedColumns = row.size();
    if (row.size() != expectedColumns)
      throw invalid_argument("Matriz com linhas de tamanhos diferentes.");
    data.push_back(std::move(row));
  }

  if (data.empty()) throw invalid_argument("Matriz vazia.");
  mat = MatrixXd::Zero(data.size(), expectedColumns);
  for (size_t row = 0; row < data.size(); ++row)
    for (size_t column = 0; column < expectedColumns; ++column)
      mat(row, column) = data[row][column];
  *matRef = mat;
}
