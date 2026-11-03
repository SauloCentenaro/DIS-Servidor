defmodule Dis.MixProject do
  use Mix.Project

  def project,
    do: [
      app: :dis,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]

  def application, do: [extra_applications: [:logger], mod: {Dis.Application, []}]

  defp deps,
    do: [
      {:bandit, "~> 1.6"},
      {:plug, "~> 1.16"},
      {:jason, "~> 1.4"},
      {:nx, "~> 0.9.2"},
      {:exla, "~> 0.9.2"}
    ]
end
