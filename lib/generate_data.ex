defmodule GenerateData do
  @shortdoc "Generated a requested number of customers"
  @moduledoc """
  Generated a requested number of customers
  ## Examples:

      iex> alias GenerateData, as: Task
      iex> Task.run([])

  Supply a valid integer for [number_of_records]

      iex> Task.run([10000])
  """

  # use Ecto.Schema
  use Mix.Task

  alias Example.Customer
  alias Example.Address
  alias Example.Order
  alias Example.Repo

  import Ecto.Query, only: [from: 2]

  require Logger

  @the_maximum_is 65535

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

  # Repo.insert_all() has limitation on 32K parameters markers,
  @default_size 5461
  # hence for Customer it's 5461 = 32K/number_of_columns_in_insert

  @impl Mix.Task
  @callback run(command_line_args :: list()) :: any()
  @doc ~S"""
  ## Run Generation

  Supply *[] - empty list* To generate orders data 

      iex> alias GenerateData, as: Task
      iex> Task.run([])

  """

  def run([goal]) when is_integer(goal) do
    Logger.info("Generating #{goal} Orders ...")
    process_next({0, nil}, 0, goal)
  end

  def run([@default_size]) do
    Logger.info("Generating data ...")
    process_next({0, nil}, 0, @default_size)
  end

  def run([]), do: run([@default_size])

  def run(_list) do
    Logger.info(
      "Please supply either empty list `[]` to run with default  number_of_customers of `5461` , or a valid integers for [number_of_customers_to_insert]"
    )
  end

  @spec process_next({this_time :: integer(), nil}, so_far :: integer(), goal :: integer()) ::
          {so_far :: integer(), goal :: integer()} | :ok
  def process_next({this_time, nil}, so_far, goal) when goal == so_far do
    Logger.info("Generated last batch of #{this_time} ...")
    Logger.info("Done generating total of #{goal}.")
  end

  def process_next({this_time, nil}, so_far, goal) when goal > so_far do
    Logger.info("Generated next batch of #{this_time} Orders ...")
    so_far = so_far + this_time

    customers =
      case goal - so_far > @default_size do
        true ->
          Stream.repeatedly(&__MODULE__.a_customer/0) |> Enum.take(@default_size)

        false ->
          ## it's less than or equal to @default_size left to go
          Stream.repeatedly(&__MODULE__.a_customer/0) |> Enum.take(goal - so_far)
      end

    {inserted, nil} = Repo.insert_all(Customer, customers)
    Repo.insert_all(Order, orderz())
    #order_addressez = Stream.repeatedly(&__MODULE__.order_addressez/0)
    #|> Enum.take(3)
    #|> IO.inspect(label: :orders)
    #Repo.insert_all(Order, order_addressez)

    {inserted, nil} |> process_next(so_far, goal)
  end

  def orderz do
    customer_ids =
      from(Customer,
        select: [:id]
      )
    idz = Repo.all(customer_ids)
    |> Enum.map(fn %Customer{id: customer_id} = _c -> customer_id end)
    |> IO.inspect(label: :idz)

    idz |> Enum.map(fn customer_id -> order(customer_id) end)
  end

  def a_customer do
    fake_bd = Faker.DateTime.between(~N[1934-12-20 00:00:00], ~N[2006-12-25 00:00:00])

    {bd_day, bd_month} =
      Enum.random([{nil, nil}, {nil, nil}, {nil, nil}, {fake_bd.day, fake_bd.month}])

    %{
      birthday_day: bd_day,
      birthday_month: bd_month,
      brand_code: Faker.Beer.brand(),
      email: Faker.Internet.email(),
      first_name: Faker.Person.first_name(),
      last_name: Faker.Person.last_name(),
      market_code: Faker.Address.country_code(),
      inserted_at: fake_bd |> DateTime.to_naive() |> NaiveDateTime.truncate(:second),
      updated_at:
        Faker.DateTime.backward(900) |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
    }
  end

  def order_shipping_address(order_id) do
    Map.merge(
      %{kind: :shipping, order_id: order_id},
      base_address()
    )
  end

  def order_billing_address(order_id) do
    Map.merge(
      %{kind: :billing, order_id: order_id},
      base_address()
    )
  end

  def customer_billing_address(%Customer{} = customer) do
    Map.merge(
      %{kind: :billing, customer_id: customer.id},
      base_address()
    )
  end

  def customer_shipping_address(%Customer{} = customer) do
    Map.merge(
      %{kind: :shipping, customer_id: customer.id},
      base_address()
    )
  end

  def base_address() do
    %{
      brand_code: Faker.Beer.brand(),
      market_code: Faker.Address.country_code(),
      email: Faker.Internet.email(),
      address_1: Faker.Address.En.street_address(),
      address_2: Faker.Address.En.secondary_address(),
      city: Faker.Address.En.city(),
      company: Enum.random([nil, nil, nil, Faker.Company.name()]),
      country_code: Faker.Address.En.country_code(),
      country: Faker.Address.En.country(),
      first_name: Faker.Person.first_name(),
      last_name: Faker.Person.last_name(),
      phone: Faker.Phone.EnUs.phone(),
      postal_code: Faker.Address.En.zip_code(),
      province: Faker.Address.En.state(),
      province_code: Faker.Address.En.state_abbr(),
      summary: "FaKeD",
      inserted_at:
        Faker.DateTime.backward(1000) |> DateTime.to_naive() |> NaiveDateTime.truncate(:second),
      updated_at:
        Faker.DateTime.backward(900) |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
    }
  end

  def order(customer_id) do
    %{
      brand_code: Faker.Beer.brand(),
      market_code: Faker.Address.country_code(),
      delivery_subtotal_amount: Faker.random_between(0, 299),
      discount_total_amount: Faker.random_between(0, 299),
      email: Faker.Internet.email(),
      financial_status: @financial_status |> Enum.random(),
      fulfillment_status: @fulfillment_status |> Enum.random(),
      payment_reference: Faker.Blockchain.Bitcoin.address(),
      subtotal_amount: Faker.random_between(0, 4299),
      tax_amount: Faker.random_between(0, 599),
      total_amount: Faker.random_between(0, 5599),
      customer_id: customer_id,
      inserted_at:
        Faker.DateTime.backward(Faker.random_between(0, 365))
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second),
      updated_at:
        Faker.DateTime.backward(Faker.random_between(0, 100))
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second)
    }
  end
end
