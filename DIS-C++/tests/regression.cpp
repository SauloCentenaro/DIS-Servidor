#include "CGNR.hpp"
#include "CGNE.hpp"
#include "ImageGeneration.hpp"
#include "Gain.hpp"
#include <cassert>
#include <cfenv>
#include <iostream>

int main() {
  MatrixXd h = MatrixXd::Identity(3, 3);
  VectorXd zero = VectorXd::Zero(3);
  std::feclearexcept(FE_ALL_EXCEPT);
  auto nr = ConjugateGradienteNR(h, zero).solve();
  auto ne = ConjugateGradientNE(h, zero).solve();
  assert(nr.second == 0 && ne.second == 0);
  assert(nr.first.isZero() && ne.first.isZero());
  assert(!std::fetestexcept(FE_INVALID | FE_DIVBYZERO));

  h.diagonal() << 1, 2, 3;
  VectorXd expected(3); expected << 2, -3, 4;
  VectorXd g = h * expected;
  nr = ConjugateGradienteNR(h, g).solve();
  ne = ConjugateGradientNE(h, g).solve();
  assert(nr.first.isApprox(expected, 1e-4) && nr.second <= 20);
  assert(ne.first.isApprox(expected, 1e-4) && ne.second <= 100);
  MatrixXd hard = MatrixXd::Zero(200, 200);
  for (int i = 0; i < 200; ++i) hard(i, i) = i + 1;
  VectorXd rhs = VectorXd::Ones(200);
  assert(ConjugateGradienteNR(hard, rhs).solve().second == 20);
  assert(ConjugateGradientNE(hard, rhs).solve().second <= 100);
  MatrixXd singular = MatrixXd::Zero(3, 3);
  assert(ConjugateGradienteNR(singular, g).solve().first.isZero());
  bool rejected = false;
  try { ConjugateGradientNE(singular, g).solve(); }
  catch (const std::runtime_error &) { rejected = true; }
  assert(rejected);

  for (int size : {900, 3600}) {
    VectorXd f = VectorXd::Zero(size);
    auto pixels = ImageGeneration::ImgVector(f);
    assert(std::all_of(pixels.begin(), pixels.end(), [](auto p) { return p == 0; }));
    f[1] = -1000; f[2] = 500;
    pixels = ImageGeneration::ImgVector(f);
    assert(*std::max_element(pixels.begin(), pixels.end()) == 255);
    ImageGeneration::makeImage(f, "regression");
    cv::Mat png = cv::imread("imagens/regression.png", cv::IMREAD_GRAYSCALE);
    for (int i = 0; i < size; ++i) assert(png.data[i] == pixels[i]);
  }
  for (bool model : {false, true}) {
    int samples = model ? 794 : 436;
    VectorXd v = VectorXd::Ones(samples * 64);
    applyGain(v, model);
    for (int c = 0; c < 64; ++c)
      for (int s = 0; s < samples; ++s)
        assert(std::abs(v[c * samples + s] - (100 + s * std::sqrt(double(s)) / 20)) < 1e-10);
  }
  std::cout << "PASS: zero, known solutions, singular systems, iteration limits, PNG parity, gain for both models\n";
}
