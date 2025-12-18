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
    test "measures/0 returns list of MeasureRef structs" do
      measures = TestCube.measures()
      assert is_list(measures)
      assert length(measures) == 3
      assert Enum.all?(measures, fn m -> match?(%MeasureRef{}, m) end)
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

    test "measures list contains all defined measures" do
      measures = TestCube.measures()
      names = Enum.map(measures, & &1.name)

      assert "count" in names or :count in names
      assert :unique_emails in names
      assert :aquarii in names
    end

    test "measures from list match direct accessors" do
      measures_list = TestCube.measures()
      count_from_list = Enum.find(measures_list, fn m -> m.name == "count" or m.name == :count end)
      count_from_accessor = TestCube.Measures.count()

      assert count_from_list == count_from_accessor
    end

    test "MeasureRef.to_sql_column works with generated refs" do
      measure = TestCube.Measures.count()
      sql = MeasureRef.to_sql_column(measure)

      assert sql == "MEASURE(customer.count)"
    end
  end

  describe "dimensions accessor" do
    test "dimensions/0 returns list of DimensionRef structs" do
      dimensions = TestCube.dimensions()
      assert is_list(dimensions)
      assert length(dimensions) == 4
      assert Enum.all?(dimensions, fn d -> match?(%DimensionRef{}, d) end)
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

    test "dimensions list contains all defined dimensions" do
      dimensions = TestCube.dimensions()
      names = Enum.map(dimensions, & &1.name)

      assert "email" in names
      assert :brand in names
      assert :brand_market in names
      assert :inserted_at in names
    end

    test "dimensions from list match direct accessors" do
      dimensions_list = TestCube.dimensions()
      email_from_list = Enum.find(dimensions_list, fn d -> d.name == "email" end)
      email_from_accessor = TestCube.Dimensions.email()

      assert email_from_list == email_from_accessor
    end

    test "DimensionRef.to_sql_column works with generated refs" do
      dimension = TestCube.Dimensions.email()
      sql = DimensionRef.to_sql_column(dimension)

      assert sql == "customer.email"
    end
  end

  describe "dot-accessible syntax via module" do
    test "can access measures with dot syntax via module" do
      # TestCube.Measures.count()
      measure = TestCube.Measures.count()

      assert %MeasureRef{} = measure
      assert measure.name == "count"
    end

    test "can access dimensions with dot syntax via module" do
      # TestCube.Dimensions.email()
      dimension = TestCube.Dimensions.email()

      assert %DimensionRef{} = dimension
      assert dimension.name == "email"
    end

    test "can build query references using module accessors" do
      # Simulate building a query with refs
      columns = [
        TestCube.Dimensions.brand(),
        TestCube.Dimensions.email(),
        TestCube.Measures.count(),
        TestCube.Measures.unique_emails()
      ]

      assert length(columns) == 4
      assert Enum.count(columns, &match?(%DimensionRef{}, &1)) == 2
      assert Enum.count(columns, &match?(%MeasureRef{}, &1)) == 2
    end

    test "can build query references from lists" do
      # Get all dimensions and measures as lists
      dimensions = TestCube.dimensions()
      measures = TestCube.measures()

      # Pick specific ones
      brand = Enum.find(dimensions, fn d -> d.name == :brand end)
      email = Enum.find(dimensions, fn d -> d.name == "email" end)
      count = Enum.find(measures, fn m -> m.name == "count" or m.name == :count end)

      columns = [brand, email, count]

      assert length(columns) == 3
      assert Enum.count(columns, &match?(%DimensionRef{}, &1)) == 2
      assert Enum.count(columns, &match?(%MeasureRef{}, &1)) == 1
    end
  end

  describe "module existence and functionality" do
    test "Measures module exists and is accessible" do
      assert Code.ensure_loaded?(TestCube.Measures)
    end

    test "Dimensions module exists and is accessible" do
      assert Code.ensure_loaded?(TestCube.Dimensions)
    end

    test "accessor modules are proper modules" do
      # Verify they're actual modules, not just atoms
      assert is_atom(TestCube.Measures)
      assert is_atom(TestCube.Dimensions)
      assert function_exported?(TestCube.Measures, :__measure_names__, 0)
      assert function_exported?(TestCube.Dimensions, :__dimension_names__, 0)
    end

    test "measures/0 returns list, not module" do
      result = TestCube.measures()
      assert is_list(result)
      refute result == TestCube.Measures
    end

    test "dimensions/0 returns list, not module" do
      result = TestCube.dimensions()
      assert is_list(result)
      refute result == TestCube.Dimensions
    end
  end
end
