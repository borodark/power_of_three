defmodule PowerOfThree.QueryBuilderTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.{QueryBuilder, MeasureRef, DimensionRef}

  # Mock module for testing
  defmodule TestCustomer do
    def __schema__(:source), do: "customer"
  end

  describe "build/1" do
    test "builds simple query with dimensions and measures" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: "email"
      }

      measure = %MeasureRef{
        name: :count,
        module: TestCustomer,
        type: :count
      }

      sql =
        QueryBuilder.build(
          cube: "customer",
          columns: [dimension, measure]
        )

      assert sql =~ "SELECT customer.email, MEASURE(customer.count)"
      assert sql =~ "FROM customer"
      assert sql =~ "GROUP BY 1"
    end

    test "builds query with multiple dimensions" do
      dim1 = %DimensionRef{name: :brand, module: TestCustomer, type: :string, sql: "brand_code"}
      dim2 = %DimensionRef{name: :market, module: TestCustomer, type: :string, sql: "market_code"}

      measure = %MeasureRef{name: :count, module: TestCustomer, type: :count}

      sql =
        QueryBuilder.build(
          cube: "customer",
          columns: [dim1, dim2, measure]
        )

      assert sql =~ "SELECT customer.brand, customer.market, MEASURE(customer.count)"
      assert sql =~ "GROUP BY 1, 2"
    end

    test "builds query with measures only (no GROUP BY)" do
      measure1 = %MeasureRef{name: :count, module: TestCustomer, type: :count}
      measure2 = %MeasureRef{name: :total, module: TestCustomer, type: :sum}

      sql =
        QueryBuilder.build(
          cube: "customer",
          columns: [measure1, measure2]
        )

      assert sql =~ "SELECT MEASURE(customer.count), MEASURE(customer.total)"
      refute sql =~ "GROUP BY"
    end

    test "builds query with WHERE clause" do
      dimension = %DimensionRef{
        name: :brand,
        module: TestCustomer,
        type: :string,
        sql: "brand_code"
      }

      measure = %MeasureRef{name: :count, module: TestCustomer, type: :count}

      sql =
        QueryBuilder.build(
          cube: "customer",
          columns: [dimension, measure],
          where: "brand_code = 'NIKE'"
        )

      assert sql =~ "WHERE brand_code = 'NIKE'"
    end

    test "builds query with ORDER BY" do
      dimension = %DimensionRef{
        name: :brand,
        module: TestCustomer,
        type: :string,
        sql: "brand_code"
      }

      measure = %MeasureRef{name: :count, module: TestCustomer, type: :count}

      sql =
        QueryBuilder.build(
          cube: "customer",
          columns: [dimension, measure],
          order_by: [{2, :desc}, {1, :asc}]
        )

      assert sql =~ "ORDER BY 2 DESC, 1 ASC"
    end

    test "builds query with ORDER BY using integer shortcuts" do
      dimension = %DimensionRef{
        name: :brand,
        module: TestCustomer,
        type: :string,
        sql: "brand_code"
      }

      measure = %MeasureRef{name: :count, module: TestCustomer, type: :count}

      sql =
        QueryBuilder.build(
          cube: "customer",
          columns: [dimension, measure],
          order_by: [1, 2]
        )

      assert sql =~ "ORDER BY 1, 2"
    end

    test "builds query with LIMIT" do
      dimension = %DimensionRef{
        name: :brand,
        module: TestCustomer,
        type: :string,
        sql: "brand_code"
      }

      measure = %MeasureRef{name: :count, module: TestCustomer, type: :count}

      sql =
        QueryBuilder.build(
          cube: "customer",
          columns: [dimension, measure],
          limit: 10
        )

      assert sql =~ "LIMIT 10"
    end

    test "builds query with OFFSET" do
      dimension = %DimensionRef{
        name: :brand,
        module: TestCustomer,
        type: :string,
        sql: "brand_code"
      }

      measure = %MeasureRef{name: :count, module: TestCustomer, type: :count}

      sql =
        QueryBuilder.build(
          cube: "customer",
          columns: [dimension, measure],
          offset: 5
        )

      assert sql =~ "OFFSET 5"
    end

    test "builds query with all options" do
      dimension = %DimensionRef{
        name: :brand,
        module: TestCustomer,
        type: :string,
        sql: "brand_code"
      }

      measure = %MeasureRef{name: :count, module: TestCustomer, type: :count}

      sql =
        QueryBuilder.build(
          cube: "customer",
          columns: [dimension, measure],
          where: "brand_code = 'NIKE'",
          order_by: [{2, :desc}],
          limit: 10,
          offset: 5
        )

      assert sql =~ "SELECT customer.brand, MEASURE(customer.count)"
      assert sql =~ "FROM customer"
      assert sql =~ "GROUP BY 1"
      assert sql =~ "WHERE brand_code = 'NIKE'"
      assert sql =~ "ORDER BY 2 DESC"
      assert sql =~ "LIMIT 10"
      assert sql =~ "OFFSET 5"
    end

    test "accepts atom cube name" do
      dimension = %DimensionRef{
        name: :brand,
        module: TestCustomer,
        type: :string,
        sql: "brand_code"
      }

      measure = %MeasureRef{name: :count, module: TestCustomer, type: :count}

      sql =
        QueryBuilder.build(
          cube: :customer,
          columns: [dimension, measure]
        )

      assert sql =~ "FROM customer"
    end
  end

  describe "validate_columns!/1" do
    test "accepts valid columns" do
      dimension = %DimensionRef{
        name: :brand,
        module: TestCustomer,
        type: :string,
        sql: "brand_code"
      }

      measure = %MeasureRef{name: :count, module: TestCustomer, type: :count}

      assert :ok = QueryBuilder.validate_columns!([dimension, measure])
    end

    test "raises on empty list" do
      assert_raise ArgumentError, "columns cannot be empty", fn ->
        QueryBuilder.validate_columns!([])
      end
    end

    test "raises on non-list" do
      assert_raise ArgumentError, "columns must be a list", fn ->
        QueryBuilder.validate_columns!("invalid")
      end
    end

    test "raises on invalid column type" do
      assert_raise ArgumentError, ~r/Expected MeasureRef or DimensionRef/, fn ->
        QueryBuilder.validate_columns!([%{invalid: true}])
      end
    end
  end

  describe "build_select_clause/2" do
    test "builds SELECT with dimensions and measures" do
      dimension = %DimensionRef{
        name: :brand,
        module: TestCustomer,
        type: :string,
        sql: "brand_code"
      }

      measure = %MeasureRef{name: :count, module: TestCustomer, type: :count}

      sql = QueryBuilder.build_select_clause("customer", [dimension, measure])

      assert sql == "SELECT customer.brand, MEASURE(customer.count)"
    end
  end

  describe "build_group_by_clause/1" do
    test "builds GROUP BY for dimensions" do
      dim1 = %DimensionRef{name: :brand, module: TestCustomer, type: :string, sql: "brand_code"}
      dim2 = %DimensionRef{name: :market, module: TestCustomer, type: :string, sql: "market_code"}
      measure = %MeasureRef{name: :count, module: TestCustomer, type: :count}

      sql = QueryBuilder.build_group_by_clause([dim1, dim2, measure])

      assert sql == "GROUP BY 1, 2"
    end

    test "returns nil when no dimensions" do
      measure1 = %MeasureRef{name: :count, module: TestCustomer, type: :count}
      measure2 = %MeasureRef{name: :total, module: TestCustomer, type: :sum}

      assert QueryBuilder.build_group_by_clause([measure1, measure2]) == nil
    end

    test "handles dimensions at different positions" do
      measure1 = %MeasureRef{name: :count, module: TestCustomer, type: :count}
      dim1 = %DimensionRef{name: :brand, module: TestCustomer, type: :string, sql: "brand_code"}
      measure2 = %MeasureRef{name: :total, module: TestCustomer, type: :sum}
      dim2 = %DimensionRef{name: :market, module: TestCustomer, type: :string, sql: "market_code"}

      sql = QueryBuilder.build_group_by_clause([measure1, dim1, measure2, dim2])

      assert sql == "GROUP BY 2, 4"
    end
  end

  describe "build_order_by_clause/1" do
    test "builds ORDER BY with directions" do
      sql = QueryBuilder.build_order_by_clause([{1, :asc}, {2, :desc}])
      assert sql == "ORDER BY 1 ASC, 2 DESC"
    end

    test "builds ORDER BY with integer shortcuts" do
      sql = QueryBuilder.build_order_by_clause([1, 2, 3])
      assert sql == "ORDER BY 1, 2, 3"
    end

    test "handles mixed format" do
      sql = QueryBuilder.build_order_by_clause([1, {2, :desc}, 3, {4, :asc}])
      assert sql == "ORDER BY 1, 2 DESC, 3, 4 ASC"
    end
  end

  describe "extract_cube_name/1" do
    test "extracts cube name from columns" do
      dimension = %DimensionRef{
        name: :brand,
        module: TestCustomer,
        type: :string,
        sql: "brand_code"
      }

      measure = %MeasureRef{name: :count, module: TestCustomer, type: :count}

      assert QueryBuilder.extract_cube_name([dimension, measure]) == "customer"
    end

    test "raises on empty list" do
      assert_raise ArgumentError, "columns cannot be empty", fn ->
        QueryBuilder.extract_cube_name([])
      end
    end

    test "raises when columns are from different cubes" do
      defmodule TestOrders do
        def __schema__(:source), do: "orders"
      end

      dim1 = %DimensionRef{name: :brand, module: TestCustomer, type: :string, sql: "brand_code"}
      dim2 = %DimensionRef{name: :order_id, module: TestOrders, type: :string, sql: "order_id"}

      assert_raise ArgumentError, ~r/All columns must be from the same cube/, fn ->
        QueryBuilder.extract_cube_name([dim1, dim2])
      end
    end
  end
end
