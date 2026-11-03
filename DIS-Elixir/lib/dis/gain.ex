defmodule Dis.Gain do
  def apply(vector, model) do
    samples = if model, do: 794, else: 436

    if Nx.shape(vector) != {64 * samples},
      do: raise(ArgumentError, "Dimensões inválidas para ganho.")

    factors =
      for _channel <- 0..63,
          sample <- 0..(samples - 1),
          do: 100.0 + sample * :math.sqrt(sample) / 20.0

    Nx.multiply(vector, Nx.tensor(factors, type: :f64))
  end
end
