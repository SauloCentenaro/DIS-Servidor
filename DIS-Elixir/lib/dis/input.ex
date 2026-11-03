defmodule Dis.Input do
  def number!(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> number
      _ -> raise ArgumentError, "Vetor contém valor inválido."
    end
  end

  def number!(_), do: raise(ArgumentError, "Cada amostra deve ser uma string numérica.")

  def request!(%{"model" => model, "ganho" => gain, "user" => user, "vector" => values})
      when is_boolean(model) and is_boolean(gain) and is_integer(user) and is_list(values) do
    if values == [] or length(values) > 100_000,
      do: raise(ArgumentError, "Tamanho de vetor inválido.")

    %{
      model: model,
      gain: gain,
      user: user,
      vector: Nx.tensor(Enum.map(values, &number!/1), type: :f64)
    }
  end

  def request!(_),
    do: raise(ArgumentError, "Informe model, ganho, user e vector com tipos válidos.")
end
