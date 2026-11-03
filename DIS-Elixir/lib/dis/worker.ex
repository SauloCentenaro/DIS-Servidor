defmodule Dis.Worker do
  use GenServer
  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def reconstruct(params), do: GenServer.call(__MODULE__, {:run, params}, :infinity)
  def init(_), do: {:ok, nil}

  def handle_call({:run, params}, _from, state) do
    # One isolated task at a time: large matrices are released when the task exits.
    task =
      Task.Supervisor.async_nolink(Dis.Tasks, fn ->
        try do
          {:ok, Dis.Reconstruction.run(params)}
        rescue
          e in [ArgumentError] -> {:error, 400, Exception.message(e)}
          e -> {:error, 500, Exception.message(e)}
        end
      end)

    result =
      case Task.yield(task, :infinity) do
        {:ok, reply} -> reply
        {:exit, _} -> {:error, 500, "Falha no processamento."}
      end

    {:reply, result, state}
  end
end
