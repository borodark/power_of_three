defmodule Tarakan.Repo do
  use Ecto.Repo,
    otp_app: :power_of_3,
    adapter: Ecto.Adapters.Postgres
end
