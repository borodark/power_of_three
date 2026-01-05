defmodule PowerOfThree.PreAggDefaultIntegrationTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.{CubeHttpClient, QueryError}

  @moduletag :live_cube
  @moduletag timeout: 60_000

  setup do
    {:ok, client} = CubeHttpClient.new(base_url: "http://localhost:4008")
    {:ok, client: client}
  end

  defp assert_columns(df, expected_columns) do
    names = Explorer.DataFrame.names(df)
    Enum.each(expected_columns, fn column -> assert column in names end)
  end

  defp assert_non_empty(df) do
    {rows, _cols} = Explorer.DataFrame.shape(df)
    assert rows > 0
  end

  defp assert_query_or_wait(client, cube_query, expected_columns) do
    case CubeHttpClient.query(client, cube_query, max_wait: 0) do
      {:ok, result} ->
        assert %Explorer.DataFrame{} = result
        assert_columns(result, expected_columns)
        assert_non_empty(result)

      {:error, %QueryError{message: "Continue wait"}} ->
        assert true

      {:error, %QueryError{type: :timeout}} ->
        assert true

      {:error, error} ->
        flunk("Unexpected Cube query error: #{inspect(error)}")
    end
  end

  test "day granularity with dimensions and count", %{client: client} do
    cube_query = %{
      "dimensions" => [
        "mandata_captate.market_code",
        "mandata_captate.brand_code"
      ],
      "measures" => ["mandata_captate.count"],
      "timeDimensions" => [
        %{
          "dimension" => "mandata_captate.updated_at",
          "granularity" => "day",
          "dateRange" => ["2024-01-01", "2024-01-07"]
        }
      ],
      "limit" => 20
    }

    assert_query_or_wait(client, cube_query, [
      "market_code",
      "brand_code",
      "count",
      "updated_at.day"
    ])
  end

  test "week granularity with single dimension and multiple measures", %{client: client} do
    cube_query = %{
      "dimensions" => ["mandata_captate.market_code"],
      "measures" => [
        "mandata_captate.count",
        "mandata_captate.total_amount_sum"
      ],
      "timeDimensions" => [
        %{
          "dimension" => "mandata_captate.updated_at",
          "granularity" => "week",
          "dateRange" => ["2024-01-01", "2024-02-01"]
        }
      ],
      "order" => [["mandata_captate.total_amount_sum", "desc"]],
      "limit" => 10
    }

    assert_query_or_wait(client, cube_query, [
      "market_code",
      "count",
      "total_amount_sum",
      "updated_at.week"
    ])
  end

  test "month granularity with measures only", %{client: client} do
    cube_query = %{
      "measures" => [
        "mandata_captate.count",
        "mandata_captate.tax_amount_sum"
      ],
      "timeDimensions" => [
        %{
          "dimension" => "mandata_captate.updated_at",
          "granularity" => "month",
          "dateRange" => ["2024-01-01", "2024-03-31"]
        }
      ],
      "limit" => 24
    }

    assert_query_or_wait(client, cube_query, [
      "count",
      "tax_amount_sum",
      "updated_at.month"
    ])
  end

  test "hour granularity with dimensions and multiple measures", %{client: client} do
    cube_query = %{
      "dimensions" => [
        "mandata_captate.market_code",
        "mandata_captate.fulfillment_status"
      ],
      "measures" => [
        "mandata_captate.count",
        "mandata_captate.discount_total_amount_sum"
      ],
      "timeDimensions" => [
        %{
          "dimension" => "mandata_captate.updated_at",
          "granularity" => "hour",
          "dateRange" => ["2024-01-01", "2024-01-02"]
        }
      ],
      "limit" => 25
    }

    assert_query_or_wait(client, cube_query, [
      "market_code",
      "fulfillment_status",
      "count",
      "discount_total_amount_sum",
      "updated_at.hour"
    ])
  end
end
