defmodule Example.Address do
  @moduledoc false
  use Ecto.Schema

  use PowerOfThree

  alias Example.Customer
  alias Example.Order

  @type t() :: %__MODULE__{}

  @kinds [:shipping, :billing]

  @schema_prefix :prefixed_schema_of_address

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
      [:brand_code, :market_code, :country],
      name: :country_bm
    )

    dimension(
      :kind,
      name: :kind
    )

    dimension(
      :first_name,
      name: :given_name,
      description: "Louzy documentation"
    )

    time_dimensions()

    measure(:count,
      name: :count_of_records,
      description: "no need for fields for :count type measure"
    )

    measure(:country, type: :count, name: :country_count)
  end
end
