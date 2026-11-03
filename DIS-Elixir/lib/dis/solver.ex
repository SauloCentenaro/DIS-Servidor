defmodule Dis.Solver do
  @tolerance 1.0e-4

  def solve(h, g, algorithm \\ :cgnr) when algorithm in [:cgnr, :cgne] do
    {rows, cols, forward, adjoint} = Dis.Matrix.operators(h)
    if Nx.shape(g) != {rows}, do: raise(ArgumentError, "Dimensões incompatíveis.")
    finite!(g)
    f = Nx.broadcast(Nx.tensor(0.0, type: :f64), {cols})
    z = adjoint.(g)
    initial = norm(if algorithm == :cgnr, do: z, else: g)

    if initial == 0.0 do
      {f, 0}
    else
      iterate({f, g, z, z}, initial, 0, algorithm, forward, adjoint)
    end
  end

  # Functions are passed as values: the recurrence works with dense or blocked matrices.
  defp iterate({f, r, z, p}, initial, count, algorithm, forward, adjoint) do
    limit = if algorithm == :cgnr, do: 20, else: 100

    if count == limit do
      {f, count}
    else
      w = forward.(p)
      numerator = squared_norm(if algorithm == :cgnr, do: z, else: r)
      denominator = squared_norm(if algorithm == :cgnr, do: w, else: p)

      if denominator <= 0 or numerator <= 0,
        do: raise(ArithmeticError, "Sistema singular ou falha numérica.")

      alpha = numerator / denominator
      next_f = Nx.add(f, Nx.multiply(alpha, p)) |> finite!()
      next_r = Nx.subtract(r, Nx.multiply(alpha, w)) |> finite!()
      next_z = adjoint.(next_r) |> finite!()
      residual = if algorithm == :cgnr, do: next_z, else: next_r

      if norm(residual) <= @tolerance * initial do
        {next_f, count + 1}
      else
        beta = squared_norm(residual) / numerator
        next_p = Nx.add(next_z, Nx.multiply(beta, p))
        iterate({next_f, next_r, next_z, next_p}, initial, count + 1, algorithm, forward, adjoint)
      end
    end
  end

  def finite!(tensor) do
    if tensor
       |> Nx.is_nan()
       |> Nx.logical_or(Nx.is_infinity(tensor))
       |> Nx.any()
       |> Nx.to_number() == 1,
       do: raise(ArithmeticError, "Resultado numérico não finito.")

    tensor
  end

  defp squared_norm(tensor) do
    value = tensor |> Nx.multiply(tensor) |> Nx.sum() |> Nx.to_number()
    if not is_number(value), do: raise(ArithmeticError, "Norma não finita.")
    value
  end

  defp norm(tensor), do: :math.sqrt(squared_norm(tensor))
end
