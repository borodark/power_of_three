defmodule Example.Repo.Migrations.Customers do
  use Ecto.Migration

  def change do
    create table(:customer) do
      add :first_name, :string
      add :last_name, :string
      add :email, :string
      add :birthday_day, :integer
      add :birthday_month, :integer
      add :brand_code, :string
      add :market_code, :string
      timestamps()
    end

    create table(:order) do
      add :delivery_subtotal_amount, :integer
      add :discount_total_amount, :integer
      add :email, :string
      add :financial_status, :string
      add :fulfillment_status, :string
      add :gift_message, :string, virtual: true, default: nil
      add :has_giftwrap?, :boolean, virtual: true, default: false
      add :payment_reference, :string
      add :subtotal_amount, :integer
      add :tax_amount, :integer
      add :total_amount, :integer
      add :customer_id,
        references(:customer)
      add :brand_code, :string
      add :market_code, :string
      timestamps()
    end

    create table(:address) do
      add :address_1, :string
      add :address_2, :string
      add :brand_code, :string
      add :city, :string
      add :company, :string
      add :country_code, :string
      add :country, :string
      add :first_name, :string
      add :kind, :string
      add :last_name, :string
      add :phone, :string
      add :postal_code, :string
      add :province, :string
      add :province_code, :string
      add :market_code, :string
      add :summary, :string
      add :customer_id,
        references(:customer)
      add :order_id,
        references(:order)
      timestamps()
    end
  end
end
