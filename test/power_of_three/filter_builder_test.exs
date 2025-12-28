defmodule PowerOfThree.FilterBuilderTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.{FilterBuilder, DimensionRef, MeasureRef}

  setup do
    brand_dim = %DimensionRef{
      name: :brand,
      sql: "brand_code",
      type: :string,
      module: Customer
    }

    market_dim = %DimensionRef{
      name: :market,
      sql: "market_code",
      type: :string,
      module: Customer
    }

    count_measure = %MeasureRef{
      name: :count,
      type: :count,
      module: Customer
    }

    {:ok, brand: brand_dim, market: market_dim, count: count_measure}
  end

  describe "to_cube_filters/1" do
    test "converts empty list", do: assert({:ok, []} = FilterBuilder.to_cube_filters([]))
    test "converts nil", do: assert({:ok, []} = FilterBuilder.to_cube_filters(nil))

    test "converts single condition", %{brand: brand} do
      {:ok, filters} = FilterBuilder.to_cube_filters([{brand, :==, "BQ"}])

      assert length(filters) == 1
      [filter] = filters
      assert filter["member"] == "power_customers.brand"
      assert filter["operator"] == "equals"
      assert filter["values"] == ["BQ"]
    end

    test "converts multiple conditions", %{brand: brand, count: count} do
      {:ok, filters} =
        FilterBuilder.to_cube_filters([
          {brand, :==, "BQ"},
          {count, :>, 1000}
        ])

      assert length(filters) == 2

      [filter1, filter2] = filters
      assert filter1["member"] == "power_customers.brand"
      assert filter2["member"] == "power_customers.count"
    end
  end

  describe "to_sql/1" do
    test "converts empty list", do: assert({:ok, ""} = FilterBuilder.to_sql([]))
    test "converts nil", do: assert({:ok, ""} = FilterBuilder.to_sql(nil))

    test "converts single condition", %{brand: brand} do
      {:ok, sql} = FilterBuilder.to_sql([{brand, :==, "BQ"}])
      assert sql == "brand = 'BQ'"
    end

    test "converts multiple conditions with AND", %{brand: brand, count: count} do
      {:ok, sql} =
        FilterBuilder.to_sql([
          {brand, :==, "BQ"},
          {count, :>, 1000}
        ])

      assert sql == "brand = 'BQ' AND count > 1000"
    end

    test "converts complex multi-condition query", %{brand: brand, market: market, count: count} do
      {:ok, sql} =
        FilterBuilder.to_sql([
          {brand, :in, ["BQ", "Corona"]},
          {market, :==, "US"},
          {count, :>=, 500}
        ])

      assert sql == "brand IN ('BQ', 'Corona') AND market = 'US' AND count >= 500"
    end
  end

  describe "validate/1" do
    test "validates empty list", do: assert(:ok = FilterBuilder.validate([]))
    test "validates nil", do: assert(:ok = FilterBuilder.validate(nil))

    test "validates list of conditions", %{brand: brand, count: count} do
      assert :ok =
               FilterBuilder.validate([
                 {brand, :==, "BQ"},
                 {count, :>, 1000}
               ])
    end

    test "rejects invalid condition in list" do
      assert {:error, _} = FilterBuilder.validate([{:invalid, :==, "BQ"}])
    end

    test "rejects non-list, non-string" do
      assert {:error, _} = FilterBuilder.validate(123)
    end
  end
end
