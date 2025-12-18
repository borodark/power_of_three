defmodule PowerOfThree.DimensionRef do
  @moduledoc """
  Represents a reference to a cube dimension.

  Used in dot-accessible collections like `Customer.dimensions.email`

  ## Fields

    * `:name` - The dimension name (atom or string)
    * `:module` - The module where this dimension is defined
    * `:type` - The dimension type (`:string`, `:number`, `:time`, `:boolean`)
    * `:sql` - The SQL expression or column reference
    * `:meta` - Metadata map containing ecto field information
    * `:description` - Optional description of the dimension
    * `:primary_key` - Whether this dimension is part of the primary key
    * `:format` - Optional format specification

  ## Examples

      # Reference created by generated accessor
      dimension_ref = Customer.dimensions.email()
      %DimensionRef{
        name: :email,
        module: Customer,
        type: :string,
        sql: "email",
        ...
      }

      # Convert to SQL column expression
      DimensionRef.to_sql_column(dimension_ref)
      # => "customer.email"
  """

  @enforce_keys [:name, :module, :type]
  defstruct [
    :name,
    :module,
    :type,
    :sql,
    :meta,
    :description,
    :primary_key,
    :format,
    :propagate_filters_to_sub_query,
    :public
  ]

  @type dimension_type :: :string | :number | :time | :boolean | :geo

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          module: module(),
          type: dimension_type(),
          sql: String.t(),
          meta: map() | nil,
          description: String.t() | nil,
          primary_key: boolean(),
          format: atom() | nil,
          propagate_filters_to_sub_query: boolean() | nil,
          public: boolean() | nil
        }

  @doc """
  Converts a dimension reference to a SQL column expression.

  Returns the qualified column name used by Cube SQL.

  ## Examples

      iex> dimension = %DimensionRef{name: :email, module: Customer, type: :string, sql: "email"}
      iex> DimensionRef.to_sql_column(dimension)
      "customer.email"

      iex> dimension = %DimensionRef{name: "brand_code", module: Customer, type: :string, sql: "brand_code"}
      iex> DimensionRef.to_sql_column(dimension)
      "customer.brand_code"
  """
  @spec to_sql_column(t()) :: String.t()
  def to_sql_column(%__MODULE__{module: module, name: name}) do
    cube_name = extract_cube_name(module)
    dimension_name = to_string(name)
    "#{cube_name}.#{dimension_name}"
  end

  @doc """
  Returns the cube name from the module.

  Uses the Ecto schema source as the cube name.

  ## Examples

      iex> DimensionRef.extract_cube_name(Customer)
      "customer"
  """
  @spec extract_cube_name(module()) :: String.t()
  def extract_cube_name(module) do
    module.__schema__(:source)
  end

  @doc """
  Returns the dimension name as a string.

  ## Examples

      iex> dimension = %DimensionRef{name: :email, module: Customer, type: :string, sql: "email"}
      iex> DimensionRef.name_string(dimension)
      "email"
  """
  @spec name_string(t()) :: String.t()
  def name_string(%__MODULE__{name: name}) when is_atom(name), do: Atom.to_string(name)
  def name_string(%__MODULE__{name: name}) when is_binary(name), do: name

  @doc """
  Returns a human-readable description of the dimension.

  ## Examples

      iex> dimension = %DimensionRef{
      ...>   name: :email,
      ...>   module: Customer,
      ...>   type: :string,
      ...>   sql: "email",
      ...>   description: "Customer email address"
      ...> }
      iex> DimensionRef.describe(dimension)
      "email (string): Customer email address"
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{name: name, type: type, description: nil}) do
    "#{name} (#{type})"
  end

  def describe(%__MODULE__{name: name, type: type, description: description}) do
    "#{name} (#{type}): #{description}"
  end

  @doc """
  Validates that the dimension reference is well-formed.

  Returns `:ok` if valid, or `{:error, reason}` if invalid.

  ## Examples

      iex> dimension = %DimensionRef{name: :email, module: Customer, type: :string, sql: "email"}
      iex> DimensionRef.validate(dimension)
      :ok

      iex> dimension = %DimensionRef{name: nil, module: Customer, type: :string, sql: "email"}
      iex> DimensionRef.validate(dimension)
      {:error, "name cannot be nil"}
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{name: nil}), do: {:error, "name cannot be nil"}
  def validate(%__MODULE__{module: nil}), do: {:error, "module cannot be nil"}
  def validate(%__MODULE__{type: nil}), do: {:error, "type cannot be nil"}
  def validate(%__MODULE__{sql: nil}), do: {:error, "sql cannot be nil"}

  def validate(%__MODULE__{type: type}) do
    valid_types = [:string, :number, :time, :boolean, :geo]

    if type in valid_types do
      :ok
    else
      {:error, "invalid dimension type: #{inspect(type)}"}
    end
  end

  @doc """
  Checks if this dimension is a primary key.

  ## Examples

      iex> dimension = %DimensionRef{
      ...>   name: :id,
      ...>   module: Customer,
      ...>   type: :number,
      ...>   sql: "id",
      ...>   primary_key: true
      ...> }
      iex> DimensionRef.primary_key?(dimension)
      true
  """
  @spec primary_key?(t()) :: boolean()
  def primary_key?(%__MODULE__{primary_key: true}), do: true
  def primary_key?(%__MODULE__{}), do: false

  @doc """
  Returns the SQL expression for this dimension.

  Handles both simple column names and complex SQL expressions.

  ## Examples

      iex> dimension = %DimensionRef{
      ...>   name: :email,
      ...>   module: Customer,
      ...>   type: :string,
      ...>   sql: "email"
      ...> }
      iex> DimensionRef.sql_expression(dimension)
      "email"

      iex> dimension = %DimensionRef{
      ...>   name: :full_name,
      ...>   module: Customer,
      ...>   type: :string,
      ...>   sql: "first_name || ' ' || last_name"
      ...> }
      iex> DimensionRef.sql_expression(dimension)
      "first_name || ' ' || last_name"
  """
  @spec sql_expression(t()) :: String.t()
  def sql_expression(%__MODULE__{sql: sql}) when is_binary(sql), do: sql
  def sql_expression(%__MODULE__{sql: sql}) when is_atom(sql), do: Atom.to_string(sql)
end
