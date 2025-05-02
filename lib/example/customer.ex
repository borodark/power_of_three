defmodule Example.Customer do
  @moduledoc false

  use Ecto.Schema

  use PowerOfThree

  alias Example.Address

  @type t() :: %__MODULE__{}

  @required_fields [:brand_code, :email, :market_code]
  @optional_fields [:birthday_day, :birthday_month, :address_id, :first_name, :last_name]

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

  cube :of_customers, of: :customer do
    dimension(
      :email_per_brand_per_market,
      [:brand_code, :market_code, :email],
      description: "MANDATORI",
      cube_primary_key: true
    )

    dimension(
      :names,
      :first_name,
      description: "MANDATORI"
    )

    dimension(:zodiac, [:birthday_day, :birthday_month],
      description:
        "SQL for a zodiac sign for given [:birthday_day, :birthday_month], not _gyroscope_, TODO unicode of Emoji",
      sql: """
      CASE
      WHEN (birthday_month = 1 AND birthday_day >= 20) OR (birthday_month = 2 AND birthday_day <= 18) THEN 'Aquarius'
      WHEN (birthday_month = 2 AND birthday_day >= 19) OR (birthday_month = 3 AND birthday_day <= 20) THEN 'Pisces'
      WHEN (birthday_month = 3 AND birthday_day >= 21) OR (birthday_month = 4 AND birthday_day <= 19) THEN 'Aries'
      WHEN (birthday_month = 4 AND birthday_day >= 20) OR (birthday_month = 5 AND birthday_day <= 20) THEN 'Taurus'
      WHEN (birthday_month = 5 AND birthday_day >= 21) OR (birthday_month = 6 AND birthday_day <= 20) THEN 'Gemini'
      WHEN (birthday_month = 6 AND birthday_day >= 21) OR (birthday_month = 7 AND birthday_day <= 22) THEN 'Cancer'
      WHEN (birthday_month = 7 AND birthday_day >= 23) OR (birthday_month = 8 AND birthday_day <= 22) THEN 'Leo'
      WHEN (birthday_month = 8 AND birthday_day >= 23) OR (birthday_month = 9 AND birthday_day <= 22) THEN 'Virgo'
      WHEN (birthday_month = 9 AND birthday_day >= 23) OR (birthday_month = 10 AND birthday_day <= 22) THEN 'Libra'
      WHEN (birthday_month = 10 AND birthday_day >= 23) OR (birthday_month = 11 AND birthday_day <= 21) THEN 'Scorpio'
      WHEN (birthday_month = 11 AND birthday_day >= 22) OR (birthday_month = 12 AND birthday_day <= 21) THEN 'Sagittarius'
      WHEN (birthday_month = 12 AND birthday_day >= 22) OR (birthday_month = 1 AND birthday_day <= 19) THEN 'Capricorn'
      ELSE 'Aquarius'
      END
      """
    )

    dimension(:star_sector, [:birthday_day, :birthday_month],
      description: "integer from 0 to 11 for zodiac signs",
      sql: """
      CASE
      WHEN (birthday_month = 1 AND birthday_day >= 20) OR (birthday_month = 2 AND birthday_day <= 18) THEN 0
      WHEN (birthday_month = 2 AND birthday_day >= 19) OR (birthday_month = 3 AND birthday_day <= 20) THEN 1
      WHEN (birthday_month = 3 AND birthday_day >= 21) OR (birthday_month = 4 AND birthday_day <= 19) THEN 2
      WHEN (birthday_month = 4 AND birthday_day >= 20) OR (birthday_month = 5 AND birthday_day <= 20) THEN 3
      WHEN (birthday_month = 5 AND birthday_day >= 21) OR (birthday_month = 6 AND birthday_day <= 20) THEN 4
      WHEN (birthday_month = 6 AND birthday_day >= 21) OR (birthday_month = 7 AND birthday_day <= 22) THEN 5
      WHEN (birthday_month = 7 AND birthday_day >= 23) OR (birthday_month = 8 AND birthday_day <= 22) THEN 6
      WHEN (birthday_month = 8 AND birthday_day >= 23) OR (birthday_month = 9 AND birthday_day <= 22) THEN 7
      WHEN (birthday_month = 9 AND birthday_day >= 23) OR (birthday_month = 10 AND birthday_day <= 22) THEN 8
      WHEN (birthday_month = 10 AND birthday_day >= 23) OR (birthday_month = 11 AND birthday_day <= 21) THEN 9
      WHEN (birthday_month = 11 AND birthday_day >= 22) OR (birthday_month = 12 AND birthday_day <= 21) THEN 10
      WHEN (birthday_month = 12 AND birthday_day >= 22) OR (birthday_month = 1 AND birthday_day <= 19) THEN 11
      ELSE 0
      END
      """
    )

    dimension(
      :bm_code,
      [:brand_code, :market_code],
      description: " brand_code+_+market_code, like TF_AU",
      type: :string,
      # This is Cube Dimension type. TODO like in ecto :kind, Ecto.Enum, values: @kinds
      sql: "brand_code|| '_' || market_code"
      ## TODO danger lurking here"
    )

    dimension(:brand, :brand_code, description: " brand_code, like TF")

    dimension(:market, :market_code, description: "market_code, like AU")

    dimension(:arbirtary_datetime, :updated_at, description: "IDK ...?")

    measure(:number_of_emails, :email,
      type: :count_distinct,
      description: "count of emails, int perhaps"
    )

    measure(:obscure_one, :birthday_day,
      type: :sum,
      description: "Explore your inner data scientist"
    )

    measure(:latest_joined, :inserted_at,
      type: :max,
      description: "Again, Explore your inner data scientist"
    )

    measure(:updated_pii, :updated_at,
      type: :max,
      description: "Again, Explore your inner data scientist"
    )

    measure(:number_of_accounts, [:brand_code, :market_code, :email],
      type: :count,
      description: "Accounts: email + market code + brand code"
    )
  end
end
