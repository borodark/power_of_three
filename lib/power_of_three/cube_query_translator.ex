defmodule PowerOfThree.CubeQueryTranslator do
  @moduledoc """
  Translates PowerOfThree query options to Cube Query JSON format.

  Converts PowerOfThree query options (dimensions, measures, filters) to the
  Cube REST API JSON query format for HTTP API queries.

  ## Translation Examples

      # Input (PowerOfThree query options):
      [
        cube: "customer",
        columns: [
          %DimensionRef{name: :brand, module: Customer},
          %MeasureRef{name: :count, module: Customer}
        ],
        where: [{Customer.Dimensions.brand(), :==, "NIKE"}],
        order_by: [{2, :desc}],
        limit: 10,
        offset: 5
      ]

      # Output (Cube Query JSON):
      %{
        "dimensions" => ["of_customers.brand"],
        "measures" => ["of_customers.count"],
        "filters" => [
          %{"member" => "of_customers.brand", "operator" => "equals", "values" => ["NIKE"]}
        ],
        "order" => [["of_customers.count", "desc"]],
        "limit" => 10,
        "offset" => 5
      }

  ## WHERE Clause Support

  Supports typed WHERE clauses using DimensionRef and MeasureRef:
  - `:==` (equals)
  - `:!=` (not equals)
  - `:>`, `:>=`, `:<`, `:<=` (comparison operators)
  - `:in`, `:not_in` (set membership)
  - `:like`, `:not_like` (pattern matching)
  - `:is_nil`, `:is_not_nil` (NULL checks)

  All conditions in the WHERE list are combined with AND logic.
  """

  alias PowerOfThree.{DimensionRef, MeasureRef, QueryError, FilterBuilder}

  @doc """
  Translates PowerOfThree query options to Cube Query JSON format.

  ## Parameters

  - `opts` - Keyword list with query options

  ## Required Options

  - `:columns` - List of DimensionRef and MeasureRef structs

  ## Optional Options

  - `:where` - List of typed filter conditions `[{column_ref, operator, value}]`
  - `:order_by` - List of `{column_index, direction}` tuples
  - `:limit` - Maximum number of rows
  - `:offset` - Number of rows to skip

  ## Returns

  - `{:ok, cube_query}` - Map in Cube Query JSON format
  - `{:error, %QueryError{}}` - Translation error

  ## Examples

      iex> opts = [
      ...>   columns: [
      ...>     %DimensionRef{name: :brand, module: Customer},
      ...>     %MeasureRef{name: :count, module: Customer}
      ...>   ],
      ...>   where: [{Customer.Dimensions.brand(), :==, "NIKE"}],
      ...>   limit: 10
      ...> ]
      iex> PowerOfThree.CubeQueryTranslator.to_cube_query(opts)
      {:ok, %{
        "dimensions" => ["of_customers.brand"],
        "measures" => ["of_customers.count"],
        "filters" => [...],
        "limit" => 10
      }}
  """
  def to_cube_query(opts) do
    with {:ok, columns} <- get_required_option(opts, :columns),
         {:ok, {dimensions, measures}} <- extract_dimensions_and_measures(columns),
         {:ok, filters} <- parse_where_clause(Keyword.get(opts, :where), columns),
         {:ok, order} <- translate_order_by(Keyword.get(opts, :order_by), columns) do
      cube_query =
        %{
          "dimensions" => dimensions,
          "measures" => measures
        }
        |> maybe_add_filters(filters)
        |> maybe_add_order(order)
        |> maybe_add_limit(Keyword.get(opts, :limit))
        |> maybe_add_offset(Keyword.get(opts, :offset))

      {:ok, cube_query}
    end
  end

  # Gets a required option or returns error
  defp get_required_option(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, QueryError.translation_error("Missing required option: #{key}")}
    end
  end

  # Extracts dimensions and measures from columns list
  defp extract_dimensions_and_measures(columns) do
    dimensions =
      columns
      |> Enum.filter(&match?(%DimensionRef{}, &1))
      |> Enum.map(&dimension_to_cube_name/1)

    measures =
      columns
      |> Enum.filter(&match?(%MeasureRef{}, &1))
      |> Enum.map(&measure_to_cube_name/1)

    {:ok, {dimensions, measures}}
  rescue
    error ->
      {:error, QueryError.translation_error("Failed to extract columns: #{inspect(error)}")}
  end

  @doc """
  Converts a DimensionRef to Cube dimension name format.

  ## Examples

      iex> dim = %DimensionRef{name: :brand, module: Customer}
      iex> PowerOfThree.CubeQueryTranslator.dimension_to_cube_name(dim)
      "of_customers.brand"
  """
  def dimension_to_cube_name(%DimensionRef{name: name, module: module}) do
    cube_name = extract_cube_name(module)
    "#{cube_name}.#{name}"
  end

  @doc """
  Converts a MeasureRef to Cube measure name format.

  ## Examples

      iex> measure = %MeasureRef{name: :count, module: Customer}
      iex> PowerOfThree.CubeQueryTranslator.measure_to_cube_name(measure)
      "of_customers.count"
  """
  def measure_to_cube_name(%MeasureRef{name: name, module: module}) do
    cube_name = extract_cube_name(module)
    "#{cube_name}.#{name}"
  end

  # Extracts cube name from module schema
  # E.g., Customer module with source "customer" → "of_customers"
  defp extract_cube_name(module) do
    module.__info__(:attributes)[:cube_config]
    |> List.first()
    |> Map.get(:name)
    |> to_string()
  end

  # Parses WHERE clause to Cube filters
  defp parse_where_clause(nil, _columns), do: {:ok, []}
  defp parse_where_clause([], _columns), do: {:ok, []}

  # Typed filter syntax (list of filter conditions)
  defp parse_where_clause(conditions, _columns) when is_list(conditions) do
    FilterBuilder.to_cube_filters(conditions)
  end

  # Translates ORDER BY from column indices to field names
  defp translate_order_by(nil, _columns), do: {:ok, []}
  defp translate_order_by([], _columns), do: {:ok, []}

  defp translate_order_by(order_specs, columns) when is_list(order_specs) do
    order =
      Enum.map(order_specs, fn
        {index, direction} when is_integer(index) ->
          column = Enum.at(columns, index - 1)
          field_name = column_to_cube_name(column)
          [field_name, to_string(direction)]

        index when is_integer(index) ->
          column = Enum.at(columns, index - 1)
          field_name = column_to_cube_name(column)
          [field_name, "asc"]
      end)

    {:ok, order}
  rescue
    error ->
      {:error, QueryError.translation_error("Failed to translate ORDER BY: #{inspect(error)}")}
  end

  # Converts a column ref to Cube name
  defp column_to_cube_name(%DimensionRef{} = dim), do: dimension_to_cube_name(dim)
  defp column_to_cube_name(%MeasureRef{} = measure), do: measure_to_cube_name(measure)

  # Helper functions to conditionally add query parts

  defp maybe_add_filters(query, []), do: query
  defp maybe_add_filters(query, filters), do: Map.put(query, "filters", filters)

  defp maybe_add_order(query, []), do: query
  defp maybe_add_order(query, order), do: Map.put(query, "order", order)

  defp maybe_add_limit(query, nil), do: query
  defp maybe_add_limit(query, limit), do: Map.put(query, "limit", limit)

  defp maybe_add_offset(query, nil), do: query
  defp maybe_add_offset(query, offset), do: Map.put(query, "offset", offset)
end
