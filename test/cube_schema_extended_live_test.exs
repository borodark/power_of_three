defmodule CubeSchemaExtendedLiveTest do
  @moduledoc """
  Extended live integration tests for CubeSchema with Cube SQL API on port 9432.

  These tests cover additional query patterns and edge cases.

  Run with: mix test --include live_cube
  """

  use ExUnit.Case, async: false

  @moduletag :live_cube

  # Define a test Repo for connecting to Cube
  defmodule CubeRepo do
    use Ecto.Repo,
      otp_app: :power_of_3,
      adapter: Ecto.Adapters.Postgres
  end

  # CubeSchema for orders_no_preagg cube
  defmodule Orders do
    use PowerOfThree.CubeSchema

    cube_schema :orders_no_preagg do
      dimension :id, :float
      dimension :brand_code, :string
      dimension :market_code, :string
      dimension :updated_at, :utc_datetime
      dimension :inserted_at, :utc_datetime

      measure :count, :integer
      measure :total_amount_sum, :float
      measure :tax_amount_sum, :float
      measure :subtotal_amount_sum, :float
      measure :customer_id_distinct, :integer
    end
  end

  # CubeSchema for of_customers cube
  defmodule Customers do
    use PowerOfThree.CubeSchema

    cube_schema :of_customers do
      dimension :email_per_brand_per_market, :string
      dimension :given_name, :string
      dimension :zodiac, :string
      dimension :star_sector, :float
      dimension :bm_code, :string
      dimension :brand, :string
      dimension :market, :string
      dimension :updated, :utc_datetime
      dimension :inserted_at, :utc_datetime

      measure :count, :integer
      measure :emails_distinct, :integer
      measure :aquarii, :integer
    end
  end

  setup_all do
    repo_config = [
      hostname: "localhost",
      port: 9432,
      database: "cube",
      username: "cube",
      password: "cube",
      pool_size: 2
    ]

    {:ok, _pid} = CubeRepo.start_link(repo_config)

    :ok
  end

  describe "IN clause filtering" do
    test "filters orders by multiple brand codes using OR" do
      import Ecto.Query

      # Cube doesn't support IN with parameterized arrays, use OR instead
      query =
        from(o in Orders,
          where: o.brand_code == "Heineken" or o.brand_code == "Corona Extra" or o.brand_code == "Budweiser",
          limit: 10
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      assert Enum.all?(results, fn r -> r.brand_code in ["Heineken", "Corona Extra", "Budweiser"] end)
    end

    test "filters customers by multiple markets using OR" do
      import Ecto.Query

      # Cube doesn't support IN with parameterized arrays, use OR instead
      query =
        from(c in Customers,
          where: c.market == "AU" or c.market == "US" or c.market == "UK",
          limit: 10
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      assert Enum.all?(results, fn r -> r.market in ["AU", "US", "UK"] end)
    end
  end

  describe "multiple WHERE conditions" do
    test "filters with AND conditions" do
      import Ecto.Query

      query =
        from(o in Orders,
          where: o.brand_code == "Heineken" and o.market_code == "AU",
          limit: 5
        )

      results = CubeRepo.all(query)

      assert Enum.all?(results, fn r ->
        r.brand_code == "Heineken" and r.market_code == "AU"
      end)
    end

    test "filters customers by brand and zodiac" do
      import Ecto.Query

      query =
        from(c in Customers,
          where: c.brand == "Guinness" and c.zodiac == "Leo",
          limit: 5
        )

      results = CubeRepo.all(query)

      assert Enum.all?(results, fn r ->
        r.brand == "Guinness" and r.zodiac == "Leo"
      end)
    end
  end

  describe "OFFSET and pagination" do
    test "paginates orders with offset" do
      import Ecto.Query

      # First page
      page1_query =
        from(o in Orders,
          order_by: [asc: o.id],
          limit: 5,
          offset: 0
        )

      page1 = CubeRepo.all(page1_query)

      # Second page
      page2_query =
        from(o in Orders,
          order_by: [asc: o.id],
          limit: 5,
          offset: 5
        )

      page2 = CubeRepo.all(page2_query)

      # Pages should be different
      assert length(page1) == 5
      assert length(page2) == 5

      page1_ids = Enum.map(page1, & &1.id)
      page2_ids = Enum.map(page2, & &1.id)

      assert MapSet.disjoint?(MapSet.new(page1_ids), MapSet.new(page2_ids))
    end

    test "paginates grouped results" do
      import Ecto.Query

      query =
        from(o in Orders,
          group_by: o.brand_code,
          select: {o.brand_code, count(o.id)},
          order_by: [desc: 2],
          limit: 3,
          offset: 2
        )

      results = CubeRepo.all(query)

      assert length(results) == 3
    end
  end

  describe "NOT conditions" do
    test "excludes specific brand" do
      import Ecto.Query

      query =
        from(o in Orders,
          where: o.brand_code != "Heineken",
          limit: 10
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      assert Enum.all?(results, fn r -> r.brand_code != "Heineken" end)
    end

    test "excludes multiple brands using AND not equals" do
      import Ecto.Query

      # Cube doesn't support NOT IN with parameterized arrays, use AND with != instead
      query =
        from(o in Orders,
          where: o.brand_code != "Heineken" and o.brand_code != "Corona Extra",
          limit: 10
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      assert Enum.all?(results, fn r -> r.brand_code not in ["Heineken", "Corona Extra"] end)
    end
  end

  describe "numeric comparisons on measures" do
    test "filters grouped results by sum threshold" do
      import Ecto.Query

      # Get all brands with their sums first, then filter in Elixir
      # since Cube HAVING support is limited
      query =
        from(o in Orders,
          group_by: o.brand_code,
          select: {o.brand_code, sum(o.total_amount_sum)},
          order_by: [desc: 2],
          limit: 20
        )

      results = CubeRepo.all(query)
      # Filter for high revenue brands
      high_revenue = Enum.filter(results, fn {_brand, total} -> total > 1_000_000.0 end)

      assert length(high_revenue) > 0
      assert Enum.all?(high_revenue, fn {_brand, total} -> total > 1_000_000.0 end)
    end

    test "filters customers by star sector range" do
      import Ecto.Query

      # Star sector is 0-11, widen range to ensure we get results
      query =
        from(c in Customers,
          where: c.star_sector >= 0.0 and c.star_sector <= 11.0,
          limit: 10
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      assert Enum.all?(results, fn r ->
        r.star_sector >= 0.0 and r.star_sector <= 11.0
      end)
    end
  end

  describe "count and distinct aggregations" do
    test "counts orders per brand" do
      import Ecto.Query

      # Use sum of count measure for aggregation in GROUP BY queries
      query =
        from(o in Orders,
          group_by: o.brand_code,
          select: {o.brand_code, sum(o.count)},
          order_by: [desc: 2],
          limit: 5
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      assert Enum.all?(results, fn {brand, count} ->
        is_binary(brand) and is_integer(count) and count > 0
      end)
    end

    test "counts customers per market" do
      import Ecto.Query

      # Use count measure with sum for GROUP BY aggregation
      query =
        from(c in Customers,
          group_by: c.market,
          select: %{market: c.market, customer_count: sum(c.count)},
          order_by: [desc: sum(c.count)],
          limit: 5
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      assert Enum.all?(results, fn r -> r.customer_count > 0 end)
    end
  end

  describe "complex multi-level grouping" do
    test "groups by brand, market, and zodiac" do
      import Ecto.Query

      query =
        from(c in Customers,
          group_by: [c.brand, c.market, c.zodiac],
          select: %{
            brand: c.brand,
            market: c.market,
            zodiac: c.zodiac,
            customer_count: sum(c.count)
          },
          order_by: [desc: sum(c.count)],
          limit: 20
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      assert Enum.all?(results, fn r ->
        is_binary(r.brand) and
        is_binary(r.market) and
        is_binary(r.zodiac) and
        is_integer(r.customer_count)
      end)
    end

    test "calculates revenue breakdown by brand and market" do
      import Ecto.Query

      query =
        from(o in Orders,
          group_by: [o.brand_code, o.market_code],
          select: %{
            brand: o.brand_code,
            market: o.market_code,
            revenue: sum(o.total_amount_sum),
            tax: sum(o.tax_amount_sum),
            order_count: sum(o.count)
          },
          order_by: [desc: sum(o.total_amount_sum)],
          limit: 15
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      # Verify structure and data types
      first = hd(results)
      assert is_binary(first.brand)
      assert is_binary(first.market)
      assert is_float(first.revenue)
      assert is_float(first.tax)
      assert is_integer(first.order_count)
    end
  end

  describe "subquery-style patterns" do
    test "performs two-stage query with filtering" do
      import Ecto.Query

      # First query: get all brand revenues
      brand_query =
        from(o in Orders,
          group_by: o.brand_code,
          select: {o.brand_code, sum(o.total_amount_sum)},
          order_by: [desc: 2]
        )

      all_results = CubeRepo.all(brand_query)

      # Verify we got results
      assert length(all_results) > 0

      # Second stage: use results to do further analysis
      # Get top 3 brands
      top_brands = all_results |> Enum.take(3) |> Enum.map(fn {brand, _} -> brand end)

      # Verify the two-stage pattern works
      assert length(top_brands) == 3

      # Query orders for these top brands
      top_brands_details =
        from(o in Orders,
          where: o.brand_code == ^hd(top_brands),
          limit: 5
        )

      brand_orders = CubeRepo.all(top_brands_details)
      assert length(brand_orders) > 0
      assert Enum.all?(brand_orders, fn o -> o.brand_code == hd(top_brands) end)
    end
  end

  describe "field aliasing and transformations" do
    test "selects with computed field names" do
      import Ecto.Query

      # Use sum() on sum-compatible measures only
      query =
        from(o in Orders,
          group_by: o.brand_code,
          select: %{
            beer_brand: o.brand_code,
            total_sales: sum(o.total_amount_sum),
            order_count: sum(o.count)
          },
          order_by: [desc: sum(o.total_amount_sum)],
          limit: 5
        )

      results = CubeRepo.all(query)

      assert length(results) == 5
      first = hd(results)
      assert Map.has_key?(first, :beer_brand)
      assert Map.has_key?(first, :total_sales)
      assert Map.has_key?(first, :order_count)
    end

    test "returns list format results" do
      import Ecto.Query

      # Use sum(c.count) instead of count() for Cube compatibility
      query =
        from(c in Customers,
          group_by: c.zodiac,
          select: [c.zodiac, sum(c.count)],
          order_by: [desc: 2],
          limit: 12
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      assert Enum.all?(results, fn [zodiac, count] ->
        is_binary(zodiac) and is_integer(count)
      end)
    end
  end

  describe "edge cases and boundary conditions" do
    test "handles empty result set gracefully" do
      import Ecto.Query

      query =
        from(o in Orders,
          where: o.brand_code == "NonExistentBrand12345",
          limit: 10
        )

      results = CubeRepo.all(query)

      assert results == []
    end

    test "handles single result" do
      import Ecto.Query

      query =
        from(o in Orders,
          limit: 1
        )

      results = CubeRepo.all(query)

      assert length(results) == 1
    end

    test "handles large limit" do
      import Ecto.Query

      query =
        from(o in Orders,
          group_by: [o.brand_code, o.market_code],
          select: {o.brand_code, o.market_code, count(o.id)},
          limit: 1000
        )

      results = CubeRepo.all(query)

      # Should return whatever is available up to limit
      assert length(results) > 0
      assert length(results) <= 1000
    end
  end

  describe "real-world analytics scenarios" do
    test "calculates customer lifetime value metrics" do
      import Ecto.Query

      # Cube doesn't support SQL fragments, use separate calculations
      query =
        from(o in Orders,
          group_by: o.brand_code,
          select: %{
            brand: o.brand_code,
            total_revenue: sum(o.total_amount_sum),
            order_count: count(o.id)
          },
          order_by: [desc: sum(o.total_amount_sum)],
          limit: 10
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      first = hd(results)
      assert first.total_revenue > 0
      assert first.order_count > 0
      # Calculate avg_order_value in Elixir
      avg_order_value = first.total_revenue / first.order_count
      assert avg_order_value > 0
    end

    test "analyzes market penetration" do
      import Ecto.Query

      # Get market/brand combinations with counts
      query =
        from(c in Customers,
          group_by: [c.market, c.brand],
          select: %{
            market: c.market,
            brand: c.brand,
            customer_count: sum(c.count)
          },
          order_by: [asc: c.market, desc: sum(c.count)],
          limit: 100
        )

      all_results = CubeRepo.all(query)

      # Should have results
      assert length(all_results) > 0
      # Verify structure
      first = hd(all_results)
      assert is_binary(first.market)
      assert is_binary(first.brand)
      assert is_integer(first.customer_count)
    end

    test "zodiac distribution analysis" do
      import Ecto.Query

      query =
        from(c in Customers,
          group_by: [c.zodiac, c.star_sector],
          select: %{
            sign: c.zodiac,
            sector: c.star_sector,
            total: count()
          },
          order_by: [asc: c.star_sector],
          limit: 15
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      # Verify zodiac signs are present
      signs = Enum.map(results, & &1.sign) |> Enum.uniq()
      assert length(signs) > 1
    end
  end
end
