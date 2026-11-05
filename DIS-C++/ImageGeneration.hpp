#pragma once
#include <opencv2/opencv.hpp>
#include <Eigen/Dense>
#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <vector>

namespace ImageGeneration
{
  // Normalize absolute amplitude by its peak and preserve the original orientation.
  inline std::vector<unsigned short> ImgVector(const Eigen::VectorXd &f)
  {
    const int side = static_cast<int>(std::sqrt(f.size()));
    if ((side != 30 && side != 60) || side * side != f.size() || !f.allFinite())
      throw std::invalid_argument("Vetor de imagem invalido.");
    const double peak = f.cwiseAbs().maxCoeff();
    std::vector<unsigned short> pixels;
    pixels.reserve(f.size());
    for (int y = 0; y < side; ++y)
      for (int x = 0; x < side; ++x)
      {
        const double value = peak == 0 ? 0 : std::abs(f[x * side + y]) / peak * 255;
        pixels.push_back(static_cast<unsigned short>(std::lround(std::clamp(value, 0.0, 255.0))));
      }
    return pixels;
  }
  inline void makeImage(const Eigen::VectorXd &f, const std::string &filename)
  {
    const auto pixels = ImgVector(f);
    const int side = static_cast<int>(std::sqrt(pixels.size()));
    cv::Mat image(side, side, CV_8UC1);
    for (int y = 0; y < side; ++y)
      for (int x = 0; x < side; ++x)
        image.at<uchar>(y, x) = static_cast<uchar>(pixels[y * side + x]);
    if (!cv::imwrite("imagens/" + filename + ".png", image))
      throw std::runtime_error("Nao foi possivel salvar a imagem.");
  }
}
