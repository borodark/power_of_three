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

  # cube name and _of_ what schema is it
  # to derive/read during Macro expansion
  #  - cube default table
  #   - field names and types to feed to dimensions/measures generation

  @doc """
  CASE
        WHEN (birthday_month = 1 AND day >= 20) OR (month = 2 AND day <= 18) THEN 'Aquarius'
        WHEN (month = 2 AND day >= 19) OR (month = 3 AND day <= 20) THEN 'Pisces'
        WHEN (month = 3 AND day >= 21) OR (month = 4 AND day <= 19) THEN 'Aries'
        WHEN (month = 4 AND day >= 20) OR (month = 5 AND day <= 20) THEN 'Taurus'
        WHEN (month = 5 AND day >= 21) OR (month = 6 AND day <= 20) THEN 'Gemini'
        WHEN (month = 6 AND day >= 21) OR (month = 7 AND day <= 22) THEN 'Cancer'
        WHEN (month = 7 AND day >= 23) OR (month = 8 AND day <= 22) THEN 'Leo'
        WHEN (month = 8 AND day >= 23) OR (month = 9 AND day <= 22) THEN 'Virgo'
        WHEN (month = 9 AND day >= 23) OR (month = 10 AND day <= 22) THEN 'Libra'
        WHEN (month = 10 AND day >= 23) OR (month = 11 AND day <= 21) THEN 'Scorpio'
        WHEN (month = 11 AND day >= 22) OR (month = 12 AND day <= 21) THEN 'Sagittarius'
        WHEN (month = 12 AND day >= 22) OR (month = 1 AND day <= 19) THEN 'Capricorn'
        ELSE 'Unknown'
        END AS zodiac_sign
  """
  cube :of_customers, of: :customer do
    dimension(:email_per_brand_per_market,
      description: "MANDATORI",
      for: [:brand_code, :market_code, :email],
      cube_primary_key: true
    )

    time_dimensions()

    dimension(:names,
      description: "MANDATORI",
      for: :first_name
    )

    dimension(:zodiac,
      description:
        "SQL for a zodiac sign for given [:birthday_day, :birthday_month], not _gyroscope_, TODO unicode of Emoji",
      type: :number,
      for: [:birthday_day, :birthday_month],
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

    dimension(:bm_code,
      description: " brand_code+_+market_code, like TF_AU",
      type: :string,
      for: [:brand_code, :market_code],
      sql: "brand_code|| '_' || market_code"
      ## TODO danger lurking here"
    )

    dimension(:brand,
      description: " brand_code, like TF",
      for: :brand_code
    )

    dimension(:market,
      description: "market_code, like AU",
      for: :market_code
    )

    measure(:number_of_emails,
      type: :count,
      for: :email,
      description: "count of emails, int perhaps"
    )

    measure(:number_of_customers,
      type: :count,
      for: [:brand_code, :market_code, :email],
      description: "count of emails, int perhaps"
    )

    measure(:obscure_one,
      type: :sum,
      for: :birthday_day,
      description: "Explore your inner data scientist"
    )
  end
end
