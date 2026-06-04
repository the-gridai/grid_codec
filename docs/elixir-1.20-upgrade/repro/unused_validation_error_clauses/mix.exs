defmodule UnusedValidationErrorClausesRepro.MixProject do
  use Mix.Project

  def project do
    [
      app: :unused_validation_error_clauses_repro,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: []
    ]
  end
end
