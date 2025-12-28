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
        where: "brand_code = 'NIKE'",
        order_by: [{2, :desc}],
        limit: 10,
        offset: 5
      ]

      # Output (Cube Query JSON):
      %{
        "dimensions" => ["of_customers.brand"],
        "measures" => ["of_customers.count"],
        "filters" => [
          %{"member" => "of_customers.brand_code", "operator" => "equals", "values" => ["NIKE"]}
        ],
        "order" => [["of_customers.count", "desc"]],
        "limit" => 10,
        "offset" => 5
      }

  ## Limitations

  Phase 1 supports simple WHERE clauses with basic operators:
  - `=` (equals)
  - `!=` (notEquals)
  - `>`, `>=`, `<`, `<=` (comparison operators)
  - `IN (...)` (set membership)

  Complex WHERE clauses with multiple conditions or subqueries are not
  supported and will return an error. For complex queries, use ADBC instead.
  """

  alias PowerOfThree.{DimensionRef, MeasureRef, QueryError}

  @doc """
  Translates PowerOfThree query options to Cube Query JSON format.

  ## Parameters

  - `opts` - Keyword list with query options

  ## Required Options

  - `:columns` - List of DimensionRef and MeasureRef structs

  ## Optional Options

  - `:where` - SQL WHERE clause (simple expressions only)
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
      ...>   where: "brand_code = 'NIKE'",
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

  # Parses SQL WHERE clause to Cube filters
  defp parse_where_clause(nil, _columns), do: {:ok, []}
  defp parse_where_clause("", _columns), do: {:ok, []}

  defp parse_where_clause(where_sql, columns) when is_binary(where_sql) do
    # Simple WHERE clause parser for common patterns
    # Supports: field = 'value', field != 'value', field > value, field IN (...)

    where_sql = String.trim(where_sql)

    cond do
      # Pattern: field = 'value' or field = value
      Regex.match?(~r/^(\w+)\s*=\s*'([^']+)'$/, where_sql) ->
        parse_equals_filter(where_sql, columns)

      Regex.match?(~r/^(\w+)\s*=\s*(\d+)$/, where_sql) ->
        parse_equals_filter(where_sql, columns)

      # Pattern: field != 'value'
      Regex.match?(~r/^(\w+)\s*!=\s*'([^']+)'$/, where_sql) ->
        parse_not_equals_filter(where_sql, columns)

      # Pattern: field > value, field >= value, etc.
      Regex.match?(~r/^(\w+)\s*(>|>=|<|<=)\s*(\d+)$/, where_sql) ->
        parse_comparison_filter(where_sql, columns)

      # Pattern: field IN ('a', 'b', 'c')
      Regex.match?(~r/^(\w+)\s+IN\s*\(/i, where_sql) ->
        parse_in_filter(where_sql, columns)

      true ->
        {:error,
         QueryError.translation_error(
           "Complex WHERE clause not supported in HTTP mode. " <>
             "Use ADBC or structured filters. WHERE: #{where_sql}"
         )}
    end
  end

  # Parses "field = 'value'" pattern
  defp parse_equals_filter(where_sql, columns) do
    case Regex.run(~r/^(\w+)\s*=\s*'([^']+)'$/, where_sql) do
      [_, field, value] ->
        member = field_to_cube_member(field, columns)
        {:ok, [%{"member" => member, "operator" => "equals", "values" => [value]}]}

      nil ->
        # Try numeric value
        case Regex.run(~r/^(\w+)\s*=\s*(\d+)$/, where_sql) do
          [_, field, value] ->
            member = field_to_cube_member(field, columns)
            {:ok, [%{"member" => member, "operator" => "equals", "values" => [value]}]}

          nil ->
            {:error, QueryError.translation_error("Failed to parse WHERE clause: #{where_sql}")}
        end
    end
  end

  # Parses "field != 'value'" pattern
  defp parse_not_equals_filter(where_sql, _columns) do
    case Regex.run(~r/^(\w+)\s*!=\s*'([^']+)'$/, where_sql) do
      [_, field, value] ->
        {:ok, [%{"member" => field, "operator" => "notEquals", "values" => [value]}]}

      nil ->
        {:error, QueryError.translation_error("Failed to parse WHERE clause: #{where_sql}")}
    end
  end

  # Parses "field > value" patterns
  defp parse_comparison_filter(where_sql, _columns) do
    case Regex.run(~r/^(\w+)\s*(>|>=|<|<=)\s*(\d+)$/, where_sql) do
      [_, field, operator, value] ->
        cube_operator =
          case operator do
            ">" -> "gt"
            ">=" -> "gte"
            "<" -> "lt"
            "<=" -> "lte"
          end

        {:ok, [%{"member" => field, "operator" => cube_operator, "values" => [value]}]}

      nil ->
        {:error, QueryError.translation_error("Failed to parse WHERE clause: #{where_sql}")}
    end
  end

  # Parses "field IN ('a', 'b', 'c')" pattern
  defp parse_in_filter(where_sql, _columns) do
    case Regex.run(~r/^(\w+)\s+IN\s*\(([^)]+)\)/i, where_sql) do
      [_, field, values_str] ->
        values =
          values_str
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.map(&String.trim(&1, "'\""))

        {:ok, [%{"member" => field, "operator" => "set", "values" => values}]}

      nil ->
        {:error, QueryError.translation_error("Failed to parse WHERE clause: #{where_sql}")}
    end
  end

  # Converts a field name to Cube member format
  # Tries to find matching dimension/measure in columns list by SQL field name
  defp field_to_cube_member(field, columns) do
    # First, try to find a dimension/measure that uses this SQL field
    found =
      Enum.find(columns, fn
        %DimensionRef{sql: ^field} -> true
        %DimensionRef{meta: %{ecto_field: ecto_field}} -> to_string(ecto_field) == field
        %MeasureRef{sql: sql} when is_binary(sql) -> sql == field
        %MeasureRef{meta: %{ecto_field: ecto_field}} -> to_string(ecto_field) == field
        _ -> false
      end)

    case found do
      %DimensionRef{} = dim ->
        dimension_to_cube_name(dim)

      %MeasureRef{} = measure ->
        measure_to_cube_name(measure)

      nil ->
        # If not found, try to construct cube member from first column's cube name
        case List.first(columns) do
          %DimensionRef{module: module} ->
            cube_name = extract_cube_name(module)
            "#{cube_name}.#{field}"

          %MeasureRef{module: module} ->
            cube_name = extract_cube_name(module)
            "#{cube_name}.#{field}"

          _ ->
            field
        end
    end
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
