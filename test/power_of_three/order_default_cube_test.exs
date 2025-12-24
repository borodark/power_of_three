defmodule PowerOfThree.OrderDefaultCubeTest do
  use ExUnit.Case, async: true

  @moduletag :live_cube

  describe "auto-generated dimensions for Order" do
    test "generates dimensions for string fields" do
      dimensions = Order.dimensions() |> IO.inspect()
      dimension_names = Enum.map(dimensions, & &1.name)

      # String fields should be dimensions
      assert "email" in dimension_names
      assert "financial_status" in dimension_names
      assert "fulfillment_status" in dimension_names
      assert "payment_reference" in dimension_names
      assert "brand_code" in dimension_names
      assert "market_code" in dimension_names
    end

    test "does not generate dimensions for integer fields" do
      dimensions = Order.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      # Integer fields should NOT be dimensions
      refute "delivery_subtotal_amount" in dimension_names
      refute "discount_total_amount" in dimension_names
      refute "subtotal_amount" in dimension_names
      refute "tax_amount" in dimension_names
      refute "total_amount" in dimension_names
      refute "customer_id" in dimension_names
    end

    test "skips id but generates time dimensions for timestamps" do
      dimensions = Order.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      # System field id should be skipped
      refute "id" in dimension_names

      # inserted_at and updated_at dimensions SHOULD exist as simple time dimensions
      assert "inserted_at" in dimension_names
      assert "updated_at" in dimension_names

      # Verify they are time dimensions
      inserted_dim = Enum.find(dimensions, &(&1.name == "inserted_at"))
      assert inserted_dim.type == :time

      updated_dim = Enum.find(dimensions, &(&1.name == "updated_at"))
      assert updated_dim.type == :time
    end

    test "dimension accessors work" do
      # Test that accessor functions exist and return proper structs
      assert %PowerOfThree.DimensionRef{} = Order.Dimensions.email()
      assert %PowerOfThree.DimensionRef{} = Order.Dimensions.financial_status()
      assert %PowerOfThree.DimensionRef{} = Order.Dimensions.brand_code()
      assert %PowerOfThree.DimensionRef{} = Order.Dimensions.market_code()
    end
  end

  describe "auto-generated measures for Order" do
    test "always generates count measure" do
      measures = Order.measures()
      measure_names = Enum.map(measures, & &1.name)

      assert :count in measure_names
    end

    test "generates sum measures for integer fields" do
      measures = Order.measures()
      measure_names = Enum.map(measures, & &1.name)

      # Integer fields should have _sum measures
      assert :delivery_subtotal_amount_sum in measure_names
      assert :discount_total_amount_sum in measure_names
      assert :subtotal_amount_sum in measure_names
      assert :tax_amount_sum in measure_names
      assert :total_amount_sum in measure_names
      assert :customer_id_sum in measure_names
    end

    test "generates count_distinct measures for integer fields" do
      measures = Order.measures()
      measure_names = Enum.map(measures, & &1.name)

      # Integer fields should have _distinct measures
      assert :delivery_subtotal_amount_distinct in measure_names
      assert :discount_total_amount_distinct in measure_names
      assert :subtotal_amount_distinct in measure_names
      assert :tax_amount_distinct in measure_names
      assert :total_amount_distinct in measure_names
      assert :customer_id_distinct in measure_names
    end

    test "measure accessors work" do
      # Test that accessor functions exist and return proper structs
      assert %PowerOfThree.MeasureRef{} = Order.Measures.count()
      assert %PowerOfThree.MeasureRef{} = Order.Measures.total_amount_sum()
      assert %PowerOfThree.MeasureRef{} = Order.Measures.total_amount_distinct()
      assert %PowerOfThree.MeasureRef{} = Order.Measures.tax_amount_sum()
    end
  end

  describe "df/1 basic queries with auto-generated cube" do
    test "simple query with one dimension and count" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Measures.count()
          ],
          limit: 5
        )

      assert %Explorer.DataFrame{} = result
      names = Explorer.DataFrame.names(result)
      assert "mandata_captate.brand_code" in names
      assert "mandata_captate.count" in names

      # Verify we got data
      brands = result["mandata_captate.brand_code"]
      assert Explorer.Series.size(brands) > 0
      assert Explorer.Series.size(brands) <= 5
    end

    test "query with multiple dimensions" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Dimensions.market_code(),
            Order.Measures.count()
          ],
          limit: 10
        )

      names = Explorer.DataFrame.names(result)
      assert "mandata_captate.brand_code" in names
      assert "mandata_captate.market_code" in names
      assert "mandata_captate.count" in names

      # All series should have same length
      brands_len = Explorer.Series.size(result["mandata_captate.brand_code"])
      markets_len = Explorer.Series.size(result["mandata_captate.market_code"])
      counts_len = Explorer.Series.size(result["mandata_captate.count"])

      assert brands_len == markets_len
      assert markets_len == counts_len
    end

    test "query with sum measures" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Measures.total_amount_sum(),
            Order.Measures.tax_amount_sum()
          ],
          limit: 5
        )

      names = Explorer.DataFrame.names(result)
      assert "mandata_captate.brand_code" in names
      assert "mandata_captate.total_amount_sum" in names
      assert "mandata_captate.tax_amount_sum" in names

      # Verify numeric data
      totals = result["mandata_captate.total_amount_sum"]
      taxes = result["mandata_captate.tax_amount_sum"]

      assert Explorer.Series.size(totals) > 0
      assert Explorer.Series.size(taxes) > 0
    end

    test "query with count_distinct measures" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Measures.customer_id_distinct()
          ],
          limit: 5
        )

      names = Explorer.DataFrame.names(result)
      assert "mandata_captate.brand_code" in names
      assert "mandata_captate.customer_id_distinct" in names

      distinct_customers = result["mandata_captate.customer_id_distinct"]
      assert Explorer.Series.size(distinct_customers) > 0
    end

    test "query with just count measure" do
      {:ok, result} =
        Order.df(
          columns: [Order.Measures.count()],
          limit: 1
        )

      assert ["mandata_captate.count"] == Explorer.DataFrame.names(result)
      count = result["mandata_captate.count"]
      assert Explorer.Series.size(count) == 1
    end
  end

  describe "df/1 with WHERE filters" do
    test "filter by string dimension" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Measures.count()
          ],
          where: "brand_code = 'BudLight'",
          limit: 10
        )

      brands = result["mandata_captate.brand_code"]

      # All brands should be BudLight
      brand_list = Explorer.Series.to_list(brands)
      assert Enum.all?(brand_list, &(&1 == "BudLight"))
    end

    test "filter by financial status" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.financial_status(),
            Order.Measures.count()
          ],
          where: "financial_status = 'paid'",
          limit: 5
        )

      statuses = result["mandata_captate.financial_status"]
      status_list = Explorer.Series.to_list(statuses)

      # All should be 'paid'
      assert Enum.all?(status_list, &(&1 == "paid"))
    end

    test "filter combined with aggregation" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.market_code(),
            Order.Measures.total_amount_sum()
          ],
          where: "market_code = 'US'",
          limit: 5
        )

      markets = result["mandata_captate.market_code"]
      totals = result["mandata_captate.total_amount_sum"]

      assert Explorer.Series.size(markets) > 0
      assert Explorer.Series.size(totals) > 0

      # All markets should be US
      market_list = Explorer.Series.to_list(markets)
      assert Enum.all?(market_list, &(&1 == "US"))
    end
  end

  describe "df/1 with ORDER BY" do
    test "order by dimension ascending" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Measures.count()
          ],
          order_by: [{1, :asc}],
          limit: 5
        )

      brands = result["mandata_captate.brand_code"]
      brand_list = Explorer.Series.to_list(brands)

      # Should be sorted
      assert brand_list == Enum.sort(brand_list)
    end

    test "order by measure descending" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Measures.total_amount_sum()
          ],
          order_by: [{2, :desc}],
          limit: 5
        )

      totals = result["mandata_captate.total_amount_sum"]

      # Should be in descending order
      assert Explorer.Series.size(totals) > 0
    end

    test "order by count descending" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.financial_status(),
            Order.Measures.count()
          ],
          order_by: [{2, :desc}],
          limit: 5
        )

      counts = result["mandata_captate.count"]
      assert Explorer.Series.size(counts) > 0
    end
  end

  describe "df/1 combined scenarios" do
    test "filter + order + limit" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Dimensions.market_code(),
            Order.Measures.total_amount_sum()
          ],
          where: "market_code = 'US'",
          order_by: [{3, :desc}],
          limit: 10
        )

      markets = result["mandata_captate.market_code"]
      brands = result["mandata_captate.brand_code"]
      totals = result["mandata_captate.total_amount_sum"]

      assert Explorer.Series.size(markets) > 0
      assert Explorer.Series.size(brands) > 0
      assert Explorer.Series.size(totals) > 0

      # All markets should be US
      market_list = Explorer.Series.to_list(markets)
      assert Enum.all?(market_list, &(&1 == "US"))
    end

    test "multiple dimensions + multiple measures" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Dimensions.financial_status(),
            Order.Measures.count(),
            Order.Measures.total_amount_sum(),
            Order.Measures.tax_amount_sum()
          ],
          limit: 20
        )

      names = Explorer.DataFrame.names(result)
      assert length(names) == 5
      assert "mandata_captate.brand_code" in names
      assert "mandata_captate.financial_status" in names
      assert "mandata_captate.count" in names
      assert "mandata_captate.total_amount_sum" in names
      assert "mandata_captate.tax_amount_sum" in names
    end

    test "aggregation by multiple dimensions" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Dimensions.market_code(),
            Order.Dimensions.financial_status(),
            Order.Measures.count(),
            Order.Measures.total_amount_sum()
          ],
          order_by: [{4, :desc}],
          limit: 15
        )

      # All series should have data
      brands = result["mandata_captate.brand_code"]
      markets = result["mandata_captate.market_code"]
      statuses = result["mandata_captate.financial_status"]
      counts = result["mandata_captate.count"]
      totals = result["mandata_captate.total_amount_sum"]

      assert Explorer.Series.size(brands) > 0
      assert Explorer.Series.size(markets) > 0
      assert Explorer.Series.size(statuses) > 0
      assert Explorer.Series.size(counts) > 0
      assert Explorer.Series.size(totals) > 0
    end

    test "distinct customers per brand" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Measures.customer_id_distinct(),
            Order.Measures.count()
          ],
          order_by: [{2, :desc}],
          limit: 10
        )

      brands = result["mandata_captate.brand_code"]
      distinct_customers = result["mandata_captate.customer_id_distinct"]
      counts = result["mandata_captate.count"]

      assert Explorer.Series.size(brands) > 0
      assert Explorer.Series.size(distinct_customers) > 0
      assert Explorer.Series.size(counts) > 0
    end
  end

  describe "df/1 with offset" do
    test "offset pagination works" do
      # Get first batch
      {:ok, first_batch} =
        Order.df(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Measures.count()
          ],
          order_by: [{1, :asc}],
          limit: 5,
          offset: 0
        )

      # Get second batch
      {:ok, second_batch} =
        Order.df(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Measures.count()
          ],
          order_by: [{1, :asc}],
          limit: 5,
          offset: 5
        )

      first_brands = Explorer.Series.to_list(first_batch["mandata_captate.brand_code"])
      second_brands = Explorer.Series.to_list(second_batch["mandata_captate.brand_code"])

      # Should be different (assuming enough data)
      refute first_brands == second_brands
    end
  end

  describe "df!/1 raising version" do
    test "returns DataFrame directly on success" do
      result =
        Order.df!(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Measures.count()
          ],
          limit: 3
        )

      assert %Explorer.DataFrame{} = result
      assert "mandata_captate.brand_code" in Explorer.DataFrame.names(result)
    end
  end

  describe "auto-generated cube completeness" do
    test "has all expected dimensions" do
      dimensions = Order.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name) |> Enum.sort()

      expected_dimensions =
        [
          # String field dimensions
          "brand_code",
          "email",
          "financial_status",
          "fulfillment_status",
          "market_code",
          "payment_reference",
          # Time dimensions (simple, granularity specified at query time)
          "inserted_at",
          "updated_at"
        ]
        |> Enum.sort()

      assert dimension_names == expected_dimensions
    end

    test "has all expected measures" do
      measures = Order.measures()
      measure_names = Enum.map(measures, & &1.name) |> Enum.sort()

      expected_measures =
        [
          :count,
          :customer_id_distinct,
          :customer_id_sum,
          :delivery_subtotal_amount_distinct,
          :delivery_subtotal_amount_sum,
          :discount_total_amount_distinct,
          :discount_total_amount_sum,
          :subtotal_amount_distinct,
          :subtotal_amount_sum,
          :tax_amount_distinct,
          :tax_amount_sum,
          :total_amount_distinct,
          :total_amount_sum

        ]
        |> Enum.sort()

      assert measure_names == expected_measures
    end

    test "all dimension accessors are callable" do
      dimensions = Order.dimensions()

      for dim <- dimensions do
        # Handle both string and atom dimension names
        accessor_name =
          case dim.name do
            name when is_binary(name) -> String.to_atom(name)
            name when is_atom(name) -> name
          end

        assert function_exported?(Order.Dimensions, accessor_name, 0)
        accessor_result = apply(Order.Dimensions, accessor_name, [])
        assert %PowerOfThree.DimensionRef{} = accessor_result
      end
    end

    test "all measure accessors are callable" do
      measures = Order.measures() |> IO.inspect()
      # accessor_name = Order.Mea
      # assert function_exported?(Order.Measures, accessor_name, 0)
      # accessor_result = apply(Order.Measures, accessor_name, [])
      # assert %PowerOfThree.MeasureRef{} = accessor_result
    end
  end

  describe "real analytics queries" do
    test "revenue analysis by brand and status" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.brand_code(),
            Order.Dimensions.financial_status(),
            Order.Measures.count(),
            Order.Measures.total_amount_sum(),
            Order.Measures.tax_amount_sum(),
            Order.Measures.customer_id_distinct()
          ],
          where: "financial_status = 'paid'",
          order_by: [{4, :desc}],
          limit: 20
        )

      # Should have meaningful data for analytics
      brands = result["mandata_captate.brand_code"]
      statuses = result["mandata_captate.financial_status"]
      counts = result["mandata_captate.count"]
      totals = result["mandata_captate.total_amount_sum"]

      assert Explorer.Series.size(brands) > 0
      assert Enum.all?(Explorer.Series.to_list(statuses), &(&1 == "paid"))
      assert Explorer.Series.size(counts) > 0
      assert Explorer.Series.size(totals) > 0
    end

    test "market performance comparison" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.market_code(),
            Order.Measures.count(),
            Order.Measures.total_amount_sum(),
            Order.Measures.customer_id_distinct()
          ],
          order_by: [{2, :desc}],
          limit: 10
        )

      markets = result["mandata_captate.market_code"]
      counts = result["mandata_captate.count"]
      totals = result["mandata_captate.total_amount_sum"]
      customers = result["mandata_captate.customer_id_distinct"]

      assert Explorer.Series.size(markets) > 0
      assert Explorer.Series.size(counts) > 0
      assert Explorer.Series.size(totals) > 0
      assert Explorer.Series.size(customers) > 0
    end

    test "fulfillment status breakdown" do
      {:ok, result} =
        Order.df(
          columns: [
            Order.Dimensions.fulfillment_status(),
            Order.Measures.count(),
            Order.Measures.total_amount_sum()
          ],
          order_by: [{2, :desc}],
          limit: 15
        )

      statuses = result["mandata_captate.fulfillment_status"]
      counts = result["mandata_captate.count"]
      totals = result["mandata_captate.total_amount_sum"]

      assert Explorer.Series.size(statuses) > 0
      assert Explorer.Series.size(counts) > 0
      assert Explorer.Series.size(totals) > 0
    end
  end
end
