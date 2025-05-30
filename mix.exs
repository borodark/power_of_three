defmodule PowerOfThree.MixProject do
  use Mix.Project

  def project do
    [
      app: :power_of_3,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ymlr, "~> 5.0"},
      {:ecto_sql, "~> 3.0"},
      {:faker, "~> 0.18"},
      {:blacksmith, "~> 0.1"},
      {:postgrex, ">= 0.0.0"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: [
        "clean",
        "deps.get",
        "deps.compile",
        "compile",
        "ecto.drop",
        "ecto.create",
        "ecto.migrate"
      ]
    ]
  end
end
