defmodule Example.Order do
  @moduledoc false

  use Ecto.Schema

  use PowerOfThree

  alias Example.Address
  alias Example.Customer

  @type t() :: %__MODULE__{}

  @financial_status [
    :authorized,
    :paid,
    :partially_paid,
    :partially_refunded,
    :pending_risk_analysis,
    :pending,
    :refunded,
    :rejected,
    :voided
  ]

  @fulfillment_status [
    :accepted,
    :canceled,
    :fulfilled,
    :in_progress,
    :on_hold,
    :partially_canceled,
    :partially_fulfilled,
    :partially_returned,
    :rejected,
    :returned,
    :scheduled,
    :unfulfilled
  ]

  schema "order" do
    field(:delivery_subtotal_amount, :integer, default: 0)
    field(:discount_total_amount, :integer, default: 0)
    field(:email, :string)
    field(:financial_status, Ecto.Enum, values: @financial_status, default: :pending)
    field(:fulfillment_status, Ecto.Enum, values: @fulfillment_status, default: :unfulfilled)
    field(:gift_message, :string, virtual: true, default: nil)
    field(:has_giftwrap?, :boolean, virtual: true, default: false)
    field(:payment_reference, :string)
    field(:subtotal_amount, :integer, default: 0)
    field(:tax_amount, :integer, default: 0)
    field(:total_amount, :integer, default: 0)

    has_one(:billing_address, Address, where: [kind: :billing], on_replace: :delete)
    has_one(:shipping_address, Address, where: [kind: :shipping], on_replace: :delete)

    belongs_to(:customer, Customer,
      foreign_key: :customer_id,
      references: :id
    )

    field(:brand_code, :string)
    field(:market_code, :string)

    timestamps()
  end

  cube :of_orders,
    sql_table: "public.order",
    sql_alias: :order_facts,
    milacious_inject: :penetration_attempt do
    dimension(:financial_status, name: :FIN)
    dimension(:fulfillment_status, name: :FUL)
    dimension(:market_code)
    dimension([:brand_code], name: :brand)

    measure(:subtotal_amount, type: :avg)
    measure(:tax_amount, type: :sum, format: :currency)
    measure(:total_amount, type: :sum)
    measure(:discount_total_amount, type: :sum)
    measure(:count)
  end
end
