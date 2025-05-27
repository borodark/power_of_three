import Config

config :power_of_3,
  ecto_repos: [Tarakan.Repo]

config :power_of_3, Example.Repo,
  database: "power_of_3_repo",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 7432,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :power_of_3, Tarakan.Repo,
  username: "admin",
  password: "admin",
  hostname: "localhost",
  database: "power_of_3_repo",
  port: 26257,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  migration_lock: false
