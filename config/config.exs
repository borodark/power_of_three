import Config

config :power_of_3,
  ecto_repos: [Example.Repo]

config :power_of_3, Example.Repo,
  database: "power_of_3_repo",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
