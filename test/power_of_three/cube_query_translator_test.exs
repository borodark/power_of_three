defmodule PowerOfThree.CubeQueryTranslatorTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.{CubeQueryTranslator, QueryError}

  # Test schema for translator tests
  defmodule TestSchema do
    use Ecto.Schema
    use PowerOfThree

    schema "customer" do
      field(:first_name, :string)
      field(:brand_code, :string)
      field(:market_code, :string)
    end

    cube :of_customers,
      sql_table: "customer" do
      dimension(:first_name, name: :given_name)
      dimension(:brand_code, name: :brand)
      dimension(:market_code, name: :market)

      measure(:count)
    end
  end

  describe "to_cube_query/1" do
    test "translates simple query with dimension and measure" do
      opts = [
        columns: [
          TestSchema.Dimensions.brand(),
          TestSchema.Measures.count()
        ]
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      assert cube_query["dimensions"] == ["of_customers.brand"]
      assert cube_query["measures"] == ["of_customers.count"]
      refute Map.has_key?(cube_query, "filters")
      refute Map.has_key?(cube_query, "order")
      refute Map.has_key?(cube_query, "limit")
    end

    test "translates query with multiple dimensions" do
      opts = [
        columns: [
          TestSchema.Dimensions.brand(),
          TestSchema.Dimensions.market(),
          TestSchema.Measures.count()
        ]
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      assert cube_query["dimensions"] == ["of_customers.brand", "of_customers.market"]
      assert cube_query["measures"] == ["of_customers.count"]
    end

    test "translates query with limit" do
      opts = [
        columns: [TestSchema.Measures.count()],
        limit: 10
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      assert cube_query["limit"] == 10
    end

    test "translates query with offset" do
      opts = [
        columns: [TestSchema.Measures.count()],
        offset: 5
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      assert cube_query["offset"] == 5
    end

    test "translates query with limit and offset" do
      opts = [
        columns: [TestSchema.Measures.count()],
        limit: 10,
        offset: 20
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      assert cube_query["limit"] == 10
      assert cube_query["offset"] == 20
    end

    test "returns error when columns are missing" do
      opts = [limit: 10]

      {:error, error} = CubeQueryTranslator.to_cube_query(opts)

      assert %QueryError{} = error
      assert error.type == :translation_error
      assert String.contains?(error.message, "Missing required option: columns")
    end
  end

  describe "dimension_to_cube_name/1" do
    test "converts DimensionRef to cube name format" do
      dim = TestSchema.Dimensions.brand()

      cube_name = CubeQueryTranslator.dimension_to_cube_name(dim)

      assert cube_name == "of_customers.brand"
    end

    test "handles dimensions with different names" do
      dim = TestSchema.Dimensions.given_name()

      cube_name = CubeQueryTranslator.dimension_to_cube_name(dim)

      assert cube_name == "of_customers.given_name"
    end
  end

  describe "measure_to_cube_name/1" do
    test "converts MeasureRef to cube name format" do
      measure = TestSchema.Measures.count()

      cube_name = CubeQueryTranslator.measure_to_cube_name(measure)

      assert cube_name == "of_customers.count"
    end
  end

  describe "WHERE clause parsing - equals" do
    test "parses simple equals filter with string value" do
      opts = [
        columns: [
          TestSchema.Dimensions.brand(),
          TestSchema.Measures.count()
        ],
        where: "brand_code = 'BudLight'"
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      assert length(cube_query["filters"]) == 1

      filter = List.first(cube_query["filters"])
      assert filter["member"] == "of_customers.brand"
      assert filter["operator"] == "equals"
      assert filter["values"] == ["BudLight"]
    end

    test "parses equals filter with numeric value" do
      opts = [
        columns: [
          TestSchema.Dimensions.brand(),
          TestSchema.Measures.count()
        ],
        where: "brand_code = 123"
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      filter = List.first(cube_query["filters"])
      assert filter["operator"] == "equals"
      assert filter["values"] == ["123"]
    end
  end

  describe "WHERE clause parsing - not equals" do
    test "parses not equals filter" do
      opts = [
        columns: [
          TestSchema.Dimensions.brand(),
          TestSchema.Measures.count()
        ],
        where: "brand_code != 'Unknown'"
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      filter = List.first(cube_query["filters"])
      assert filter["operator"] == "notEquals"
      assert filter["values"] == ["Unknown"]
    end
  end

  describe "WHERE clause parsing - comparison operators" do
    test "parses greater than filter" do
      opts = [
        columns: [TestSchema.Measures.count()],
        where: "count > 100"
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      filter = List.first(cube_query["filters"])
      assert filter["operator"] == "gt"
      assert filter["values"] == ["100"]
    end

    test "parses greater than or equal filter" do
      opts = [
        columns: [TestSchema.Measures.count()],
        where: "count >= 50"
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      filter = List.first(cube_query["filters"])
      assert filter["operator"] == "gte"
      assert filter["values"] == ["50"]
    end

    test "parses less than filter" do
      opts = [
        columns: [TestSchema.Measures.count()],
        where: "count < 1000"
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      filter = List.first(cube_query["filters"])
      assert filter["operator"] == "lt"
      assert filter["values"] == ["1000"]
    end

    test "parses less than or equal filter" do
      opts = [
        columns: [TestSchema.Measures.count()],
        where: "count <= 500"
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      filter = List.first(cube_query["filters"])
      assert filter["operator"] == "lte"
      assert filter["values"] == ["500"]
    end
  end

  describe "WHERE clause parsing - IN operator" do
    test "parses IN filter with multiple values" do
      opts = [
        columns: [
          TestSchema.Dimensions.brand(),
          TestSchema.Measures.count()
        ],
        where: "brand_code IN ('BudLight', 'Dos Equis', 'Blue Moon')"
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      filter = List.first(cube_query["filters"])
      assert filter["operator"] == "set"
      assert filter["values"] == ["'BudLight'", "'Dos Equis'", "'Blue Moon'"]
    end

    test "parses IN filter case insensitive" do
      opts = [
        columns: [
          TestSchema.Dimensions.brand(),
          TestSchema.Measures.count()
        ],
        where: "brand_code in ('BudLight', 'Corona')"
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      filter = List.first(cube_query["filters"])
      assert filter["operator"] == "set"
    end
  end

  describe "WHERE clause parsing - edge cases" do
    test "handles empty WHERE clause" do
      opts = [
        columns: [TestSchema.Measures.count()],
        where: ""
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      refute Map.has_key?(cube_query, "filters")
    end

    test "handles nil WHERE clause" do
      opts = [
        columns: [TestSchema.Measures.count()],
        where: nil
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      refute Map.has_key?(cube_query, "filters")
    end

    test "returns error for complex WHERE clause" do
      opts = [
        columns: [TestSchema.Measures.count()],
        where: "brand_code = 'BudLight' AND market_code = 'US'"
      ]

      {:error, error} = CubeQueryTranslator.to_cube_query(opts)

      assert %QueryError{} = error
      assert error.type == :translation_error
      assert String.contains?(error.message, "Complex WHERE clause")
    end

    test "returns error for unsupported WHERE pattern" do
      opts = [
        columns: [TestSchema.Measures.count()],
        where: "EXTRACT(YEAR FROM created_at) = 2023"
      ]

      {:error, error} = CubeQueryTranslator.to_cube_query(opts)

      assert %QueryError{} = error
      assert error.type == :translation_error
    end
  end

  describe "ORDER BY translation" do
    test "translates order by with direction" do
      opts = [
        columns: [
          TestSchema.Dimensions.brand(),
          TestSchema.Measures.count()
        ],
        order_by: [{2, :desc}]
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      assert cube_query["order"] == [["of_customers.count", "desc"]]
    end

    test "translates order by ascending" do
      opts = [
        columns: [
          TestSchema.Dimensions.brand(),
          TestSchema.Measures.count()
        ],
        order_by: [{1, :asc}]
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      assert cube_query["order"] == [["of_customers.brand", "asc"]]
    end

    test "translates order by without direction (defaults to asc)" do
      opts = [
        columns: [
          TestSchema.Dimensions.brand(),
          TestSchema.Measures.count()
        ],
        order_by: [1]
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      assert cube_query["order"] == [["of_customers.brand", "asc"]]
    end

    test "translates multiple order by clauses" do
      opts = [
        columns: [
          TestSchema.Dimensions.brand(),
          TestSchema.Dimensions.market(),
          TestSchema.Measures.count()
        ],
        order_by: [{1, :asc}, {3, :desc}]
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      assert cube_query["order"] == [
               ["of_customers.brand", "asc"],
               ["of_customers.count", "desc"]
             ]
    end

    test "handles empty order_by" do
      opts = [
        columns: [TestSchema.Measures.count()],
        order_by: []
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      refute Map.has_key?(cube_query, "order")
    end

    test "handles nil order_by" do
      opts = [
        columns: [TestSchema.Measures.count()],
        order_by: nil
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      refute Map.has_key?(cube_query, "order")
    end
  end

  describe "complex query translation" do
    test "translates query with all options" do
      opts = [
        columns: [
          TestSchema.Dimensions.brand(),
          TestSchema.Dimensions.market(),
          TestSchema.Measures.count()
        ],
        where: "brand_code = 'BudLight'",
        order_by: [{3, :desc}],
        limit: 10,
        offset: 5
      ]

      {:ok, cube_query} = CubeQueryTranslator.to_cube_query(opts)

      assert cube_query["dimensions"] == ["of_customers.brand", "of_customers.market"]
      assert cube_query["measures"] == ["of_customers.count"]
      assert length(cube_query["filters"]) == 1
      assert cube_query["order"] == [["of_customers.count", "desc"]]
      assert cube_query["limit"] == 10
      assert cube_query["offset"] == 5
    end
  end
end
