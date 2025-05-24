defmodule Example.Address do
  @moduledoc """
  Schema for Address model entity.
  """
  use Ecto.Schema

  use PowerOfThree

  alias Example.Customer
  alias Example.Order

  @type t() :: %__MODULE__{}

  @kinds [:shipping, :billing]

  schema "address" do
    field(:address_1, :string)
    field(:address_2, :string)
    field(:brand_code, :string)
    field(:city, :string)
    field(:company, :string)
    field(:country_code, :string)
    field(:country, :string)
    field(:first_name, :string)
    field(:kind, Ecto.Enum, values: @kinds)
    field(:last_name, :string)
    field(:phone, :string)
    field(:postal_code, :string)
    field(:province, :string)
    field(:province_code, :string)
    field(:market_code, :string)
    field(:summary, :string)

    belongs_to(:customer, Customer,
      foreign_key: :customer_id,
      references: :id
    )

    belongs_to(:order, Order,
      foreign_key: :order_id,
      references: :id
    )

    timestamps()
  end

  cube :of_addresses,
    sql_table: "address",
    title: "Demo cube",
    description: "of Customers" do
    dimension(
      :country_bm,
      [:brand_code, :market_code, :country]
    )

    dimension(
      :kind,
      :kind
    )

    dimension(
      :names,
      :first_name,
      description: "Louzy documentation"
    )

    time_dimensions()

    measure(:number_of_addresses,
      type: :count,
      description: "no need for fields for :count type measure"
    )

    measure(:country_count, :country, type: :count)
  end
end
