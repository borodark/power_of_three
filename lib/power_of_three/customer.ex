# Test schemas matching the live cubes
defmodule PowerOfThree.Customer do
  use Ecto.Schema
  use PowerOfThree

  schema "customer" do
    field(:first_name, :string)
    field(:email, :string)
    field(:birthday_day, :integer)
    field(:birthday_month, :integer)
    field(:brand_code, :string)
    field(:market_code, :string)
    timestamps()
  end

  cube :power_customers,
    sql_table: "customer",
    title: "customers cube",
    description: "of Customers" do
    dimension(:first_name, name: :given_name, description: "good documentation")
    dimension(:brand_code, name: :brand, description: "Beer")
    dimension(:market_code, name: :market, description: "market_code, like AU")

    dimension([:birthday_day, :birthday_month],
      name: :zodiac,
      description: "SQL for a zodiac sign",
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
      ELSE 'Professor Abe Weissman'
      END
      """
    )

    dimension([:birthday_day, :birthday_month],
      name: :star_sector,
      type: :number,
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
      ELSE -1
      END
      """
    )

    dimension([:brand_code, :market_code],
      name: :bm_code,
      sql: "brand_code|| '_' || market_code"
    )

    dimension(:updated_at, name: :updated, description: "updated_at timestamp")

    measure(:count, description: "no need for fields for :count type measure")
  end
end
