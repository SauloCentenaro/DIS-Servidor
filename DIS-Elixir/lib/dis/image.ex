defmodule Dis.Image do
  def pixels(f) do
    size = Nx.size(f)
    side = trunc(:math.sqrt(size))

    if side not in [30, 60] or side * side != size,
      do: raise(ArgumentError, "Dimensões de imagem inválidas.")

    Dis.Solver.finite!(f)
    absolute = Nx.abs(f)
    peak = absolute |> Nx.reduce_max() |> Nx.to_number()
    scale = if peak == 0, do: 1.0, else: peak

    absolute
    |> Nx.divide(scale)
    |> Nx.multiply(255)
    |> Nx.clip(0, 255)
    |> Nx.round()
    |> Nx.reshape({side, side})
    |> Nx.transpose()
    |> Nx.as_type(:u8)
    |> Nx.to_flat_list()
  end

  def png(pixels) do
    side = trunc(:math.sqrt(length(pixels)))

    if side not in [30, 60] or side * side != length(pixels),
      do: raise(ArgumentError, "Imagem inválida.")

    raw =
      pixels
      |> Enum.chunk_every(side)
      |> Enum.map(fn row -> [0 | row] end)
      |> IO.iodata_to_binary()

    header = <<side::32, side::32, 8, 0, 0, 0, 0>>

    <<137, 80, 78, 71, 13, 10, 26, 10>> <>
      chunk("IHDR", header) <> chunk("IDAT", :zlib.compress(raw)) <> chunk("IEND", "")
  end

  defp chunk(type, data),
    do: <<byte_size(data)::32>> <> type <> data <> <<:erlang.crc32(type <> data)::32>>
end
