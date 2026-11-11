defmodule Dis.Worker do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def reconstruct(params), do: GenServer.call(__MODULE__, {:run, params}, :infinity)

  def init(_) do
    limit =
      System.get_env("WORKER_THREADS", "1")
      |> Integer.parse()
      |> case do
        {value, ""} when value in 1..256 -> value
        _ -> raise ArgumentError, "WORKER_THREADS deve estar entre 1 e 256."
      end

    {:ok, %{limit: limit, running: %{}, queue: :queue.new()}}
  end

  def handle_call({:run, params}, from, state) do
    {:noreply, enqueue_or_start(params, from, state)}
  end

  def handle_info({reference, result}, state) when is_reference(reference) do
    case Map.pop(state.running, reference) do
      {nil, _running} ->
        {:noreply, state}

      {{_pid, from}, running} ->
        Process.demonitor(reference, [:flush])
        GenServer.reply(from, result)
        {:noreply, start_queued(%{state | running: running})}
    end
  end

  def handle_info({:DOWN, reference, :process, _pid, _reason}, state) do
    case Map.pop(state.running, reference) do
      {nil, _running} ->
        {:noreply, state}

      {{_pid, from}, running} ->
        GenServer.reply(from, {:error, 500, "Falha no processamento."})
        {:noreply, start_queued(%{state | running: running})}
    end
  end

  defp enqueue_or_start(params, from, state) do
    if map_size(state.running) < state.limit do
      start_task(params, from, state)
    else
      %{state | queue: :queue.in({params, from}, state.queue)}
    end
  end

  defp start_queued(state) do
    case :queue.out(state.queue) do
      {{:value, {params, from}}, queue} -> start_task(params, from, %{state | queue: queue})
      {:empty, _queue} -> state
    end
  end

  defp start_task(params, from, state) do
    task =
      Task.Supervisor.async_nolink(Dis.Tasks, fn ->
        try do
          {:ok, Dis.Reconstruction.run(params)}
        rescue
          e in [ArgumentError] -> {:error, 400, Exception.message(e)}
          e -> {:error, 500, Exception.message(e)}
        end
      end)

    %{state | running: Map.put(state.running, task.ref, {task.pid, from})}
  end
end
