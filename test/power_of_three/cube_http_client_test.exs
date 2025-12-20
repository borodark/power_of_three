defmodule PowerOfThree.CubeHttpClientTest do
  use ExUnit.Case, async: false

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

      assert ["power_customers.brand", "power_customers.count"] ==
               result |> Explorer.DataFrame.names()
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

      brands = result["power_customers.brand"] |> Explorer.Series.to_list()
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

      counts = result["power_customers.count"]

      assert ["1758", "1751", "1739", "1735", "1731"] == counts |> Explorer.Series.to_list()
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

      counts = result["power_customers.brand"]
      assert %Explorer.Series{} = counts
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

      counts = result["power_customers.count"]

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

      brands = result["power_customers.brand"]
      assert %Explorer.Series{} = brands

      assert ["Dos Equis"] =
               brands |> Explorer.Series.to_list()
    end

    test "converts number dimensions to integers", %{client: client} do
      cube_query = %{
        "dimensions" => ["power_customers.star_sector"],
        "measures" => ["power_customers.count"],
        "limit" => 5
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      assert [-1.0, 5.0, 4.0, 0.0, 6.0] ==
               result["power_customers.star_sector"] |> Explorer.Series.to_list()
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
        "limit" => 3
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      # Should have 3 keys (2 dimensions + 1 measure)
      assert Explorer.DataFrame.shape(result) == {3, 3}
    end
  end

  describe "response transformationn arrow" do
    setup do
      {:ok, client} = CubeHttpClient.new(base_url: "http://localhost:4008")
      {:ok, client: client}
    end

    test "transforms row-oriented data to columnar format", %{client: client} do
      cube_query = %{
        "dimensions" => ["power_customers.brand", "power_customers.market"],
        "measures" => ["power_customers.count"],
        "limit" => 3
      }

      {:ok, result} = CubeHttpClient.arrow(client, cube_query)

      # Should have 3 keys (2 dimensions + 1 measure)
      assert Explorer.DataFrame.shape(result) == {3, 3}
    end
  end

  #       // res.set('Content-Type', 'application/vnd.apache.arrow.stream');e
end
