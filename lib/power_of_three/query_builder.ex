defmodule PowerOfThree.QueryBuilder do
  @moduledoc """
  Builds Cube SQL queries from MeasureRef and DimensionRef structs.

  ## Examples

      # Build a simple query
      query = QueryBuilder.build(
        cube: "customer",
        columns: [
          %DimensionRef{name: :email, ...},
          %MeasureRef{name: :count, ...}
        ]
      )
      # => "SELECT customer.email, MEASURE(customer.count) FROM customer GROUP BY 1"

      # Build with filters and ordering
      query = QueryBuilder.build(
        cube: "customer",
        columns: [dimension_ref, measure_ref],
        where: "brand_code = 'NIKE'",
        order_by: [{1, :asc}],
        limit: 10
      )
  """

  alias PowerOfThree.{MeasureRef, DimensionRef}

  @type column_ref :: MeasureRef.t() | DimensionRef.t()
  @type order_direction :: :asc | :desc
  @type order_spec :: {pos_integer(), order_direction()} | pos_integer()

  @type build_opts :: [
          cube: String.t() | atom(),
          columns: [column_ref()],
          where: String.t() | nil,
          order_by: [order_spec()] | nil,
          limit: pos_integer() | nil,
          offset: non_neg_integer() | nil
        ]

  @doc """
  Builds a Cube SQL query from column references and options.

  ## Options

    * `:cube` - Required. The cube name (string or atom)
    * `:columns` - Required. List of MeasureRef and/or DimensionRef structs
    * `:where` - Optional. SQL WHERE clause (without "WHERE" keyword)
    * `:order_by` - Optional. List of {column_index, :asc | :desc} or just column_index
    * `:limit` - Optional. Maximum number of rows to return
    * `:offset` - Optional. Number of rows to skip

  ## Examples

      QueryBuilder.build(
        cube: "customer",
        columns: [
          %DimensionRef{name: :brand, module: Customer, type: :string, sql: "brand_code"},
          %MeasureRef{name: :count, module: Customer, type: :count}
        ]
      )
      # => "SELECT customer.brand, MEASURE(customer.count) FROM customer GROUP BY 1"

      QueryBuilder.build(
        cube: :customer,
        columns: [dimension, measure],
        where: "brand_code = 'NIKE'",
        order_by: [{2, :desc}],
        limit: 10,
        offset: 5
      )
  """
  @spec build(build_opts()) :: String.t()
  def build(opts) do
    cube = Keyword.fetch!(opts, :cube) |> to_string()
    columns = Keyword.fetch!(opts, :columns)
    where = Keyword.get(opts, :where)
    order_by = Keyword.get(opts, :order_by)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset)

    validate_columns!(columns)

    select_clause = build_select_clause(cube, columns)
    from_clause = "FROM #{cube}"
    group_by_clause = build_group_by_clause(columns)
    where_clause = if where, do: "WHERE #{where}", else: nil
    order_by_clause = if order_by, do: build_order_by_clause(order_by), else: nil
    limit_clause = if limit, do: "LIMIT #{limit}", else: nil
    offset_clause = if offset, do: "OFFSET #{offset}", else: nil

    [
      select_clause,
      from_clause,
      group_by_clause,
      where_clause,
      order_by_clause,
      limit_clause,
      offset_clause
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  @doc """
  Validates that all columns are either MeasureRef or DimensionRef structs.

  Raises ArgumentError if validation fails.
  """
  @spec validate_columns!([column_ref()]) :: :ok
  def validate_columns!([]), do: raise(ArgumentError, "columns cannot be empty")

  def validate_columns!(columns) when is_list(columns) do
    Enum.each(columns, fn col ->
      unless match?(%MeasureRef{}, col) or match?(%DimensionRef{}, col) do
        raise ArgumentError,
              "Expected MeasureRef or DimensionRef, got: #{inspect(col)}"
      end
    end)

    :ok
  end

  def validate_columns!(_), do: raise(ArgumentError, "columns must be a list")

  @doc """
  Builds the SELECT clause with dimension and measure references.

  ## Examples

      iex> build_select_clause("customer", [dimension, measure])
      "SELECT customer.email, MEASURE(customer.count)"
  """
  @spec build_select_clause(String.t(), [column_ref()]) :: String.t()
  def build_select_clause(cube, columns) do
    select_items =
      Enum.map(columns, fn
        %DimensionRef{name: name} ->
          "#{cube}.#{name}"

        %MeasureRef{name: name} ->
          "MEASURE(#{cube}.#{name})"
      end)

    "SELECT " <> Enum.join(select_items, ", ")
  end

  @doc """
  Builds the GROUP BY clause with column indices.

  Only includes dimensions (measures are aggregated).

  ## Examples

      iex> build_group_by_clause([dimension1, measure1, dimension2])
      "GROUP BY 1, 3"
  """
  @spec build_group_by_clause([column_ref()]) :: String.t() | nil
  def build_group_by_clause(columns) do
    dimension_indices =
      columns
      |> Enum.with_index(1)
      |> Enum.filter(fn {col, _idx} -> match?(%DimensionRef{}, col) end)
      |> Enum.map(fn {_col, idx} -> idx end)

    case dimension_indices do
      [] -> nil
      indices -> "GROUP BY " <> Enum.join(indices, ", ")
    end
  end

  @doc """
  Builds the ORDER BY clause from order specifications.

  ## Examples

      iex> build_order_by_clause([{1, :asc}, {2, :desc}])
      "ORDER BY 1 ASC, 2 DESC"

      iex> build_order_by_clause([1, 2])
      "ORDER BY 1, 2"
  """
  @spec build_order_by_clause([order_spec()]) :: String.t()
  def build_order_by_clause(order_specs) do
    order_items =
      Enum.map(order_specs, fn
        {index, :asc} -> "#{index} ASC"
        {index, :desc} -> "#{index} DESC"
        index when is_integer(index) -> "#{index}"
      end)

    "ORDER BY " <> Enum.join(order_items, ", ")
  end

  @doc """
  Extracts the cube name from a list of column references.

  All columns must belong to the same cube (same module).

  ## Examples

      iex> extract_cube_name([
      ...>   %DimensionRef{module: Customer, ...},
      ...>   %MeasureRef{module: Customer, ...}
      ...> ])
      "customer"
  """
  @spec extract_cube_name([column_ref()]) :: String.t()
  def extract_cube_name([]), do: raise(ArgumentError, "columns cannot be empty")

  def extract_cube_name(columns) do
    [first | rest] = columns
    first_module = get_module(first)
    first_cube = extract_module_cube_name(first_module)

    # Validate all columns are from the same cube
    Enum.each(rest, fn col ->
      col_module = get_module(col)
      col_cube = extract_module_cube_name(col_module)

      if col_cube != first_cube do
        raise ArgumentError,
              "All columns must be from the same cube. Found #{first_cube} and #{col_cube}"
      end
    end)

    first_cube
  end

  defp get_module(%MeasureRef{module: module}), do: module
  defp get_module(%DimensionRef{module: module}), do: module

  defp extract_module_cube_name(module) do
    module.__schema__(:source)
  end
end
