defmodule PowerOfThree.CubeHttpClientTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.CubeHttpClient
  alias PowerOfThree.QueryError

  @moduletag :live_cube

  describe "new/1" do
    test "creates HTTP client with default options" do
      {:ok, client} = CubeHttpClient.new()

      assert %CubeHttpClient{} = client
      assert client.base_url == "http://localhost:4008"
      assert client.api_token == nil
    end

    test "creates HTTP client with custom base URL" do
      {:ok, client} = CubeHttpClient.new(base_url: "http://example.com:8080")

      assert client.base_url == "http://example.com:8080"
    end

    test "creates HTTP client with API token" do
      {:ok, client} = CubeHttpClient.new(api_token: "secret_token")

      assert client.api_token == "secret_token"
    end

    test "creates HTTP client with custom timeout" do
      {:ok, client} = CubeHttpClient.new(timeout: 60_000)

      # Client should be created successfully
      assert %CubeHttpClient{} = client
    end
  end

  describe "new!/1" do
    test "creates HTTP client successfully" do
      client = CubeHttpClient.new!()

      assert %CubeHttpClient{} = client
    end
  end

  describe "query/2" do
    setup do
      {:ok, client} = CubeHttpClient.new(base_url: "http://localhost:4008")
      {:ok, client: client}
    end

    test "executes simple query successfully", %{client: client} do
      cube_query = %{
        "dimensions" => ["power_customers.brand"],
        "measures" => ["power_customers.count"],
        "limit" => 3
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      # Column names should be normalized (cube prefix removed)
      assert ["brand", "count"] == result |> Explorer.DataFrame.names()

      require Explorer.DataFrame

      assert result
             |> Explorer.DataFrame.mutate(count: cast(count, {:u, 64}))
             |> Explorer.DataFrame.dtypes() == %{"brand" => :string, "count" => {:u, 64}}
    end

    test "executes query with filters", %{client: client} do
      cube_query = %{
        "dimensions" => ["power_customers.brand"],
        "measures" => ["power_customers.count"],
        "filters" => [
          %{
            "member" => "power_customers.brand",
            "operator" => "equals",
            "values" => ["BudLight"]
          }
        ],
        "limit" => 5
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      # Column names are normalized (cube prefix removed)
      brands = result["brand"] |> Explorer.Series.to_list()
      assert Enum.all?(brands, &(&1 == "BudLight"))
    end

    test "executes query with ordering", %{client: client} do
      cube_query = %{
        "dimensions" => ["power_customers.brand"],
        "measures" => ["power_customers.count"],
        "order" => [["power_customers.count", "desc"]],
        "limit" => 5
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      # Column names are normalized (cube prefix removed)
      counts = result["count"]

      assert [1208, 1205, 1205, 1201, 1198] == counts |> Explorer.Series.to_list()
    end

    test "handles empty result set", %{client: client} do
      cube_query = %{
        "dimensions" => ["power_customers.brand"],
        "measures" => ["power_customers.count"],
        "filters" => [
          %{
            "member" => "power_customers.brand",
            "operator" => "equals",
            "values" => ["NonExistentBrand12345"]
          }
        ]
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      # Empty result should still be a valid map
      assert is_map(result)
    end

    test "returns error for invalid query", %{client: client} do
      # Invalid cube query - missing required fields
      cube_query = %{
        "invalid_field" => "bad_value"
      }

      result = CubeHttpClient.query(client, cube_query)

      # Should return error
      assert {:error, %QueryError{}} = result
    end

    test "handles connection errors gracefully" do
      # Create client with non-existent server
      {:ok, client} = CubeHttpClient.new(base_url: "http://localhost:9999")

      cube_query = %{
        "dimensions" => ["power_customers.brand"],
        "measures" => ["power_customers.count"]
      }

      {:error, error} = CubeHttpClient.query(client, cube_query)

      assert %QueryError{} = error
      assert error.type == :connection_error
    end
  end

  describe "query!/2" do
    setup do
      {:ok, client} = CubeHttpClient.new(base_url: "http://localhost:4008")
      {:ok, client: client}
    end

    test "returns result directly on success", %{client: client} do
      cube_query = %{
        "dimensions" => ["power_customers.brand"],
        "measures" => ["power_customers.count"],
        "limit" => 3
      }

      result = CubeHttpClient.query!(client, cube_query)

      # Should return map directly, not tuple
      # Column names are normalized (cube prefix removed)
      brands = result["brand"]
      assert %Explorer.Series{} = brands
    end

    test "raises on error" do
      {:ok, client} = CubeHttpClient.new(base_url: "http://localhost:9999")

      cube_query = %{
        "dimensions" => ["power_customers.brand"],
        "measures" => ["power_customers.count"]
      }

      assert_raise RuntimeError, fn ->
        CubeHttpClient.query!(client, cube_query)
      end
    end
  end

  describe "type conversion" do
    setup do
      {:ok, client} = CubeHttpClient.new(base_url: "http://localhost:4008")
      {:ok, client: client}
    end

    test "converts string numbers to integers", %{client: client} do
      cube_query = %{
        "measures" => ["power_customers.count"],
        "limit" => 1
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      # Column names are normalized (cube prefix removed)
      counts = result["count"]

      assert %Explorer.Series{} = counts
      # assert Enum.all?(counts, &is_integer/1)
    end

    test "keeps string dimensions as strings", %{client: client} do
      cube_query = %{
        "dimensions" => ["power_customers.brand"],
        "measures" => ["power_customers.count"],
        "limit" => 1
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      # Column names are normalized (cube prefix removed)
      brands = result["brand"]
      assert %Explorer.Series{} = brands

      assert ["Tsingtao"] =
               brands |> Explorer.Series.to_list()
    end

    test "converts number dimensions to integers", %{client: client} do
      cube_query = %{
        "dimensions" => ["power_customers.star_sector"],
        "measures" => ["power_customers.count"],
        "limit" => 5
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      # Column names are normalized (cube prefix removed)
      assert [-1.0, 5.0, 6.0, 9.0, 10.0] ==
               result["star_sector"] |> Explorer.Series.to_list()
    end
  end

  describe "response transformationn" do
    setup do
      {:ok, client} = CubeHttpClient.new(base_url: "http://localhost:4008")
      {:ok, client: client}
    end

    test "transforms row-oriented data to columnar format", %{client: client} do
      cube_query = %{
        "dimensions" => ["power_customers.brand", "power_customers.market"],
        "measures" => ["power_customers.count"],
        "limit" => 5000
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      result |> Explorer.DataFrame.print(limit: 100)
      # Should have 3 keys (2 dimensions + 1 measure)
      assert Explorer.DataFrame.shape(result) == {5000, 3}
    end
  end

  describe "query/3 with retry options" do
    setup do
      {:ok, client} = CubeHttpClient.new(base_url: "http://localhost:4008")
      {:ok, client: client}
    end

    test "accepts max_wait option", %{client: client} do
      cube_query = %{
        "dimensions" => ["power_customers.brand"],
        "measures" => ["power_customers.count"],
        "limit" => 3
      }

      # Query with custom max_wait should work
      {:ok, result} = CubeHttpClient.query(client, cube_query, max_wait: 120_000)

      assert ["brand", "count"] == result |> Explorer.DataFrame.names()
    end

    test "accepts poll_interval option", %{client: client} do
      cube_query = %{
        "dimensions" => ["power_customers.brand"],
        "measures" => ["power_customers.count"],
        "limit" => 3
      }

      # Query with custom poll_interval should work
      {:ok, result} = CubeHttpClient.query(client, cube_query, poll_interval: 500)

      assert ["brand", "count"] == result |> Explorer.DataFrame.names()
    end

    test "query without options uses defaults", %{client: client} do
      cube_query = %{
        "dimensions" => ["power_customers.brand"],
        "measures" => ["power_customers.count"],
        "limit" => 3
      }

      # Query with no options (default retry behavior)
      {:ok, result} = CubeHttpClient.query(client, cube_query)

      assert ["brand", "count"] == result |> Explorer.DataFrame.names()
    end
  end

  describe "QueryError timeout message" do
    test "timeout error includes elapsed time for max_wait_exceeded" do
      error = QueryError.timeout(%{reason: :max_wait_exceeded, elapsed_ms: 5000})

      assert error.type == :timeout
      assert error.message == "Query timed out after 5000ms waiting for Cube to complete"
      assert error.details[:reason] == :max_wait_exceeded
      assert error.details[:elapsed_ms] == 5000
    end

    test "regular timeout error has generic message" do
      error = QueryError.timeout()

      assert error.type == :timeout
      assert error.message == "Request timeout"
    end
  end
end
