defmodule Example.Customer do
  @moduledoc false

  use Ecto.Schema

  use PowerOfThree

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
    field(:first_name, :string)
    field(:last_name, :string)
    field(:email, :string)
    field(:birthday_day, :integer)
    field(:birthday_month, :integer)
    field(:brand_code, :string)
    field(:market_code, :string)
    has_many(:addresses, Address)
    timestamps()
  end

  # cube name and _of_ what schema is it
  # to derive/read during Macro expansion
  #  - cube default table
  #   - field names and types to feed to dimensions/measures generation
  cube "of_customers", of: "customer" do
    # cubes_dimension_name, for what field column name and type 
    dimension(:first_names,
      # for which Ecto table field?
      for: :first_name
    )


    dimension(:zodiac,
      for: [:birthday_day, :birthday_month],
      sql: "CASE ... statement for calculating zodiac sign from two of the above in the list"
    )

    dimension(:brand,
      for: :brand_code
    )

    dimension(:market,
      for: :market_code
    )

    measure(:number_of_customers,
      for: :email,
      type: :count
    )
  end
end
