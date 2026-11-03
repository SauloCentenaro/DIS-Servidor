defmodule Dis.Matrix do
  import Nx.Defn

  def load_blocks!(path, block_rows \\ 128) when is_integer(block_rows) and block_rows > 0 do
    {rows, cols, blocks} =
      path
      |> File.stream!()
      |> Stream.chunk_every(block_rows)
      |> Enum.reduce({0, nil, []}, fn lines, {offset, expected_cols, blocks} ->
        {chunks, cols} =
          Enum.map_reduce(lines, expected_cols, fn line, cols ->
            cells = line |> String.trim() |> String.split(",")
            width = length(cells)

            if cols != nil and cols != width,
              do: raise(ArgumentError, "Matriz com linhas de tamanhos diferentes.")

            binary =
              for cell <- cells, into: <<>>, do: <<Dis.Input.number!(cell)::float-native-64>>

            {binary, width}
          end)

        tensor =
          chunks
          |> IO.iodata_to_binary()
          |> Nx.from_binary(:f64)
          |> Nx.reshape({length(lines), cols})

        Dis.Solver.finite!(tensor)
        {offset + length(lines), cols, [{offset, tensor} | blocks]}
      end)

    if rows == 0, do: raise(ArgumentError, "Matriz vazia.")
    %{rows: rows, cols: cols, blocks: Enum.reverse(blocks)}
  end

  def operators(%{rows: rows, cols: cols, blocks: blocks}) do
    forward = fn vector ->
      blocks
      |> Enum.map(fn {_offset, block} -> EXLA.jit(&matvec/2).(block, vector) end)
      |> Nx.concatenate()
    end

    adjoint = fn vector ->
      Enum.reduce(blocks, Nx.broadcast(Nx.tensor(0.0, type: :f64), {cols}), fn {offset, block},
                                                                               acc ->
        {height, _} = Nx.shape(block)
        slice = Nx.slice_along_axis(vector, offset, height, axis: 0)
        Nx.add(acc, EXLA.jit(&transpose_matvec/2).(block, slice))
      end)
    end

    {rows, cols, forward, adjoint}
  end

  def operators(%Nx.Tensor{} = matrix) do
    {rows, cols} = Nx.shape(matrix)
    Dis.Solver.finite!(matrix)

    {rows, cols, fn vector -> EXLA.jit(&matvec/2).(matrix, vector) end,
     fn vector -> EXLA.jit(&transpose_matvec/2).(matrix, vector) end}
  end

  defn(matvec(matrix, vector), do: Nx.dot(matrix, vector))
  defn(transpose_matvec(matrix, vector), do: Nx.dot(Nx.transpose(matrix), vector))

  def load!(path) do
    {rows, cols, chunks} =
      path
      |> File.stream!()
      |> Enum.reduce({0, nil, []}, fn line, {rows, cols, chunks} ->
        cells = line |> String.trim() |> String.split(",")
        width = length(cells)

        if cols != nil and cols != width,
          do: raise(ArgumentError, "Matriz com linhas de tamanhos diferentes.")

        chunk = for cell <- cells, into: <<>>, do: <<Dis.Input.number!(cell)::float-native-64>>
        {rows + 1, width, [chunk | chunks]}
      end)

    if rows == 0, do: raise(ArgumentError, "Matriz vazia.")

    chunks
    |> Enum.reverse()
    |> IO.iodata_to_binary()
    |> Nx.from_binary(:f64)
    |> Nx.reshape({rows, cols})
  end
end
