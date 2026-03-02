defmodule ExampleApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ExampleApp.Repo
    ]

    opts = [strategy: :one_for_one, name: ExampleApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
