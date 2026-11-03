defmodule Dis.Application do
  use Application

  def start(_type, _args) do
    children = [{Task.Supervisor, name: Dis.Tasks}, Dis.Worker]

    children =
      if Application.get_env(:dis, :http),
        do:
          children ++
            [
              {Bandit,
               plug: Dis.Router, port: Application.fetch_env!(:dis, :port), ip: {0, 0, 0, 0}}
            ],
        else: children

    Supervisor.start_link(children, strategy: :one_for_one, name: Dis.Supervisor)
  end
end
