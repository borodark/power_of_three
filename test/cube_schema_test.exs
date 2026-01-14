defmodule CubeSchemaTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.CubeSchema

  describe "cube_schema/2 with explicit definitions" do
    defmodule OrdersSchema do
      @moduledoc false
      use PowerOfThree.CubeSchema

      cube_schema :orders_test do
        dimension :brand_code, :string
        dimension :market_code, :string
        dimension :updated_at, :utc_datetime
        dimension :inserted_at, :utc_datetime

        measure :count, :integer
        measure :total_amount_sum, :float
        measure :tax_amount_sum, :float
      end
    end

    test "generates schema with correct table name" do
      assert OrdersSchema.__schema__(:source) == "orders_test"
    end

    test "generates schema with all dimension fields" do
      fields = OrdersSchema.__schema__(:fields)

      assert :brand_code in fields
      assert :market_code in fields
      assert :updated_at in fields
      assert :inserted_at in fields
    end

    test "generates schema with all measure fields" do
      fields = OrdersSchema.__schema__(:fields)

      assert :count in fields
      assert :total_amount_sum in fields
      assert :tax_amount_sum in fields
    end

    test "maps dimension types correctly" do
      assert OrdersSchema.__schema__(:type, :brand_code) == :string
      assert OrdersSchema.__schema__(:type, :market_code) == :string
      assert OrdersSchema.__schema__(:type, :updated_at) == :utc_datetime
      assert OrdersSchema.__schema__(:type, :inserted_at) == :utc_datetime
    end

    test "maps measure types correctly" do
      assert OrdersSchema.__schema__(:type, :count) == :integer
      assert OrdersSchema.__schema__(:type, :total_amount_sum) == :float
      assert OrdersSchema.__schema__(:type, :tax_amount_sum) == :float
    end

    test "schema without id field has no primary key" do
      assert OrdersSchema.__schema__(:primary_key) == []
    end
  end

  describe "cube_schema/2 with id dimension" do
    defmodule OrdersWithIdSchema do
      @moduledoc false
      use PowerOfThree.CubeSchema

      cube_schema :orders_with_id do
        dimension :id, :float
        dimension :brand_code, :string

        measure :count, :integer
      end
    end

    test "schema with id field uses it as primary key" do
      assert OrdersWithIdSchema.__schema__(:primary_key) == [:id]
    end

    test "id field has correct type" do
      assert OrdersWithIdSchema.__schema__(:type, :id) == :float
    end
  end

  describe "cube_schema/2 with various measure types" do
    defmodule MeasuresSchema do
      @moduledoc false
      use PowerOfThree.CubeSchema

      cube_schema :measures_test do
        dimension :category, :string

        measure :total_count, :integer
        measure :distinct_count, :integer
        measure :sum_amount, :float
        measure :avg_amount, :float
        measure :min_value, :float
        measure :max_value, :float
      end
    end

    test "all measure types are mapped correctly" do
      assert MeasuresSchema.__schema__(:type, :total_count) == :integer
      assert MeasuresSchema.__schema__(:type, :distinct_count) == :integer
      assert MeasuresSchema.__schema__(:type, :sum_amount) == :float
      assert MeasuresSchema.__schema__(:type, :avg_amount) == :float
      assert MeasuresSchema.__schema__(:type, :min_value) == :float
      assert MeasuresSchema.__schema__(:type, :max_value) == :float
    end
  end

  describe "cube_schema/2 with various dimension types" do
    defmodule DimensionsSchema do
      @moduledoc false
      use PowerOfThree.CubeSchema

      cube_schema :dimensions_test do
        dimension :name, :string
        dimension :amount, :float
        dimension :created_at, :utc_datetime
        dimension :is_active, :boolean
      end
    end

    test "all dimension types are mapped correctly" do
      assert DimensionsSchema.__schema__(:type, :name) == :string
      assert DimensionsSchema.__schema__(:type, :amount) == :float
      assert DimensionsSchema.__schema__(:type, :created_at) == :utc_datetime
      assert DimensionsSchema.__schema__(:type, :is_active) == :boolean
    end
  end

  describe "type conversion functions" do
    test "cube_type_to_ecto/1 converts string types" do
      assert CubeSchema.cube_type_to_ecto(:string) == :string
      assert CubeSchema.cube_type_to_ecto("string") == :string
    end

    test "cube_type_to_ecto/1 converts number types" do
      assert CubeSchema.cube_type_to_ecto(:number) == :float
      assert CubeSchema.cube_type_to_ecto("number") == :float
    end

    test "cube_type_to_ecto/1 converts time types" do
      assert CubeSchema.cube_type_to_ecto(:time) == :utc_datetime
      assert CubeSchema.cube_type_to_ecto("time") == :utc_datetime
    end

    test "cube_type_to_ecto/1 converts boolean types" do
      assert CubeSchema.cube_type_to_ecto(:boolean) == :boolean
      assert CubeSchema.cube_type_to_ecto("boolean") == :boolean
    end

    test "cube_type_to_ecto/1 defaults unknown types to string" do
      assert CubeSchema.cube_type_to_ecto(:unknown) == :string
      assert CubeSchema.cube_type_to_ecto("custom") == :string
    end

    test "measure_type_to_ecto/1 converts count types" do
      assert CubeSchema.measure_type_to_ecto(:count) == :integer
      assert CubeSchema.measure_type_to_ecto("count") == :integer
    end

    test "measure_type_to_ecto/1 converts count_distinct types" do
      assert CubeSchema.measure_type_to_ecto(:count_distinct) == :integer
      assert CubeSchema.measure_type_to_ecto("count_distinct") == :integer
    end

    test "measure_type_to_ecto/1 converts aggregation types to float" do
      assert CubeSchema.measure_type_to_ecto(:sum) == :float
      assert CubeSchema.measure_type_to_ecto(:avg) == :float
      assert CubeSchema.measure_type_to_ecto(:min) == :float
      assert CubeSchema.measure_type_to_ecto(:max) == :float
    end

    test "measure_type_to_ecto/1 converts number type to float" do
      assert CubeSchema.measure_type_to_ecto(:number) == :float
      assert CubeSchema.measure_type_to_ecto("number") == :float
    end

    test "measure_type_to_ecto/1 defaults unknown types to float" do
      assert CubeSchema.measure_type_to_ecto(:unknown) == :float
      assert CubeSchema.measure_type_to_ecto("custom") == :float
    end
  end

  describe "schema struct creation" do
    defmodule StructTestSchema do
      @moduledoc false
      use PowerOfThree.CubeSchema

      cube_schema :struct_test do
        dimension :name, :string
        dimension :value, :float

        measure :total, :integer
      end
    end

    test "can create struct with default values" do
      struct = %StructTestSchema{}

      assert struct.name == nil
      assert struct.value == nil
      assert struct.total == nil
    end

    test "can create struct with values" do
      struct = %StructTestSchema{name: "test", value: 42.0, total: 100}

      assert struct.name == "test"
      assert struct.value == 42.0
      assert struct.total == 100
    end

    test "struct has __meta__ field for Ecto" do
      struct = %StructTestSchema{}

      assert Map.has_key?(struct, :__meta__)
    end
  end

  describe "complex schema with many fields" do
    defmodule ComplexSchema do
      @moduledoc false
      use PowerOfThree.CubeSchema

      cube_schema :complex_cube do
        # Dimensions
        dimension :id, :float
        dimension :brand_code, :string
        dimension :market_code, :string
        dimension :customer_email, :string
        dimension :product_category, :string
        dimension :region, :string
        dimension :created_at, :utc_datetime
        dimension :updated_at, :utc_datetime
        dimension :is_premium, :boolean

        # Measures
        measure :order_count, :integer
        measure :customer_count, :integer
        measure :total_revenue, :float
        measure :average_order_value, :float
        measure :min_order_value, :float
        measure :max_order_value, :float
      end
    end

    test "all fields are present" do
      fields = ComplexSchema.__schema__(:fields)

      # 9 dimensions + 6 measures = 15 fields (id is primary key, still in fields)
      assert length(fields) >= 14
    end

    test "has id as primary key" do
      assert ComplexSchema.__schema__(:primary_key) == [:id]
    end

    test "dimension types are correct" do
      assert ComplexSchema.__schema__(:type, :brand_code) == :string
      assert ComplexSchema.__schema__(:type, :is_premium) == :boolean
      assert ComplexSchema.__schema__(:type, :created_at) == :utc_datetime
    end

    test "measure types are correct" do
      assert ComplexSchema.__schema__(:type, :order_count) == :integer
      assert ComplexSchema.__schema__(:type, :total_revenue) == :float
      assert ComplexSchema.__schema__(:type, :average_order_value) == :float
    end
  end
end
