#pragma once
#include <Eigen/Dense>
#include <cmath>
#include <stdexcept>
inline void applyGain(Eigen::VectorXd &vector, bool model)
{
  const int channels = 64, samples = model ? 794 : 436;
  if (vector.size() != channels * samples)
    throw std::invalid_argument("Dimensoes invalidas para aplicar ganho.");
  // Each channel contains consecutive time samples.
  for (int channel = 0; channel < channels; ++channel)
    for (int sample = 0; sample < samples; ++sample)
      vector[channel * samples + sample] *= 100.0 + sample * std::sqrt(static_cast<double>(sample)) / 20.0;
}
