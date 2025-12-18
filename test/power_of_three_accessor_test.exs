defmodule PowerOfThreeAccessorTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.{MeasureRef, DimensionRef}

  defmodule TestCube do
    @moduledoc false
    use Ecto.Schema
    use PowerOfThree

    schema "customer" do
      field(:email, :string)
      field(:brand_code, :string)
      field(:market_code, :string)
      field(:birthday_day, :integer)
      field(:birthday_month, :integer)
      timestamps()
    end

    cube :test_cube,
      sql_table: "customer",
      title: "Test Cube",
      description: "Test cube for accessor testing" do
      # Dimensions
      dimension(:email, description: "Customer email")
      dimension(:brand_code, name: :brand, description: "Brand code")
      dimension([:brand_code, :market_code], name: :brand_market, primary_key: true)

      # Measures
      measure(:count, description: "Total count")

      measure(:email,
        name: :unique_emails,
        type: :count_distinct,
        description: "Unique email addresses"
      )

      measure(:email,
        name: :aquarii,
        type: :count_distinct,
        description: "Aquarius customers",
        filters: [
          %{
            sql:
              "(birthday_month = 1 AND birthday_day >= 20) OR (birthday_month = 2 AND birthday_day <= 18)"
          }
        ]
      )

      # Time dimension
      time_dimensions()
    end
  end

  describe "measures accessor" do
    test "measures/0 returns Measures module" do
      assert TestCube.measures() == TestCube.Measures
    end

    test "Measures module exists" do
      assert Code.ensure_loaded?(TestCube.Measures)
    end

    test "Measures module has __measure_names__/0" do
      names = TestCube.Measures.__measure_names__()
      assert is_list(names)
      assert length(names) == 3
    end

    test "count measure accessor returns MeasureRef" do
      measure = TestCube.Measures.count()

      assert %MeasureRef{} = measure
      assert measure.name == "count"
      assert measure.module == TestCube
      assert measure.type == :count
      assert measure.description == "Total count"
    end

    test "unique_emails measure accessor returns MeasureRef" do
      measure = TestCube.Measures.unique_emails()

      assert %MeasureRef{} = measure
      assert measure.name == :unique_emails
      assert measure.module == TestCube
      assert measure.type == :count_distinct
      assert measure.description == "Unique email addresses"
      assert measure.sql == :email
    end

    test "aquarii measure accessor returns MeasureRef with filters" do
      measure = TestCube.Measures.aquarii()

      assert %MeasureRef{} = measure
      assert measure.name == :aquarii
      assert measure.type == :count_distinct
      assert measure.description == "Aquarius customers"
      assert is_list(measure.filters)
      assert length(measure.filters) == 1
    end

    test "measure accessors work via module reference" do
      measures_module = TestCube.measures()
      measure = measures_module.count()

      assert %MeasureRef{} = measure
      assert measure.name == "count"
    end

    test "MeasureRef.to_sql_column works with generated refs" do
      measure = TestCube.Measures.count()
      sql = MeasureRef.to_sql_column(measure)

      assert sql == "MEASURE(customer.count)"
    end
  end

  describe "dimensions accessor" do
    test "dimensions/0 returns Dimensions module" do
      assert TestCube.dimensions() == TestCube.Dimensions
    end

    test "Dimensions module exists" do
      assert Code.ensure_loaded?(TestCube.Dimensions)
    end

    test "Dimensions module has __dimension_names__/0" do
      names = TestCube.Dimensions.__dimension_names__()
      assert is_list(names)
      # email, brand, brand_market, inserted_at (from time_dimensions)
      assert length(names) == 4
    end

    test "email dimension accessor returns DimensionRef" do
      dimension = TestCube.Dimensions.email()

      assert %DimensionRef{} = dimension
      assert dimension.name == "email"
      assert dimension.module == TestCube
      assert dimension.type == :string
      assert dimension.description == "Customer email"
      assert dimension.sql == "email"
    end

    test "brand dimension accessor returns DimensionRef with custom name" do
      dimension = TestCube.Dimensions.brand()

      assert %DimensionRef{} = dimension
      assert dimension.name == :brand
      assert dimension.module == TestCube
      assert dimension.type == :string
      assert dimension.description == "Brand code"
    end

    test "brand_market dimension accessor returns DimensionRef with primary_key" do
      dimension = TestCube.Dimensions.brand_market()

      assert %DimensionRef{} = dimension
      assert dimension.name == :brand_market
      assert dimension.primary_key == true
      assert dimension.sql == "brand_code||market_code"
    end

    test "inserted_at time dimension accessor returns DimensionRef" do
      dimension = TestCube.Dimensions.inserted_at()

      assert %DimensionRef{} = dimension
      assert dimension.name == :inserted_at
      assert dimension.type == :time
      assert dimension.description == "inserted_at"
    end

    test "dimension accessors work via module reference" do
      dimensions_module = TestCube.dimensions()
      dimension = dimensions_module.email()

      assert %DimensionRef{} = dimension
      assert dimension.name == "email"
    end

    test "DimensionRef.to_sql_column works with generated refs" do
      dimension = TestCube.Dimensions.email()
      sql = DimensionRef.to_sql_column(dimension)

      assert sql == "customer.email"
    end
  end

  describe "dot-accessible syntax" do
    test "can access measures with dot syntax" do
      # TestCube.measures.count()
      measure = TestCube.measures().count()

      assert %MeasureRef{} = measure
      assert measure.name == "count"
    end

    test "can access dimensions with dot syntax" do
      # TestCube.dimensions.email()
      dimension = TestCube.dimensions().email()

      assert %DimensionRef{} = dimension
      assert dimension.name == "email"
    end

    test "can build query references" do
      # Simulate building a query with refs
      columns = [
        TestCube.dimensions().brand(),
        TestCube.dimensions().email(),
        TestCube.measures().count(),
        TestCube.measures().unique_emails()
      ]

      assert length(columns) == 4
      assert Enum.count(columns, &match?(%DimensionRef{}, &1)) == 2
      assert Enum.count(columns, &match?(%MeasureRef{}, &1)) == 2
    end
  end

  describe "module existence and functionality" do
    test "Measures module exists and is accessible" do
      assert Code.ensure_loaded?(TestCube.Measures)
      assert TestCube.measures() == TestCube.Measures
    end

    test "Dimensions module exists and is accessible" do
      assert Code.ensure_loaded?(TestCube.Dimensions)
      assert TestCube.dimensions() == TestCube.Dimensions
    end

    test "accessor modules are proper modules" do
      # Verify they're actual modules, not just atoms
      assert is_atom(TestCube.Measures)
      assert is_atom(TestCube.Dimensions)
      assert function_exported?(TestCube.Measures, :__measure_names__, 0)
      assert function_exported?(TestCube.Dimensions, :__dimension_names__, 0)
    end
  end
end
