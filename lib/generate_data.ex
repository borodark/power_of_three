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

  use Ecto.Schema
  use Mix.Task

  alias Example.Customer
  alias Example.Repo

  require Logger

  @default_size 5461

  @impl Mix.Task
  @callback run(command_line_args :: [integer()]) :: any()
  @doc ~S"""
  ## Run Generation

  Supply *[] - empty list* To generate data 

      iex> alias GenerateData, as: Task
      iex> Task.run([])

  """
  def run([]) do
    Logger.info("Generating data ...")
    process_next({0, nil}, 0, @default_size)
  end

  def run([goal]) when is_integer(goal) do
    Logger.info("Generating #{goal} customers ...")
    process_next({0, nil}, 0, goal)
  end

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
    Logger.info("Generated next batch of #{this_time} customers ...")
    so_far = so_far + this_time

    next_batch =
      case goal - so_far > @default_size do
        true ->
          Stream.repeatedly(&__MODULE__.a_customer/0) |> Enum.take(@default_size)

        false ->
          ## it's less than or equal to @default_size left to go
          Stream.repeatedly(&__MODULE__.a_customer/0) |> Enum.take(goal - so_far)
      end

    Repo.insert_all(Customer, next_batch)
    |> process_next(so_far, goal)
  end

  def a_customer do
    email = to_string(:rand.uniform(999_999_999_999_999_999)) <> "@estee.com"
    fake_bd = Faker.Date.between(~D[1932-01-01], ~D[2005-12-31])
    %{
      birthday_day: fake_bd.day,
      birthday_month: fake_bd.month,
      brand_code: "TF",
      email: email,
      first_name: Faker.Person.first_name(),
      last_name: Faker.Person.last_name(),
      market_code: "US"
    }
  end
end
