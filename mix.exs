defmodule PowerOfThree.MixProject do
  use Mix.Project

  def project do
    [
      app: :power_of_3,
      version: "0.1.2",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [
        threshold: 90,
        ignore_modules: [
          # Requires ADBC dependency not available in tests
          PowerOfThree.CubeConnection
        ]
      ],
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      # Docs
      name: "PowerOfThree",
      source_url: "https://github.com/borodark/power-of-three",
      homepage_url: "https://github.com/borodark/power-of-three",
      package: package()
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
      {:ecto_sql, "~> 3.10"},
      {:explorer, "~> 0.11.1"},
      {:adbc, github: "borodark/adbc", branch: "cleanup-take-II", override: true, optional: true},

      {:req, "~> 0.5"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false, warn_if_outdated: true},
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

  defp package() do
    [
      # The main page in the docs
      main: "PowerOfThree",
      logo: "priv/logo.png",
      extras: ["README.md"],
      exclude_patterns: ["lib/generate_data.ex", "lib/example/repo.ex"],
      description: "Start with everything. Keep what performs. Pre-aggregate what matters. | Inline Cubes with Ecto.Schema",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/borodark/power_of_three",
        "cube" => "https://cube.dev/docs/product/data-modeling/reference/cube",
        "dimensions" => "https://cube.dev/docs/product/data-modeling/reference/dimensions",
        "measures" => "https://cube.dev/docs/product/data-modeling/reference/measures"
      }
    ]
  end
end
