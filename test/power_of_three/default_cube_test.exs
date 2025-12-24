defmodule PowerOfThree.DefaultCubeTest do
  use ExUnit.Case, async: true

  defmodule BasicSchema do
    @moduledoc false

    use Ecto.Schema
    use PowerOfThree

    schema "basic_table" do
      field(:name, :string)
      field(:email, :string)
      field(:age, :integer)
      field(:balance, :float)
      field(:active, :boolean)
      timestamps()
    end

    # Auto-generated cube (no block)
    cube(:basic_cube, sql_table: "basic_table")
  end

  defmodule ExplicitSchema do
    @moduledoc false

    use Ecto.Schema
    use PowerOfThree

    schema "explicit_table" do
      field(:name, :string)
      field(:age, :integer)
      field(:email, :string)
    end

    # Explicit block - should NOT auto-generate
    cube :explicit_cube, sql_table: "explicit_table" do
      dimension(:name, name: :full_name)
      measure(:count)
    end
  end

  describe "auto-generated dimensions" do
    test "generates dimensions for string fields" do
      dimensions = BasicSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      assert "name" in dimension_names
      assert "email" in dimension_names
    end

    test "generates dimension for boolean field" do
      dimensions = BasicSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      assert "active" in dimension_names
    end

    test "does not generate dimensions for numeric fields" do
      dimensions = BasicSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      # Integer and float fields should NOT be dimensions
      refute "age" in dimension_names
      refute "balance" in dimension_names
    end

    test "does not skip id field" do
      dimensions = BasicSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      # id should NOT be a dimension (it's numeric)
      refute "id" in dimension_names
    end
  end

  describe "auto-generated measures" do
    test "always generates count measure" do
      measures = BasicSchema.measures()
      measure_names = Enum.map(measures, & &1.name)

      assert :count in measure_names
    end

    test "generates sum for integer fields" do
      measures = BasicSchema.measures()
      measure_names = Enum.map(measures, & &1.name)

      assert :age_sum in measure_names
    end

    test "generates count_distinct for integer fields" do
      measures = BasicSchema.measures()
      measure_names = Enum.map(measures, & &1.name)

      assert :age_distinct in measure_names
    end

    test "generates sum for float fields" do
      measures = BasicSchema.measures()
      measure_names = Enum.map(measures, & &1.name)

      assert :balance_sum in measure_names
    end

    test "integer fields have both sum and count_distinct" do
      measures = BasicSchema.measures()
      measure_names = Enum.map(measures, & &1.name)

      # Age is an integer field, should have both measures
      assert :age_sum in measure_names
      assert :age_distinct in measure_names
    end
  end

  describe "accessor modules" do
    test "Dimensions module has functions for each dimension" do
      assert function_exported?(BasicSchema.Dimensions, :name, 0)
      assert function_exported?(BasicSchema.Dimensions, :email, 0)
      assert function_exported?(BasicSchema.Dimensions, :active, 0)
      assert function_exported?(BasicSchema.Dimensions, :inserted_at, 0)
      assert function_exported?(BasicSchema.Dimensions, :updated_at, 0)
    end

    test "Measures module has functions for each measure" do
      assert function_exported?(BasicSchema.Measures, :count, 0)
      assert function_exported?(BasicSchema.Measures, :id_sum, 0)
      assert function_exported?(BasicSchema.Measures, :id_distinct, 0)
      assert function_exported?(BasicSchema.Measures, :age_sum, 0)
      assert function_exported?(BasicSchema.Measures, :age_distinct, 0)
      assert function_exported?(BasicSchema.Measures, :balance_sum, 0)
    end

    test "can call accessor functions to get refs" do
      name_dim = BasicSchema.Dimensions.name()
      assert %PowerOfThree.DimensionRef{} = name_dim
      assert name_dim.name == "name"

      count_measure = BasicSchema.Measures.count()
      assert %PowerOfThree.MeasureRef{} = count_measure
      assert count_measure.name == "count"

      age_sum = BasicSchema.Measures.age_sum()
      assert %PowerOfThree.MeasureRef{} = age_sum
      assert age_sum.name == :age_sum
    end
  end

  describe "backward compatibility - explicit block" do
    test "explicit block overrides auto-generation" do
      dimensions = ExplicitSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      # Should only have the one dimension defined in block
      assert length(dimensions) == 1
      assert :full_name in dimension_names
      refute "name" in dimension_names
      refute "email" in dimension_names
    end

    test "explicit block measure count" do
      measures = ExplicitSchema.measures()
      measure_names = Enum.map(measures, & &1.name)

      # Should only have count measure from block
      assert length(measures) == 1
      assert :count in measure_names
      refute :age_sum in measure_names
      refute :age_distinct in measure_names
    end

    test "explicit block accessor module" do
      # Should have accessor for custom dimension name
      assert function_exported?(ExplicitSchema.Dimensions, :full_name, 0)
      refute function_exported?(ExplicitSchema.Dimensions, :name, 0)
    end
  end

  describe "YAML generation" do
    test "generates measures attribute with auto-generated measures" do
      measures = BasicSchema.__info__(:attributes)[:measures]

      assert is_list(measures)
      assert length(measures) > 1

      # Check for count measure
      count_measure = Enum.find(measures, fn m -> m.name == "count" end)
      assert count_measure
      assert count_measure.type == :count

      # Check for auto-generated sum measure
      age_sum = Enum.find(measures, fn m -> m.name == :age_sum end)
      assert age_sum
      assert age_sum.type == :sum
    end

    test "generates dimensions attribute with auto-generated dimensions" do
      dimensions = BasicSchema.__info__(:attributes)[:dimensions]

      assert is_list(dimensions)
      assert length(dimensions) > 1

      # Check for string dimension
      name_dim = Enum.find(dimensions, fn d -> d.name == "name" end)
      assert name_dim
      assert name_dim.type == :string
    end
  end

  describe "count of dimensions and measures" do
    test "counts all auto-generated dimensions" do
      dimensions = BasicSchema.dimensions()

      # Should have: name, email, active
      assert length(dimensions) == 3
    end

    test "counts all auto-generated measures" do
      measures = BasicSchema.measures()

      # Should have:
      # - count (1)
      # - id_sum, id_distinct (2)
      # - age_sum, age_distinct (2)
      # - balance_sum (1)
      # Total: 6 measures
      assert length(measures) == 6
    end
  end
end
