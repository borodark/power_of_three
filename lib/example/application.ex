defmodule Example.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true

    def start(_type, _args) do
      children = [
        Example.Repo,
      ]

      Supervisor.start_link(children, strategy: :one_for_one, name: Example.Supervisor)
  end
end
