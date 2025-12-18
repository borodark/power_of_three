defmodule PowerOfThree.MeasureRef do
  @moduledoc """
  Represents a reference to a cube measure.

  Used in dot-accessible collections like `Customer.measures.aquarii`

  ## Fields

    * `:name` - The measure name (atom or string)
    * `:module` - The module where this measure is defined
    * `:type` - The measure type (`:count`, `:sum`, `:count_distinct`, etc.)
    * `:sql` - The SQL expression or column reference
    * `:meta` - Metadata map containing ecto field information
    * `:description` - Optional description of the measure
    * `:filters` - Optional list of filter maps
    * `:format` - Optional format specification

  ## Examples

      # Reference created by generated accessor
      measure_ref = Customer.measures.aquarii()
      %MeasureRef{
        name: :aquarii,
        module: Customer,
        type: :count_distinct,
        sql: :email,
        ...
      }

      # Convert to SQL column expression
      MeasureRef.to_sql_column(measure_ref)
      # => "MEASURE(customer.aquarii)"
  """

  @enforce_keys [:name, :module, :type]
  defstruct [
    :name,
    :module,
    :type,
    :sql,
    :meta,
    :description,
    :filters,
    :format
  ]

  @type measure_type ::
          :count
          | :count_distinct
          | :count_distinct_approx
          | :sum
          | :avg
          | :min
          | :max
          | :number

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          module: module(),
          type: measure_type(),
          sql: term(),
          meta: map() | nil,
          description: String.t() | nil,
          filters: list(map()) | nil,
          format: atom() | nil
        }

  @doc """
  Converts a measure reference to a SQL column expression.

  Returns the MEASURE() function syntax used by Cube SQL.

  ## Examples

      iex> measure = %MeasureRef{name: :count, module: Customer, type: :count}
      iex> MeasureRef.to_sql_column(measure)
      "MEASURE(customer.count)"

      iex> measure = %MeasureRef{name: "total_revenue", module: Orders, type: :sum}
      iex> MeasureRef.to_sql_column(measure)
      "MEASURE(orders.total_revenue)"
  """
  @spec to_sql_column(t()) :: String.t()
  def to_sql_column(%__MODULE__{module: module, name: name}) do
    cube_name = extract_cube_name(module)
    measure_name = to_string(name)
    "MEASURE(#{cube_name}.#{measure_name})"
  end

  @doc """
  Returns the cube name from the module.

  Uses the Ecto schema source as the cube name.

  ## Examples

      iex> MeasureRef.extract_cube_name(Customer)
      "customer"
  """
  @spec extract_cube_name(module()) :: String.t()
  def extract_cube_name(module) do
    module.__schema__(:source)
  end

  @doc """
  Returns the measure name as a string.

  ## Examples

      iex> measure = %MeasureRef{name: :count, module: Customer, type: :count}
      iex> MeasureRef.name_string(measure)
      "count"
  """
  @spec name_string(t()) :: String.t()
  def name_string(%__MODULE__{name: name}) when is_atom(name), do: Atom.to_string(name)
  def name_string(%__MODULE__{name: name}) when is_binary(name), do: name

  @doc """
  Returns a human-readable description of the measure.

  ## Examples

      iex> measure = %MeasureRef{
      ...>   name: :total_revenue,
      ...>   module: Orders,
      ...>   type: :sum,
      ...>   description: "Sum of all revenue"
      ...> }
      iex> MeasureRef.describe(measure)
      "total_revenue (sum): Sum of all revenue"
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{name: name, type: type, description: nil}) do
    "#{name} (#{type})"
  end

  def describe(%__MODULE__{name: name, type: type, description: description}) do
    "#{name} (#{type}): #{description}"
  end

  @doc """
  Validates that the measure reference is well-formed.

  Returns `:ok` if valid, or `{:error, reason}` if invalid.

  ## Examples

      iex> measure = %MeasureRef{name: :count, module: Customer, type: :count}
      iex> MeasureRef.validate(measure)
      :ok

      iex> measure = %MeasureRef{name: nil, module: Customer, type: :count}
      iex> MeasureRef.validate(measure)
      {:error, "name cannot be nil"}
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{name: nil}), do: {:error, "name cannot be nil"}
  def validate(%__MODULE__{module: nil}), do: {:error, "module cannot be nil"}
  def validate(%__MODULE__{type: nil}), do: {:error, "type cannot be nil"}

  def validate(%__MODULE__{type: type}) do
    valid_types = [
      :count,
      :count_distinct,
      :count_distinct_approx,
      :sum,
      :avg,
      :min,
      :max,
      :number,
      :string,
      :time,
      :boolean
    ]

    if type in valid_types do
      :ok
    else
      {:error, "invalid measure type: #{inspect(type)}"}
    end
  end
end
