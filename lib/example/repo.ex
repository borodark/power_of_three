defmodule Example.Repo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :power_of_3,
    adapter: Ecto.Adapters.Postgres
end

defmodule Tarakan.Repo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :power_of_3,
    adapter: Ecto.Adapters.Postgres
end
