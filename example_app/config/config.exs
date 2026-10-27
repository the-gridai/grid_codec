import Config

config :example_app, ExampleApp.Repo,
  database: "gridcodec_example",
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  port: System.get_env("DATABASE_PORT", "5432") |> String.to_integer()

config :example_app,
  ecto_repos: [ExampleApp.Repo]

config :example_app, :grid_codec,
  schemas: %{
    100 => "events",
    99 => "bench_trace",
    200 => "bench_sizes"
  }
