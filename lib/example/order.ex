defmodule Example.Order do
  @moduledoc false

  use Ecto.Schema

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

  @required_fields [
    :brand_code,
    :email,
    :market_code,
    :reference_number,
    :site_domain,
    :subtotal_amount,
    :total_amount
  ]

  @optional_fields [
    :attributes,
    :customer_uuid,
    :delivery_subtotal_amount,
    :discount_total_amount,
    :financial_status,
    :fulfillment_status,
    :payment_reference,
    :tax_amount
  ]

  schema "order" do
    field :delivery_subtotal_amount, :integer, default: 0
    field :discount_total_amount, :integer, default: 0
    field :email, :string
    field :financial_status, Ecto.Enum, values: @financial_status, default: :pending
    field :fulfillment_status, Ecto.Enum, values: @fulfillment_status, default: :unfulfilled
    field :gift_message, :string, virtual: true, default: nil
    field :has_giftwrap?, :boolean, virtual: true, default: false
    field :payment_reference, :string
    field :subtotal_amount, :integer, default: 0
    field :tax_amount, :integer, default: 0
    field :total_amount, :integer, default: 0

    has_one :billing_address, Address, where: [kind: :billing], on_replace: :delete
    has_one :shipping_address, Address, where: [kind: :shipping], on_replace: :delete

    belongs_to :customer, Customer,
      foreign_key: :customer_id,
      references: :id

    field :brand_code, :string
    field :market_code, :string

    timestamps()
  end
end
