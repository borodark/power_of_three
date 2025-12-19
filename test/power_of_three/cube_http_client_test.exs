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
        "dimensions" => ["of_customers.brand"],
        "measures" => ["of_customers.count"],
        "limit" => 3
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      assert is_map(result)
      assert Map.has_key?(result, "of_customers.brand")
      assert Map.has_key?(result, "of_customers.count")

      # Data should be in columnar format
      assert is_list(result["of_customers.brand"])
      assert is_list(result["of_customers.count"])

      # Counts should be converted to integers
      assert Enum.all?(result["of_customers.count"], &is_integer/1)
    end

    test "executes query with filters", %{client: client} do
      cube_query = %{
        "dimensions" => ["of_customers.brand"],
        "measures" => ["of_customers.count"],
        "filters" => [
          %{
            "member" => "of_customers.brand",
            "operator" => "equals",
            "values" => ["BudLight"]
          }
        ],
        "limit" => 5
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      brands = result["of_customers.brand"]

      assert is_list(brands)
      assert Enum.all?(brands, &(&1 == "BudLight"))
    end

    test "executes query with ordering", %{client: client} do
      cube_query = %{
        "dimensions" => ["of_customers.brand"],
        "measures" => ["of_customers.count"],
        "order" => [["of_customers.count", "desc"]],
        "limit" => 5
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      counts = result["of_customers.count"]

      assert is_list(counts)
      # Should be in descending order
      assert counts == Enum.sort(counts, :desc)
    end

    test "handles empty result set", %{client: client} do
      cube_query = %{
        "dimensions" => ["of_customers.brand"],
        "measures" => ["of_customers.count"],
        "filters" => [
          %{
            "member" => "of_customers.brand",
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
        "dimensions" => ["of_customers.brand"],
        "measures" => ["of_customers.count"]
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
        "dimensions" => ["of_customers.brand"],
        "measures" => ["of_customers.count"],
        "limit" => 3
      }

      result = CubeHttpClient.query!(client, cube_query)

      # Should return map directly, not tuple
      assert is_map(result)
      assert Map.has_key?(result, "of_customers.brand")
    end

    test "raises on error" do
      {:ok, client} = CubeHttpClient.new(base_url: "http://localhost:9999")

      cube_query = %{
        "dimensions" => ["of_customers.brand"],
        "measures" => ["of_customers.count"]
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
        "measures" => ["of_customers.count"],
        "limit" => 1
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      counts = result["of_customers.count"]

      assert is_list(counts)
      assert Enum.all?(counts, &is_integer/1)
    end

    test "keeps string dimensions as strings", %{client: client} do
      cube_query = %{
        "dimensions" => ["of_customers.brand"],
        "measures" => ["of_customers.count"],
        "limit" => 1
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      brands = result["of_customers.brand"]

      assert is_list(brands)
      assert Enum.all?(brands, &is_binary/1)
    end

    test "converts number dimensions to integers", %{client: client} do
      cube_query = %{
        "dimensions" => ["of_customers.star_sector"],
        "measures" => ["of_customers.count"],
        "limit" => 5
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      star_sectors = result["of_customers.star_sector"]

      assert is_list(star_sectors)
      # Should be numbers (0-11 or -1)
      assert Enum.all?(star_sectors, &is_integer/1)
    end
  end

  describe "response transformation" do
    setup do
      {:ok, client} = CubeHttpClient.new(base_url: "http://localhost:4008")
      {:ok, client: client}
    end

    test "transforms row-oriented data to columnar format", %{client: client} do
      cube_query = %{
        "dimensions" => ["of_customers.brand", "of_customers.market"],
        "measures" => ["of_customers.count"],
        "limit" => 3
      }

      {:ok, result} = CubeHttpClient.query(client, cube_query)

      # Should have 3 keys (2 dimensions + 1 measure)
      assert map_size(result) == 3

      # All columns should have same length
      brands = result["of_customers.brand"]
      markets = result["of_customers.market"]
      counts = result["of_customers.count"]

      assert length(brands) == length(markets)
      assert length(markets) == length(counts)
    end
  end
end
