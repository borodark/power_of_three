defmodule Example.Address do
  @moduledoc """
  Schema for Address model entity.
  """
  use Ecto.Schema

  alias Example.Customer
  alias Example.Order

  @type t() :: %__MODULE__{}

  @required_fields [
    :address_1,
    :city,
    :country_code,
    :first_name,
    :kind,
    :last_name,
    :phone,
    :postal_code,
    :province_code,
    :site_domain,
    :market_code,
    :brand_code
  ]

  # for those fields we're gonna need locales and recheck how to build then
  @optional_fields [
    :address_2,
    :checkout_id,
    :company,
    :country,
    :customer_id,
    :order_id,
    :province,
    :summary,
    :url
  ]

  @kinds [:shipping, :billing]

  schema "address" do
    field :address_1, :string
    field :address_2, :string
    field :brand_code, :string
    field :city, :string
    field :company, :string
    field :country_code, :string
    field :country, :string
    field :first_name, :string
    field :kind, Ecto.Enum, values: @kinds
    field :last_name, :string
    field :phone, :string
    field :postal_code, :string
    field :province, :string
    field :province_code, :string
    field :market_code, :string
    field :site_domain, :string
    field :summary, :string
    field :url, :string

    belongs_to :customer, Customer,
      foreign_key: :customer_id,
      references: :id

    belongs_to :order, Order,
      foreign_key: :order_id,
      references: :id

    timestamps()
  end

end
