defmodule Example.Customer do
  @moduledoc false

  use Ecto.Schema

  use PowerOfThree

  alias Example.Address

  @type t() :: %__MODULE__{}

  # @required_fields [:brand_code, :email, :market_code]
  # @optional_fields [    :birthday_day,    :birthday_month,    :default_address_id,    :first_name,    :last_name  ]

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

  cube :of_customers, of: :customer do
    dimension(:email_per_brand_per_market,
      for: [:brand_code, :market_code, :email],
      cube_primary_key: true
    )

    time_dimensions()

    dimension(:names,
      for: :first_name
    )

    dimension(:zodiac,
      type: :string,
      for: [:birthday_day, :birthday_month],
      sql: "'WASSERMAN'"
      # hardcoded for now but"CASE ... statement for calculating zodiac sign from two of the above in the list"
    )

    dimension(:bm_code,
      type: :string,
      for: [:brand_code, :market_code],
      sql: "brand_code|| '_' || market_code"
      ## TODO danger lurking here"
    )

    dimension(:brand,
      for: :brand_code
    )

    dimension(:market,
      for: :market_code
    )

    # measure(:number_of_customers,
    #  for: :email,
    #  type: :count
    # )
  end
end
