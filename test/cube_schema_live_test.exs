defmodule CubeSchemaLiveTest do
  @moduledoc """
  Live integration tests for CubeSchema with Cube SQL API on port 9432.

  These tests require:
  - Cube SQL API running on localhost:9432
  - The orders_no_preagg cube configured

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

  # CubeSchema for of_customers cube (no id field)
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
    # Start the Repo with Cube SQL connection
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

  describe "basic queries with Repo.all/2" do
    test "fetches all orders with limit" do
      import Ecto.Query

      query = from(o in Orders, limit: 5)
      results = CubeRepo.all(query)

      assert length(results) == 5
      assert Enum.all?(results, fn r -> is_struct(r, Orders) end)
    end

    test "fetches orders with specific fields" do
      import Ecto.Query

      query =
        from(o in Orders,
          select: {o.brand_code, o.total_amount_sum},
          limit: 3
        )

      results = CubeRepo.all(query)

      assert length(results) == 3
      assert Enum.all?(results, fn {brand, total} ->
        is_binary(brand) and is_float(total)
      end)
    end

    test "fetches customers without primary key" do
      import Ecto.Query

      query = from(c in Customers, limit: 3)
      results = CubeRepo.all(query)

      assert length(results) == 3
      assert Enum.all?(results, fn r -> is_struct(r, Customers) end)
    end
  end

  describe "Repo.one/2 queries" do
    test "fetches single order by id" do
      import Ecto.Query

      query = from(o in Orders, where: o.id == 1.0)
      result = CubeRepo.one(query)

      assert is_struct(result, Orders)
      assert result.id == 1.0
    end

    test "returns nil for non-existent id" do
      import Ecto.Query

      query = from(o in Orders, where: o.id == -999.0)
      result = CubeRepo.one(query)

      assert is_nil(result)
    end
  end

  describe "WHERE clause filtering" do
    test "filters by string dimension with literal" do
      import Ecto.Query

      query =
        from(o in Orders,
          where: o.brand_code == "Heineken",
          limit: 5
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      assert Enum.all?(results, fn r -> r.brand_code == "Heineken" end)
    end

    test "filters by string dimension with parameter" do
      import Ecto.Query

      brand = "Corona Extra"

      query =
        from(o in Orders,
          where: o.brand_code == ^brand,
          limit: 5
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      assert Enum.all?(results, fn r -> r.brand_code == "Corona Extra" end)
    end

    test "filters customers by brand" do
      import Ecto.Query

      query =
        from(c in Customers,
          where: c.brand == "Guinness",
          limit: 3
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      assert Enum.all?(results, fn r -> r.brand == "Guinness" end)
    end
  end

  describe "ORDER BY queries" do
    test "orders by dimension ascending" do
      import Ecto.Query

      query =
        from(o in Orders,
          order_by: [asc: o.brand_code],
          limit: 10
        )

      results = CubeRepo.all(query)
      brands = Enum.map(results, & &1.brand_code)

      assert brands == Enum.sort(brands)
    end

    test "orders by dimension descending" do
      import Ecto.Query

      query =
        from(o in Orders,
          order_by: [desc: o.brand_code],
          limit: 10
        )

      results = CubeRepo.all(query)
      brands = Enum.map(results, & &1.brand_code)

      assert brands == Enum.sort(brands, :desc)
    end

    test "orders by measure descending" do
      import Ecto.Query

      query =
        from(o in Orders,
          order_by: [desc: o.total_amount_sum],
          limit: 5
        )

      results = CubeRepo.all(query)
      totals = Enum.map(results, & &1.total_amount_sum)

      assert totals == Enum.sort(totals, :desc)
    end
  end

  describe "GROUP BY with aggregation" do
    test "groups by brand with count" do
      import Ecto.Query

      query =
        from(o in Orders,
          group_by: o.brand_code,
          select: {o.brand_code, count(o.id)},
          order_by: [desc: 2],
          limit: 10
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      assert Enum.all?(results, fn {brand, count} ->
        is_binary(brand) and is_integer(count) and count > 0
      end)
    end

    test "groups by brand with sum aggregation" do
      import Ecto.Query

      query =
        from(o in Orders,
          group_by: o.brand_code,
          select: {o.brand_code, sum(o.total_amount_sum)},
          order_by: [desc: 2],
          limit: 5
        )

      results = CubeRepo.all(query)

      assert length(results) == 5
      # Check descending order
      sums = Enum.map(results, fn {_brand, sum} -> sum end)
      assert sums == Enum.sort(sums, :desc)
    end

    test "groups by multiple dimensions" do
      import Ecto.Query

      query =
        from(o in Orders,
          group_by: [o.brand_code, o.market_code],
          select: {o.brand_code, o.market_code, count(o.id)},
          order_by: [desc: 3],
          limit: 10
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      assert Enum.all?(results, fn {brand, market, count} ->
        is_binary(brand) and is_binary(market) and is_integer(count)
      end)
    end

    test "groups customers by zodiac sign" do
      import Ecto.Query

      query =
        from(c in Customers,
          group_by: c.zodiac,
          select: {c.zodiac, count()},
          order_by: [desc: 2],
          limit: 12
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      # Should have zodiac signs
      zodiacs = Enum.map(results, fn {zodiac, _count} -> zodiac end)
      assert Enum.any?(zodiacs, &(&1 in ["Aquarius", "Pisces", "Aries", "Leo", "Virgo"]))
    end
  end

  describe "composable queries" do
    test "builds query step by step" do
      import Ecto.Query

      base = from(o in Orders)
      filtered = where(base, [o], o.brand_code == "Heineken")
      ordered = order_by(filtered, [o], desc: o.total_amount_sum)
      limited = limit(ordered, 5)

      results = CubeRepo.all(limited)

      assert length(results) == 5
      assert Enum.all?(results, fn r -> r.brand_code == "Heineken" end)
    end

    test "combines filter with aggregation" do
      import Ecto.Query

      query =
        from(o in Orders,
          where: o.brand_code == "Budweiser",
          group_by: o.market_code,
          select: {o.market_code, sum(o.total_amount_sum)},
          order_by: [desc: 2],
          limit: 5
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
    end
  end

  describe "select with maps and tuples" do
    test "selects into map" do
      import Ecto.Query

      query =
        from(o in Orders,
          select: %{brand: o.brand_code, total: o.total_amount_sum},
          limit: 3
        )

      results = CubeRepo.all(query)

      assert length(results) == 3
      assert Enum.all?(results, fn r ->
        is_map(r) and Map.has_key?(r, :brand) and Map.has_key?(r, :total)
      end)
    end

    test "selects into tuple" do
      import Ecto.Query

      query =
        from(o in Orders,
          select: {o.brand_code, o.market_code, o.count},
          limit: 3
        )

      results = CubeRepo.all(query)

      assert length(results) == 3
      assert Enum.all?(results, fn {brand, market, count} ->
        is_binary(brand) and is_binary(market) and is_integer(count)
      end)
    end
  end

  describe "real analytics scenarios" do
    test "top brands by revenue" do
      import Ecto.Query

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

      assert length(results) == 10
      # Check top brand has significant revenue
      top_brand = hd(results)
      assert top_brand.total_revenue > 1_000_000
    end

    test "market performance analysis" do
      import Ecto.Query

      query =
        from(o in Orders,
          group_by: o.market_code,
          select: {o.market_code, count(o.id), sum(o.total_amount_sum)},
          order_by: [desc: 2],
          limit: 10
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      # Verify structure
      {market, count, total} = hd(results)
      assert is_binary(market)
      assert is_integer(count) and count > 0
      assert is_float(total) and total > 0
    end

    test "customer distribution by zodiac" do
      import Ecto.Query

      query =
        from(c in Customers,
          group_by: c.zodiac,
          select: %{sign: c.zodiac, customers: count()},
          order_by: [desc: count()],
          limit: 13
        )

      results = CubeRepo.all(query)

      assert length(results) > 0
      # Should have multiple zodiac signs
      signs = Enum.map(results, & &1.sign)
      assert length(signs) > 1
    end
  end
end
