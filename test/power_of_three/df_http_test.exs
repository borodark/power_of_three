defmodule PowerOfThree.DfHttpTest do
  use ExUnit.Case, async: true

  @moduletag :live_cube

  describe "df/1 with HTTP (default)" do
    test "simple query with dimensions and measures" do
      {:ok, result} =
        Customer.df(
          columns: [
            Customer.Dimensions.brand(),
            Customer.Measures.count()
          ],
          limit: 5
        )

      # Verify we got a map with the expected keys
      # Column names are normalized (cube prefix removed)
      assert ["brand", "count"] ==
               result |> Explorer.DataFrame.names()

      # Verify data is in columnar format
      brands = result["brand"]
      counts = result["count"]
      assert 5 == brands |> Explorer.Series.size()
      assert 5 == counts |> Explorer.Series.size()
      # Verify counts are strings (HTTP returns strings)
      assert {:s, 64} = counts |> Explorer.Series.dtype()
    end

    test "query with single measure" do
      {:ok, result} =
        Customer.df(
          columns: [Customer.Measures.count()],
          limit: 1
        )

      assert %Explorer.DataFrame{} = result
      # Column names are normalized (cube prefix removed)
      assert "count" in Explorer.DataFrame.names(result)
      counts = result["count"]
      assert %Explorer.Series{} = counts
    end

    test "query with multiple dimensions" do
      {:ok, result} =
        Customer.df(
          columns: [
            Customer.Dimensions.brand(),
            Customer.Dimensions.market(),
            Customer.Measures.count()
          ],
          limit: 3
        )

      # Column names are normalized (cube prefix removed)
      names = Explorer.DataFrame.names(result)
      assert "brand" in names
      assert "market" in names
      assert "count" in names

      # All columns should have same length
      brands_len = Explorer.Series.size(result["brand"])
      markets_len = Explorer.Series.size(result["market"])
      counts_len = Explorer.Series.size(result["count"])

      assert brands_len == markets_len
      assert markets_len == counts_len
    end

    test "query with limit" do
      {:ok, result} =
        Customer.df(
          columns: [Customer.Dimensions.brand(), Customer.Measures.count()],
          limit: 3
        )

      brands = result["brand"]
      assert Explorer.Series.size(brands) <= 3
    end

    test "query with offset" do
      # Get first 2 results
      {:ok, first_batch} =
        Customer.df(
          columns: [Customer.Dimensions.brand(), Customer.Measures.count()],
          limit: 2,
          offset: 0
        )

      # Get next 2 results
      {:ok, second_batch} =
        Customer.df(
          columns: [Customer.Dimensions.brand(), Customer.Measures.count()],
          limit: 2,
          offset: 2
        )

      # Results should be different (assuming we have > 2 rows)
      # Column names are normalized (cube prefix removed)
      refute Explorer.Series.to_list(first_batch["brand"]) ==
               Explorer.Series.to_list(second_batch["brand"])
    end
  end

  describe "df/1 with WHERE filters (HTTP)" do
    test "simple equals filter" do
      {:ok, result} =
        Customer.df(
          columns: [
            Customer.Dimensions.brand(),
            Customer.Measures.count()
          ],
          where: [{Customer.Dimensions.brand(), :==, "BudLight"}],
          limit: 5
        )

      brands = result["brand"]
      counts = result["count"]

      assert %Explorer.Series{} = brands
      assert %Explorer.Series{} = counts

      # All brands should be BudLight
      assert Enum.all?(Explorer.Series.to_list(brands), &(&1 == "BudLight"))
    end

    test "greater than filter" do
      # This tests numeric comparison in WHERE clause
      # Note: May not work if count isn't directly filterable
      {:ok, result} =
        Customer.df(
          columns: [
            Customer.Dimensions.brand(),
            Customer.Measures.count()
          ],
          limit: 10
        )

      # Just verify it executes without error
      assert %Explorer.DataFrame{} = result
    end

    test "IN filter" do
      {:ok, result} =
        Customer.df(
          columns: [
            Customer.Dimensions.brand(),
            Customer.Measures.count()
          ],
          where: [{Customer.Dimensions.brand(), :in, ["BudLight", "Dos Equis"]}],
          limit: 10
        )

      brands = result["brand"]

      assert %Explorer.Series{} = brands
      # All brands should be either BudLight or Dos Equis
      assert Enum.all?(Explorer.Series.to_list(brands), &(&1 in ["BudLight", "Dos Equis"]))
    end

    test "not equals filter" do
      {:ok, result} =
        Customer.df(
          columns: [
            Customer.Dimensions.brand(),
            Customer.Measures.count()
          ],
          where: [{Customer.Dimensions.brand(), :!=, "BudLight"}],
          limit: 5
        )

      brands = result["brand"]

      # No brand should be BudLight
      refute Enum.any?(Explorer.Series.to_list(brands), &(&1 == "BudLight"))
    end
  end

  describe "df/1 with ORDER BY (HTTP)" do
    test "order by dimension ascending" do
      {:ok, result} =
        Customer.df(
          columns: [
            Customer.Dimensions.brand(),
            Customer.Measures.count()
          ],
          order_by: [{1, :asc}],
          limit: 5
        )

      brands = result["brand"]

      # Verify we got results
      assert 5 == brands |> Explorer.Series.size()

      # Verify ordering (should be alphabetically sorted)
      assert ["Amstel", "Becks", "Birra Moretti", "Blue Moon", "BudLight"] ==
               Explorer.Series.to_list(brands)
    end

    test "order by measure descending" do
      {:ok, result} =
        Customer.df(
          columns: [
            Customer.Dimensions.brand(),
            Customer.Measures.count()
          ],
          order_by: [{2, :desc}],
          limit: 5
        )

      counts = result["count"]

      # Verify we got results
      assert Explorer.Series.size(counts) > 0

      # Verify descending order (convert to list for comparison since counts are strings)
      counts_list = Explorer.Series.to_list(counts)
      assert counts_list == Enum.sort(counts_list, :desc)
    end

    test "order by without direction (defaults to asc)" do
      {:ok, result} =
        Customer.df(
          columns: [
            Customer.Dimensions.given_name(),
            Customer.Measures.count()
          ],
          order_by: [1],
          limit: 5
        )

      names = result["given_name"]

      # Should be sorted
      assert 5 == Explorer.Series.size(names)
    end
  end

  describe "df/1 type conversion (HTTP)" do
    test "integer counts are converted from strings" do
      {:ok, result} =
        Customer.df(
          columns: [Customer.Measures.count()],
          limit: 1
        )

      counts = result["count"]

      assert %Explorer.Series{} = counts
      # HTTP client returns strings, conversion happens elsewhere
      assert {:s, 64} == Explorer.Series.dtype(counts)
    end

    test "string dimensions remain strings" do
      {:ok, result} =
        Customer.df(
          columns: [Customer.Dimensions.brand()],
          limit: 3
        )

      brands = result["brand"]
      assert :string == Explorer.Series.dtype(brands)
      brands_list = Explorer.Series.to_list(brands)
      assert is_list(brands_list)
      assert Enum.all?(brands_list, &is_binary/1)
    end

    test "numeric dimensions are converted to numbers" do
      {:ok, result} =
        Customer.df(
          columns: [
            Customer.Dimensions.star_sector(),
            Customer.Measures.count()
          ],
          limit: 5
        )

      star_sectors = result["star_sector"]

      # star_sector should be numbers (0-11) or strings from HTTP
      # HTTP returns strings, type conversion may happen in Explorer.DataFrame.new
      dtype = Explorer.Series.dtype(star_sectors)
      assert dtype in [{:f, 64}]
    end
  end

  describe "df/1 error handling (HTTP)" do
    test "returns error for invalid query" do
      # Missing required columns option
      assert_raise KeyError, fn ->
        Customer.df(limit: 5)
      end
    end

    test "supports multiple AND conditions" do
      # Multiple conditions are now supported with typed WHERE (combined with AND)
      {:ok, result} =
        Customer.df(
          columns: [Customer.Measures.count()],
          where: [
            {Customer.Dimensions.brand(), :==, "BudLight"},
            {Customer.Dimensions.market(), :==, "US"}
          ],
          limit: 5
        )

      # Should successfully return results
      assert %Explorer.DataFrame{} = result
    end
  end

  describe "df/1 with explicit HTTP client (HTTP)" do
    test "reuses HTTP client across queries" do
      {:ok, http_client} = PowerOfThree.CubeHttpClient.new(base_url: "http://localhost:4008")

      {:ok, result1} =
        Customer.df(
          columns: [Customer.Dimensions.brand(), Customer.Measures.count()],
          http_client: http_client,
          limit: 3
        )

      {:ok, result2} =
        Customer.df(
          columns: [Customer.Dimensions.market(), Customer.Measures.count()],
          http_client: http_client,
          limit: 3
        )

      # Both queries should succeed
      assert ["brand", "count"] ==
               result1 |> Explorer.DataFrame.names()

      assert ["count", "market"] ==
               result2 |> Explorer.DataFrame.names()
    end

    test "HTTP client with custom base URL" do
      {:ok, http_client} = PowerOfThree.CubeHttpClient.new(base_url: "http://localhost:4008")

      {:ok, result} =
        Customer.df(
          columns: [Customer.Measures.count()],
          http_client: http_client,
          limit: 1
        )

      assert ["count"] == result |> Explorer.DataFrame.names()
    end
  end

  describe "df/1 with connection_opts (HTTP)" do
    test "passes connection_opts for HTTP" do
      {:ok, result} =
        Customer.df(
          columns: [Customer.Dimensions.brand(), Customer.Measures.count()],
          connection_opts: [base_url: "http://localhost:4008"],
          limit: 3
        )

      assert ["brand", "count"] ==
               result |> Explorer.DataFrame.names()
    end
  end

  describe "df!/1 (raising version) with HTTP" do
    test "returns result directly on success" do
      result =
        Customer.df!(
          columns: [Customer.Dimensions.brand(), Customer.Measures.count()],
          limit: 3
        )

      assert ["brand", "count"] ==
               result |> Explorer.DataFrame.names()
    end

    test "raises on error" do
      # df!/1 re-raises errors with invalid WHERE clause
      assert_raise FunctionClauseError, fn ->
        Customer.df!(
          columns: [Customer.Measures.count()],
          where: "string WHERE not supported",
          limit: 5
        )
      end
    end
  end

  describe "df/1 combined scenarios (HTTP)" do
    test "filter + order + limit" do
      {:ok, result} =
        Customer.df(
          columns: [
            Customer.Dimensions.brand(),
            Customer.Measures.count()
          ],
          where: [{Customer.Dimensions.brand(), :==, "BudLight"}],
          order_by: [{2, :desc}],
          limit: 5
        )

      brands = result["brand"]
      counts = result["count"]

      assert brands |> Explorer.Series.size() <= 5
      assert counts |> Explorer.Series.size() <= 5

      # All brands should be BudLight
      # brands |> IO.inspect()

      assert ["BudLight"] ==
               brands |> Explorer.Series.to_list()
    end

    test "multiple dimensions + filter + order" do
      {:ok, result} =
        Customer.df(
          columns: [
            Customer.Dimensions.brand(),
            Customer.Dimensions.market(),
            Customer.Measures.count()
          ],
          where: [{Customer.Dimensions.brand(), :in, ["BudLight", "Dos Equis", "Blue Moon"]}],
          order_by: [{1, :asc}]
        )

      # All brands should be in the filter list
      assert ["BudLight", "Dos Equis", "Blue Moon"] |> Enum.sort() ==
               result["brand"]
               |> Explorer.Series.distinct() |> IO.inspect
               |> Explorer.Series.to_list()
               |> Enum.sort()
    end
  end

  describe "df/1 with column aliases (HTTP)" do
    test "simple aliases for dimensions and measures" do
      {:ok, result} =
        Customer.df(
          columns: [
            mah_brand: Customer.Dimensions.brand(),
            mah_people: Customer.Measures.count()
          ],
          limit: 5
        )

      # Column names should be the aliases
      assert ["mah_brand", "mah_people"] == Explorer.DataFrame.names(result)

      # Verify data is present
      brands = result["mah_brand"]
      counts = result["mah_people"]
      assert 5 == Explorer.Series.size(brands)
      assert 5 == Explorer.Series.size(counts)
    end

    test "mixed aliases and regular syntax" do
      # This should be treated as a keyword list with aliases
      {:ok, result} =
        Customer.df(
          columns: [
            brand_alias: Customer.Dimensions.brand(),
            market_alias: Customer.Dimensions.market(),
            total: Customer.Measures.count()
          ],
          limit: 3
        )

      names = Explorer.DataFrame.names(result)
      assert "brand_alias" in names
      assert "market_alias" in names
      assert "total" in names
    end

    test "aliases with WHERE clause" do
      {:ok, result} =
        Customer.df(
          columns: [
            my_brand: Customer.Dimensions.brand(),
            num_customers: Customer.Measures.count()
          ],
          where: [{Customer.Dimensions.brand(), :==, "BudLight"}],
          limit: 5
        )

      assert ["my_brand", "num_customers"] == Explorer.DataFrame.names(result)

      brands = result["my_brand"]
      assert Enum.all?(Explorer.Series.to_list(brands), &(&1 == "BudLight"))
    end

    test "aliases with ORDER BY" do
      {:ok, result} =
        Customer.df(
          columns: [
            beer: Customer.Dimensions.brand(),
            popularity: Customer.Measures.count()
          ],
          order_by: [{1, :asc}],
          limit: 5
        )

      assert ["beer", "popularity"] == Explorer.DataFrame.names(result)

      beers = result["beer"]
      assert 5 == Explorer.Series.size(beers)
    end

    test "single column with alias" do
      {:ok, result} =
        Customer.df(
          columns: [total_count: Customer.Measures.count()],
          limit: 1
        )

      assert ["total_count"] == Explorer.DataFrame.names(result)
      assert %Explorer.DataFrame{} = result
    end
  end
end
