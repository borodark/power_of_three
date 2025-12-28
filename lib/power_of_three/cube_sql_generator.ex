defmodule PowerOfThree.CubeSqlGenerator do
  @moduledoc """
  Generates SQL queries for ADBC execution that reference cube names.

  This module generates simple SQL that:
  1. References cube names (not pre-aggregation tables)
  2. Is sent to Cube's ADBC server (cubesql)
  3. Gets compiled and matched to pre-aggregations by cubesql
  4. Routes through HybridTransport to CubeStore for external pre-aggregations

  ## How It Works

  The ADBC server (cubesql) internally:
  - Parses the SQL we send
  - Converts it to a Cube query plan via `convert_sql_to_cube_query()`
  - Matches it to pre-aggregations (if `external: true` is configured)
  - Routes to CubeStore for pre-aggregated queries
  - Routes to HTTP for non-pre-aggregated queries

  ## Example

      # We generate:
      SELECT market_code, COUNT(*) as count
      FROM mandata_captate
      GROUP BY market_code
      LIMIT 5

      # cubesql internally matches this to:
      # - Pre-aggregation: mandata_captate.sums_and_count_daily (if external: true)
      # - Routes to: dev_pre_aggregations.mandata_captate_sums_and_count_daily
      # - Executes via: CubeStoreTransport

  ## Important Notes

  - Cubes must have `external: true` pre-aggregations for CubeStore routing
  - WHERE clause support is provided by delegating to `CubeQueryTranslator`
  - The generated SQL is simple and parseable by cubesql's SQL compiler
  - Pre-aggregation matching happens server-side (not client-side)
  """

  alias PowerOfThree.{CubeQueryTranslator, DimensionRef, MeasureRef, FilterBuilder}

  @doc """
  Generates SQL that references cube names for ADBC execution.

  The SQL is simple and parseable by cubesql, which will internally compile
  it and match it to pre-aggregations.

  ## Arguments

    * `query_opts` - PowerOfThree query options (columns, where, limit, etc.)
    * `_cube_opts` - Unused (kept for API compatibility)

  ## Examples

      {:ok, sql} = CubeSqlGenerator.generate_sql(
        [
          columns: [Order.Dimensions.market_code(), Order.Measures.count()],
          where: "market_code = 'US'",
          limit: 10
        ]
      )
      # Returns: "SELECT market_code, COUNT(*) as count FROM mandata_captate WHERE market_code = 'US' GROUP BY market_code LIMIT 10"
  """
  @spec generate_sql(keyword(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_sql(query_opts, _cube_opts \\ []) do
    with {:ok, cube_name} <- extract_cube_name(query_opts),
         {:ok, columns} <- extract_columns(query_opts),
         {:ok, select_clause} <- build_select_clause(columns),
         {:ok, group_by_clause} <- build_group_by_clause(columns) do
      sql_parts = [
        "SELECT",
        select_clause,
        "FROM",
        cube_name
      ]

      # Add WHERE clause if present (supports typed filters only)
      sql_parts =
        case FilterBuilder.to_sql(Keyword.get(query_opts, :where)) do
          {:ok, ""} -> sql_parts
          {:ok, where_sql} -> sql_parts ++ ["WHERE", where_sql]
          {:error, reason} -> throw({:error, reason})
        end

      # Add GROUP BY if we have dimensions
      sql_parts =
        if group_by_clause != "" do
          sql_parts ++ ["GROUP BY", group_by_clause]
        else
          sql_parts
        end

      # Add ORDER BY if present
      order_result = build_order_by_clause(query_opts, columns)

      sql_parts =
        case order_result do
          {:ok, ""} ->
            sql_parts

          {:ok, order_clause} ->
            sql_parts ++ ["ORDER BY", order_clause]

          {:error, _} = err ->
            # Early return on error
            throw(err)
        end

      # Add LIMIT if present
      sql_parts =
        case Keyword.get(query_opts, :limit) do
          nil -> sql_parts
          limit -> sql_parts ++ ["LIMIT", to_string(limit)]
        end

      # Add OFFSET if present
      sql_parts =
        case Keyword.get(query_opts, :offset) do
          nil -> sql_parts
          offset -> sql_parts ++ ["OFFSET", to_string(offset)]
        end

      sql = Enum.join(sql_parts, " ")
      {:ok, sql}
    end
  rescue
    error -> {:error, error}
  end

  # Private helper functions

  defp extract_cube_name(query_opts) do
    case Keyword.get(query_opts, :columns, []) do
      [] ->
        {:error, "No columns provided"}

      columns ->
        # Get cube name from first column
        first_col = List.first(columns)
        cube_name = get_cube_name_from_column(first_col)

        if cube_name do
          {:ok, cube_name}
        else
          {:error, "Could not extract cube name"}
        end
    end
  end

  defp get_cube_name_from_column(col) do
    cond do
      is_struct(col, DimensionRef) ->
        extract_cube_name_from_module(col.module)

      is_struct(col, MeasureRef) ->
        extract_cube_name_from_module(col.module)

      is_tuple(col) ->
        # Column alias format: {alias, ref}
        {_alias, ref} = col
        get_cube_name_from_column(ref)

      true ->
        nil
    end
  end

  defp extract_cube_name_from_module(module) do
    module.__info__(:attributes)[:cube_config]
    |> List.first()
    |> Map.get(:name)
    |> to_string()
  end

  defp extract_columns(query_opts) do
    case Keyword.get(query_opts, :columns, []) do
      [] -> {:error, "No columns provided"}
      columns -> {:ok, columns}
    end
  end

  defp build_select_clause(columns) do
    # Handle both plain list and keyword list (with aliases)
    select_items =
      Enum.map(columns, fn col ->
        case col do
          {alias, ref} ->
            # Column with alias
            sql_expr = get_column_sql(ref)
            "#{sql_expr} as #{alias}"

          ref ->
            # Regular column
            sql_expr = get_column_sql(ref)
            name = get_column_name(ref)
            "#{sql_expr} as #{name}"
        end
      end)

    {:ok, Enum.join(select_items, ", ")}
  end

  defp get_column_sql(%DimensionRef{sql: sql}), do: sql
  defp get_column_sql(%MeasureRef{type: :count}), do: "COUNT(*)"
  defp get_column_sql(%MeasureRef{type: :sum, sql: sql}), do: "SUM(#{sql})"
  defp get_column_sql(%MeasureRef{type: :avg, sql: sql}), do: "AVG(#{sql})"
  defp get_column_sql(%MeasureRef{type: :min, sql: sql}), do: "MIN(#{sql})"
  defp get_column_sql(%MeasureRef{type: :max, sql: sql}), do: "MAX(#{sql})"
  defp get_column_sql(%MeasureRef{type: :count_distinct, sql: sql}), do: "COUNT(DISTINCT #{sql})"
  defp get_column_sql(%MeasureRef{sql: sql}), do: sql

  defp get_column_name(%DimensionRef{name: name}), do: to_string(name)
  defp get_column_name(%MeasureRef{name: name}), do: to_string(name)

  defp build_group_by_clause(columns) do
    # Extract dimensions for GROUP BY
    dimensions =
      Enum.filter(columns, fn col ->
        case col do
          {_alias, ref} -> is_struct(ref, DimensionRef)
          ref -> is_struct(ref, DimensionRef)
        end
      end)

    if Enum.empty?(dimensions) do
      {:ok, ""}
    else
      group_by_items =
        Enum.map(dimensions, fn col ->
          case col do
            {_alias, ref} -> get_column_name(ref)
            ref -> get_column_name(ref)
          end
        end)

      {:ok, Enum.join(group_by_items, ", ")}
    end
  end

  defp build_order_by_clause(query_opts, columns) do
    case Keyword.get(query_opts, :order_by) do
      nil ->
        {:ok, ""}

      [] ->
        {:ok, ""}

      order_specs ->
        order_items =
          Enum.map(order_specs, fn
            {col_idx, direction} when is_integer(col_idx) ->
              # Get column by index (1-based)
              col = Enum.at(columns, col_idx - 1)

              col_name =
                case col do
                  {alias, _ref} -> to_string(alias)
                  ref -> get_column_name(ref)
                end

              "#{col_name} #{direction |> to_string() |> String.upcase()}"

            col_idx when is_integer(col_idx) ->
              # Default to ASC
              col = Enum.at(columns, col_idx - 1)

              col_name =
                case col do
                  {alias, _ref} -> to_string(alias)
                  ref -> get_column_name(ref)
                end

              "#{col_name} ASC"
          end)

        {:ok, Enum.join(order_items, ", ")}
    end
  rescue
    error -> {:error, error}
  end

  @doc """
  Converts PowerOfThree query options to Cube REST API query format.

  ## Examples

      {:ok, cube_query} = CubeSqlGenerator.to_cube_query([
        columns: [
          %DimensionRef{name: :market_code, module: Order},
          %MeasureRef{name: :count, module: Order}
        ],
        limit: 5
      ])

      # Returns:
      # %{
      #   "dimensions" => ["orders_no_preagg.market_code"],
      #   "measures" => ["orders_no_preagg.count"],
      #   "limit" => 5
      # }
  """
  @spec to_cube_query(keyword()) :: {:ok, map()} | {:error, term()}
  def to_cube_query(query_opts) do
    # Delegate to CubeQueryTranslator which has full WHERE clause parsing support
    CubeQueryTranslator.to_cube_query(query_opts)
  end
end
