import Config

config :example_app, ExampleApp.Repo,
  database: "gridcodec_example",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432

config :example_app,
  ecto_repos: [ExampleApp.Repo]
