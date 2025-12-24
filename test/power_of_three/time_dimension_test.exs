defmodule PowerOfThree.TimeDimensionTest do
  use ExUnit.Case, async: true

  describe "auto-generated time dimensions" do
    defmodule TimeSchema do
      use Ecto.Schema
      use PowerOfThree

      schema "time_test" do
        field :name, :string
        field :created_date, :date
        field :created_time, :time
        field :created_at_naive, :naive_datetime
        field :created_at_usec, :naive_datetime_usec
        field :modified_at, :utc_datetime
        field :modified_at_usec, :utc_datetime_usec
        field :count, :integer
      end

      # Auto-generate cube (no block)
      cube :time_cube, sql_table: "time_test"
    end

    test "generates time dimensions for :date fields" do
      dimensions = TimeSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      assert "created_date" in dimension_names

      date_dim = Enum.find(dimensions, &(&1.name == "created_date"))
      assert date_dim.type == :time
      assert date_dim.sql == "created_date"
    end

    test "generates time dimensions for :time fields" do
      dimensions = TimeSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      assert "created_time" in dimension_names

      time_dim = Enum.find(dimensions, &(&1.name == "created_time"))
      assert time_dim.type == :time
    end

    test "generates time dimensions for :naive_datetime fields" do
      dimensions = TimeSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      assert "created_at_naive" in dimension_names

      dt_dim = Enum.find(dimensions, &(&1.name == "created_at_naive"))
      assert dt_dim.type == :time
      assert dt_dim.sql == "created_at_naive"
    end

    test "generates time dimensions for :naive_datetime_usec fields" do
      dimensions = TimeSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      assert "created_at_usec" in dimension_names

      dt_dim = Enum.find(dimensions, &(&1.name == "created_at_usec"))
      assert dt_dim.type == :time
    end

    test "generates time dimensions for :utc_datetime fields" do
      dimensions = TimeSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      assert "modified_at" in dimension_names

      dt_dim = Enum.find(dimensions, &(&1.name == "modified_at"))
      assert dt_dim.type == :time
    end

    test "generates time dimensions for :utc_datetime_usec fields" do
      dimensions = TimeSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      assert "modified_at_usec" in dimension_names

      dt_dim = Enum.find(dimensions, &(&1.name == "modified_at_usec"))
      assert dt_dim.type == :time
    end

    test "time dimension accessors work" do
      # Verify accessor functions exist and return proper DimensionRef structs
      assert %PowerOfThree.DimensionRef{type: :time} = TimeSchema.Dimensions.created_date()
      assert %PowerOfThree.DimensionRef{type: :time} = TimeSchema.Dimensions.created_time()
      assert %PowerOfThree.DimensionRef{type: :time} = TimeSchema.Dimensions.created_at_naive()
      assert %PowerOfThree.DimensionRef{type: :time} = TimeSchema.Dimensions.created_at_usec()
      assert %PowerOfThree.DimensionRef{type: :time} = TimeSchema.Dimensions.modified_at()
      assert %PowerOfThree.DimensionRef{type: :time} = TimeSchema.Dimensions.modified_at_usec()
    end

    test "does not generate time dimensions for non-time fields" do
      dimensions = TimeSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      # String field should be generated but not as time type
      assert "name" in dimension_names
      name_dim = Enum.find(dimensions, &(&1.name == "name"))
      assert name_dim.type == :string

      # Integer field should NOT be a dimension
      refute "count" in dimension_names
    end

    test "all time dimensions have correct type" do
      dimensions = TimeSchema.dimensions()

      time_dimensions =
        Enum.filter(dimensions, fn dim ->
          dim.name in [
            "created_date",
            "created_time",
            "created_at_naive",
            "created_at_usec",
            "modified_at",
            "modified_at_usec"
          ]
        end)

      # All time-related dimensions should have type :time
      assert length(time_dimensions) == 6

      Enum.each(time_dimensions, fn dim ->
        assert dim.type == :time,
               "Expected #{dim.name} to have type :time, but got #{inspect(dim.type)}"
      end)
    end

    test "YAML generation includes time dimensions with correct type" do
      # Note: This verifies the YAML structure would be correct
      dimensions = TimeSchema.dimensions()

      created_at_dim = Enum.find(dimensions, &(&1.name == "created_at_naive"))

      assert created_at_dim.type == :time
      assert created_at_dim.meta.ecto_field == :created_at_naive
      assert created_at_dim.meta.ecto_field_type == :naive_datetime
    end
  end

  describe "time dimension metadata" do
    defmodule MetaTimeSchema do
      use Ecto.Schema
      use PowerOfThree

      schema "meta_time" do
        field :event_date, :date
        field :event_datetime, :naive_datetime
      end

      cube :meta_time_cube, sql_table: "meta_time"
    end

    test "time dimensions preserve Ecto field type metadata" do
      dimensions = MetaTimeSchema.dimensions()

      date_dim = Enum.find(dimensions, &(&1.name == "event_date"))
      assert date_dim.meta.ecto_field_type == :date

      datetime_dim = Enum.find(dimensions, &(&1.name == "event_datetime"))
      assert datetime_dim.meta.ecto_field_type == :naive_datetime
    end

    test "time dimensions have correct SQL field references" do
      dimensions = MetaTimeSchema.dimensions()

      date_dim = Enum.find(dimensions, &(&1.name == "event_date"))
      assert date_dim.sql == "event_date"

      datetime_dim = Enum.find(dimensions, &(&1.name == "event_datetime"))
      assert datetime_dim.sql == "event_datetime"
    end
  end

  describe "time dimension granularity support" do
    # Note: Granularity is specified at query time, not in cube definition
    # These tests verify the structure supports granularity queries

    defmodule GranularitySchema do
      use Ecto.Schema
      use PowerOfThree

      schema "events" do
        field :name, :string
        field :occurred_at, :naive_datetime
      end

      cube :events, sql_table: "events"
    end

    test "time dimensions are compatible with granularity queries" do
      occurred_dim = GranularitySchema.Dimensions.occurred_at()

      # Verify the dimension has the structure needed for granularity queries
      assert occurred_dim.type == :time
      assert occurred_dim.name == "occurred_at"
      assert occurred_dim.sql == "occurred_at"

      # Time dimensions in Cube.js support these granularities:
      # - second, minute, hour, day, week, month, quarter, year
      # These are specified in the query, not the cube definition
    end

    test "time dimension ref structure includes all required fields" do
      occurred_dim = GranularitySchema.Dimensions.occurred_at()

      # Verify key fields are present and correct
      assert occurred_dim.name == "occurred_at"
      assert occurred_dim.module == PowerOfThree.TimeDimensionTest.GranularitySchema
      assert occurred_dim.type == :time
      assert occurred_dim.sql == "occurred_at"
      assert occurred_dim.meta.ecto_field == :occurred_at
      assert occurred_dim.meta.ecto_field_type == :naive_datetime
    end
  end

  describe "system timestamp handling" do
    # Note: inserted_at and updated_at are skipped by auto-generation
    # but can be explicitly added if needed

    defmodule SystemTimestampSchema do
      use Ecto.Schema
      use PowerOfThree

      schema "system_test" do
        field :name, :string
        timestamps()
      end

      cube :system_test, sql_table: "system_test"
    end

    test "auto-generation skips inserted_at and updated_at by default" do
      dimensions = SystemTimestampSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      # System timestamps should be skipped in auto-generation
      refute "inserted_at" in dimension_names
      refute "updated_at" in dimension_names

      # Regular fields should still be generated
      assert "name" in dimension_names
    end

    test "count measure is generated even without time dimensions" do
      measures = SystemTimestampSchema.measures()
      measure_names = Enum.map(measures, & &1.name)

      # Measure names can be either strings or atoms
      assert :count in measure_names or "count" in measure_names
    end
  end

  describe "mixed field types with timestamps" do
    defmodule MixedSchema do
      use Ecto.Schema
      use PowerOfThree

      schema "mixed" do
        field :title, :string
        field :views, :integer
        field :rating, :float
        field :published_at, :utc_datetime
        field :scheduled_for, :date
      end

      cube :mixed, sql_table: "mixed"
    end

    test "generates correct mix of dimension types" do
      dimensions = MixedSchema.dimensions()

      # String dimension
      title_dim = Enum.find(dimensions, &(&1.name == "title"))
      assert title_dim.type == :string

      # Time dimensions
      published_dim = Enum.find(dimensions, &(&1.name == "published_at"))
      assert published_dim.type == :time

      scheduled_dim = Enum.find(dimensions, &(&1.name == "scheduled_for"))
      assert scheduled_dim.type == :time
    end

    test "does not create dimensions for numeric fields" do
      dimensions = MixedSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      # Numeric fields should NOT be dimensions
      refute "views" in dimension_names
      refute "rating" in dimension_names
    end

    test "creates measures for numeric fields" do
      measures = MixedSchema.measures()
      measure_names = Enum.map(measures, & &1.name)

      # Integer field gets sum and count_distinct (names can be atoms or strings)
      assert :views_sum in measure_names or "views_sum" in measure_names
      assert :views_distinct in measure_names or "views_distinct" in measure_names

      # Float field gets sum
      assert :rating_sum in measure_names or "rating_sum" in measure_names
    end
  end
end
