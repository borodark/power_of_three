defmodule Example.Customer do
  @moduledoc false

  use Ecto.Schema

  @type t() :: %__MODULE__{}

  @required_fields [:brand_code, :email, :market_code]
  @optional_fields [
    :birthday_day,
    :birthday_month,
    :default_address_id,
    :first_name,
    :last_name
  ]

  schema "customer" do
    field :first_name, :string
    field :last_name, :string
    field :email, :string
    field :birthday_day, :integer
    field :birthday_month, :integer
    field :brand_code, :string
    field :market_code, :string
    has_many :addresses, Address
    timestamps()
  end
end
