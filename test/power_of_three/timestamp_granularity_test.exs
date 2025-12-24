defmodule PowerOfThree.TimestampGranularityTest do
  use ExUnit.Case, async: true

  describe "timestamp granularity dimensions" do
    defmodule TimestampSchema do
      use Ecto.Schema
      use PowerOfThree

      schema "events" do
        field :name, :string
        field :count, :integer
        timestamps()
      end

      # Auto-generate cube (no block)
      cube :events, sql_table: "events"
    end

    test "generates granularity dimensions for inserted_at" do
      dimensions = TimestampSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      # All granularities for inserted_at
      assert :inserted_at_second in dimension_names
      assert :inserted_at_minute in dimension_names
      assert :inserted_at_hour in dimension_names
      assert :inserted_at_day in dimension_names
      assert :inserted_at_week in dimension_names
      assert :inserted_at_month in dimension_names
      assert :inserted_at_quarter in dimension_names
      assert :inserted_at_year in dimension_names
    end

    test "generates granularity dimensions for updated_at" do
      dimensions = TimestampSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      # All granularities for updated_at
      assert :updated_at_second in dimension_names
      assert :updated_at_minute in dimension_names
      assert :updated_at_hour in dimension_names
      assert :updated_at_day in dimension_names
      assert :updated_at_week in dimension_names
      assert :updated_at_month in dimension_names
      assert :updated_at_quarter in dimension_names
      assert :updated_at_year in dimension_names
    end

    test "all timestamp granularity dimensions have :time type" do
      dimensions = TimestampSchema.dimensions()

      timestamp_dims =
        Enum.filter(dimensions, fn dim ->
          String.starts_with?(to_string(dim.name), "inserted_at_") or
            String.starts_with?(to_string(dim.name), "updated_at_")
        end)

      # Should have 8 granularities × 2 timestamp fields = 16 dimensions
      assert length(timestamp_dims) == 16

      Enum.each(timestamp_dims, fn dim ->
        assert dim.type == :time,
               "Expected #{dim.name} to have type :time, got #{inspect(dim.type)}"
      end)
    end

    test "timestamp granularity dimension accessors work" do
      # Test accessor functions for inserted_at granularities
      assert %PowerOfThree.DimensionRef{type: :time} =
               TimestampSchema.Dimensions.inserted_at_second()

      assert %PowerOfThree.DimensionRef{type: :time} =
               TimestampSchema.Dimensions.inserted_at_minute()

      assert %PowerOfThree.DimensionRef{type: :time} =
               TimestampSchema.Dimensions.inserted_at_hour()

      assert %PowerOfThree.DimensionRef{type: :time} = TimestampSchema.Dimensions.inserted_at_day()

      assert %PowerOfThree.DimensionRef{type: :time} =
               TimestampSchema.Dimensions.inserted_at_week()

      assert %PowerOfThree.DimensionRef{type: :time} =
               TimestampSchema.Dimensions.inserted_at_month()

      assert %PowerOfThree.DimensionRef{type: :time} =
               TimestampSchema.Dimensions.inserted_at_quarter()

      assert %PowerOfThree.DimensionRef{type: :time} =
               TimestampSchema.Dimensions.inserted_at_year()

      # Test accessor functions for updated_at granularities
      assert %PowerOfThree.DimensionRef{type: :time} =
               TimestampSchema.Dimensions.updated_at_second()

      assert %PowerOfThree.DimensionRef{type: :time} =
               TimestampSchema.Dimensions.updated_at_minute()

      assert %PowerOfThree.DimensionRef{type: :time} =
               TimestampSchema.Dimensions.updated_at_hour()

      assert %PowerOfThree.DimensionRef{type: :time} = TimestampSchema.Dimensions.updated_at_day()

      assert %PowerOfThree.DimensionRef{type: :time} =
               TimestampSchema.Dimensions.updated_at_week()

      assert %PowerOfThree.DimensionRef{type: :time} =
               TimestampSchema.Dimensions.updated_at_month()

      assert %PowerOfThree.DimensionRef{type: :time} =
               TimestampSchema.Dimensions.updated_at_quarter()

      assert %PowerOfThree.DimensionRef{type: :time} = TimestampSchema.Dimensions.updated_at_year()
    end

    test "timestamp dimensions reference correct SQL field" do
      dimensions = TimestampSchema.dimensions()

      # Check inserted_at dimensions
      inserted_day = Enum.find(dimensions, &(&1.name == :inserted_at_day))
      assert inserted_day.sql == "inserted_at"

      inserted_month = Enum.find(dimensions, &(&1.name == :inserted_at_month))
      assert inserted_month.sql == "inserted_at"

      # Check updated_at dimensions
      updated_week = Enum.find(dimensions, &(&1.name == :updated_at_week))
      assert updated_week.sql == "updated_at"

      updated_year = Enum.find(dimensions, &(&1.name == :updated_at_year))
      assert updated_year.sql == "updated_at"
    end

    test "regular fields are still generated alongside timestamp granularities" do
      dimensions = TimestampSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      # Regular field should be present
      assert "name" in dimension_names
    end

    test "measures are generated for integer fields" do
      measures = TimestampSchema.measures()
      measure_names = Enum.map(measures, & &1.name)

      # Count measure
      assert :count in measure_names or "count" in measure_names

      # Integer field measures
      assert :count_sum in measure_names or "count_sum" in measure_names
      assert :count_distinct in measure_names or "count_distinct" in measure_names
    end
  end

  describe "timestamps with custom types" do
    defmodule CustomTimestampSchema do
      use Ecto.Schema
      use PowerOfThree

      schema "custom_events" do
        field :title, :string
        timestamps(type: :utc_datetime)
      end

      cube :custom_events, sql_table: "custom_events"
    end

    test "generates granularity dimensions for custom timestamp type" do
      dimensions = CustomTimestampSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      # Should still generate all granularities
      assert :inserted_at_day in dimension_names
      assert :inserted_at_month in dimension_names
      assert :updated_at_day in dimension_names
      assert :updated_at_month in dimension_names
    end
  end

  describe "schema without timestamps" do
    defmodule NoTimestampSchema do
      use Ecto.Schema
      use PowerOfThree

      schema "no_timestamps" do
        field :name, :string
        field :value, :integer
      end

      cube :no_timestamps, sql_table: "no_timestamps"
    end

    test "does not generate timestamp granularity dimensions" do
      dimensions = NoTimestampSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      # Should have no timestamp granularity dimensions
      refute Enum.any?(dimension_names, &String.starts_with?(&1, "inserted_at_"))
      refute Enum.any?(dimension_names, &String.starts_with?(&1, "updated_at_"))

      # Should only have regular field
      assert "name" in dimension_names
    end

    test "still generates count and other measures" do
      measures = NoTimestampSchema.measures()
      measure_names = Enum.map(measures, & &1.name)

      assert :count in measure_names or "count" in measure_names
      assert :value_sum in measure_names or "value_sum" in measure_names
    end
  end

  describe "mixed timestamp and custom time fields" do
    defmodule MixedTimeSchema do
      use Ecto.Schema
      use PowerOfThree

      schema "mixed" do
        field :title, :string
        field :published_at, :utc_datetime
        field :event_date, :date
        timestamps()
      end

      cube :mixed, sql_table: "mixed"
    end

    test "generates granularities for timestamps but not custom time fields" do
      dimensions = MixedTimeSchema.dimensions()
      dimension_names = Enum.map(dimensions, & &1.name)

      # Timestamp fields should have granularities
      assert :inserted_at_day in dimension_names
      assert :updated_at_month in dimension_names

      # Custom time fields should be plain dimensions
      assert "published_at" in dimension_names
      assert "event_date" in dimension_names

      # Custom time fields should NOT have granularity suffixes
      refute :published_at_day in dimension_names
      refute :event_date_month in dimension_names
    end

    test "all dimensions have correct types" do
      dimensions = MixedTimeSchema.dimensions()

      # Regular field
      title_dim = Enum.find(dimensions, &(&1.name == "title"))
      assert title_dim.type == :string

      # Custom time fields (plain dimensions)
      published_dim = Enum.find(dimensions, &(&1.name == "published_at"))
      assert published_dim.type == :time

      event_dim = Enum.find(dimensions, &(&1.name == "event_date"))
      assert event_dim.type == :time

      # Timestamp granularity dimensions
      inserted_day_dim = Enum.find(dimensions, &(&1.name == :inserted_at_day))
      assert inserted_day_dim.type == :time

      updated_month_dim = Enum.find(dimensions, &(&1.name == :updated_at_month))
      assert updated_month_dim.type == :time
    end
  end

  describe "granularity coverage" do
    defmodule GranularityCheckSchema do
      use Ecto.Schema
      use PowerOfThree

      schema "granularity_check" do
        field :name, :string
        timestamps()
      end

      cube :granularity_check, sql_table: "granularity_check"
    end

    test "generates all 8 Cube.js granularities" do
      dimensions = GranularityCheckSchema.dimensions()

      granularities = [:second, :minute, :hour, :day, :week, :month, :quarter, :year]

      for field <- [:inserted_at, :updated_at],
          granularity <- granularities do
        dimension_name = String.to_atom("#{field}_#{granularity}")
        dim = Enum.find(dimensions, &(&1.name == dimension_name))

        assert dim != nil,
               "Expected dimension #{dimension_name} to exist but it doesn't"

        assert dim.type == :time,
               "Expected #{dimension_name} to be :time type, got #{inspect(dim.type)}"

        assert dim.sql == Atom.to_string(field),
               "Expected #{dimension_name} to reference SQL field #{field}"
      end
    end

    test "total dimension count is correct" do
      dimensions = GranularityCheckSchema.dimensions()

      # 1 regular field (name)
      # + 8 granularities for inserted_at
      # + 8 granularities for updated_at
      # = 17 total dimensions
      assert length(dimensions) == 17
    end
  end
end
