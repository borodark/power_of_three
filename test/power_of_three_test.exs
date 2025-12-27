defmodule PowerOfThreeTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    @moduledoc false

    use Ecto.Schema

    use PowerOfThree

    @type t() :: %__MODULE__{}

    # @schema_prefix :customer_schema

    schema "customer" do
      field(:first_name, :string)
      field(:last_name, :string)
      field(:email, :string)
      field(:birthday_day, :integer)
      field(:birthday_month, :integer)
      field(:brand_code, :string)
      field(:market_code, :string)
      timestamps()
    end

    cube :of_customers,
      title: "Demo cube",
      description: "of Customers" do
      dimension(
        [:brand_code, :market_code, :email],
        name: :email_per_brand_per_market,
        primary_key: true
      )

      dimension(
        :first_name,
        name: :given_name
      )

      dimension([:birthday_day, :birthday_month],
        name: :zodiac,
        description:
          "SQL for a zodiac sign for given [:birthday_day, :birthday_month], not _gyroscope_, TODO unicode of Emoji",
        sql: """
        CASE
        WHEN (birthday_month = 1 AND birthday_day >= 20) OR (birthday_month = 2 AND birthday_day <= 18) THEN 'Aquarius'
        WHEN (birthday_month = 2 AND birthday_day >= 19) OR (birthday_month = 3 AND birthday_day <= 20) THEN 'Pisces'
        WHEN (birthday_month = 3 AND birthday_day >= 21) OR (birthday_month = 4 AND birthday_day <= 19) THEN 'Aries'
        WHEN (birthday_month = 4 AND birthday_day >= 20) OR (birthday_month = 5 AND birthday_day <= 20) THEN 'Taurus'
        WHEN (birthday_month = 5 AND birthday_day >= 21) OR (birthday_month = 6 AND birthday_day <= 20) THEN 'Gemini'
        WHEN (birthday_month = 6 AND birthday_day >= 21) OR (birthday_month = 7 AND birthday_day <= 22) THEN 'Cancer'
        WHEN (birthday_month = 7 AND birthday_day >= 23) OR (birthday_month = 8 AND birthday_day <= 22) THEN 'Leo'
        WHEN (birthday_month = 8 AND birthday_day >= 23) OR (birthday_month = 9 AND birthday_day <= 22) THEN 'Virgo'
        WHEN (birthday_month = 9 AND birthday_day >= 23) OR (birthday_month = 10 AND birthday_day <= 22) THEN 'Libra'
        WHEN (birthday_month = 10 AND birthday_day >= 23) OR (birthday_month = 11 AND birthday_day <= 21) THEN 'Scorpio'
        WHEN (birthday_month = 11 AND birthday_day >= 22) OR (birthday_month = 12 AND birthday_day <= 21) THEN 'Sagittarius'
        WHEN (birthday_month = 12 AND birthday_day >= 22) OR (birthday_month = 1 AND birthday_day <= 19) THEN 'Capricorn'
        ELSE 'Professor Abe Weissman'
        END
        """
      )

      dimension([:birthday_day, :birthday_month],
        name: :star_sector,
        type: :number,
        description: "integer from 0 to 11 for zodiac signs",
        sql: """
        CASE
        WHEN (birthday_month = 1 AND birthday_day >= 20) OR (birthday_month = 2 AND birthday_day <= 18) THEN 0
        WHEN (birthday_month = 2 AND birthday_day >= 19) OR (birthday_month = 3 AND birthday_day <= 20) THEN 1
        WHEN (birthday_month = 3 AND birthday_day >= 21) OR (birthday_month = 4 AND birthday_day <= 19) THEN 2
        WHEN (birthday_month = 4 AND birthday_day >= 20) OR (birthday_month = 5 AND birthday_day <= 20) THEN 3
        WHEN (birthday_month = 5 AND birthday_day >= 21) OR (birthday_month = 6 AND birthday_day <= 20) THEN 4
        WHEN (birthday_month = 6 AND birthday_day >= 21) OR (birthday_month = 7 AND birthday_day <= 22) THEN 5
        WHEN (birthday_month = 7 AND birthday_day >= 23) OR (birthday_month = 8 AND birthday_day <= 22) THEN 6
        WHEN (birthday_month = 8 AND birthday_day >= 23) OR (birthday_month = 9 AND birthday_day <= 22) THEN 7
        WHEN (birthday_month = 9 AND birthday_day >= 23) OR (birthday_month = 10 AND birthday_day <= 22) THEN 8
        WHEN (birthday_month = 10 AND birthday_day >= 23) OR (birthday_month = 11 AND birthday_day <= 21) THEN 9
        WHEN (birthday_month = 11 AND birthday_day >= 22) OR (birthday_month = 12 AND birthday_day <= 21) THEN 10
        WHEN (birthday_month = 12 AND birthday_day >= 22) OR (birthday_month = 1 AND birthday_day <= 19) THEN 11
        ELSE -1
        END
        """
      )

      dimension(
        [:brand_code, :market_code],
        name: :bm_code,
        type: :string,
        # This is Cube Dimension type. TODO like in ecto :kind, Ecto.Enum, values: @kinds
        sql: "brand_code|| '_' || market_code"
        ## TODO danger lurking here"
      )

      dimension(:brand_code, name: :brand, description: "Beer")

      dimension(:market_code, name: :market, description: "market_code, like AU")

      dimension(:updated_at, name: :updated, description: "updated_at timestamp")

      measure(:count,
        description: "no need for fields for :count type measure"
      )

      time_dimensions()

      measure(:email,
        name: :emails_distinct,
        type: :count_distinct,
        description: "count distinct of emails"
      )

      measure(:email,
        name: :aquarii,
        type: :count_distinct,
        description: "Filtered by start sector = 0",
        filters: [
          %{
            sql:
              "(birthday_month = 1 AND birthday_day >= 20) OR (birthday_month = 2 AND birthday_day <= 18)"
          }
        ]
      )
    end
  end

  test "schema metadata" do
    #      sql_table: "customer",
    # :of_customers,
    #      title: "Demo cube",
    #      description: "of Customers"
    assert Schema.__schema__(:source) == "customer"
    assert Schema.__info__(:attributes)[:cube_primary_keys] == ["brand_code||market_code||email"]
    assert Schema.__info__(:attributes)[:measures] |> Enum.count() == 3
    assert Schema.__info__(:attributes)[:dimensions] |> Enum.count() == 8
    assert Schema.__schema__(:primary_key) == [:id]
  end

  # Tests for dimension_type function with all type mappings
  describe "dimension_type/1" do
    test "maps string types to :string" do
      assert PowerOfThree.dimension_type(:string) == :string
      assert PowerOfThree.dimension_type(:binary) == :string
      assert PowerOfThree.dimension_type(:bitstring) == :string
      assert PowerOfThree.dimension_type(:binary_id) == :string
    end

    test "maps time types to :time" do
      assert PowerOfThree.dimension_type(:date) == :time
      assert PowerOfThree.dimension_type(:time) == :time
      assert PowerOfThree.dimension_type(:time_usec) == :time
      assert PowerOfThree.dimension_type(:naive_datetime) == :time
      assert PowerOfThree.dimension_type(:naive_datetime_usec) == :time
      assert PowerOfThree.dimension_type(:utc_datetime) == :time
      assert PowerOfThree.dimension_type(:utc_datetime_usec) == :time
    end

    test "maps numeric types to :number" do
      assert PowerOfThree.dimension_type(:id) == :number
      assert PowerOfThree.dimension_type(:integer) == :number
      assert PowerOfThree.dimension_type(:float) == :number
      assert PowerOfThree.dimension_type(:decimal) == :number
    end

    test "maps boolean type to :boolen (typo preserved)" do
      assert PowerOfThree.dimension_type(:boolean) == :boolen
    end

    test "maps unknown types to :string (default)" do
      assert PowerOfThree.dimension_type(:unknown) == :string
      assert PowerOfThree.dimension_type(:atom) == :string
      assert PowerOfThree.dimension_type(:any) == :string
    end
  end

  # Tests for invalid dimension field references
  describe "dimension validation" do
    test "raises error when dimension references non-existent field" do
      assert_raise ArgumentError, fn ->
        defmodule InvalidDimensionField do
          use Ecto.Schema
          use PowerOfThree

          schema "test" do
            field(:valid_field, :string)
          end

          cube :test_cube do
            dimension(:non_existent_field)
          end
        end
      end
    end

    test "raises error when dimension list contains non-existent fields" do
      assert_raise ArgumentError, fn ->
        defmodule InvalidDimensionFieldList do
          use Ecto.Schema
          use PowerOfThree

          schema "test" do
            field(:field_one, :string)
            field(:field_two, :string)
          end

          cube :test_cube do
            dimension([:field_one, :non_existent_field])
          end
        end
      end
    end
  end

  # Tests for invalid measure field references
  describe "measure validation" do
    test "raises error when measure references non-existent field" do
      assert_raise ArgumentError, fn ->
        defmodule InvalidMeasureField do
          use Ecto.Schema
          use PowerOfThree

          schema "test" do
            field(:valid_field, :string)
          end

          cube :test_cube do
            measure(:non_existent_field, type: :count_distinct)
          end
        end
      end
    end

    test "raises error when measure list contains non-existent fields" do
      assert_raise ArgumentError, fn ->
        defmodule InvalidMeasureFieldList do
          use Ecto.Schema
          use PowerOfThree

          schema "test" do
            field(:field_one, :integer)
            field(:field_two, :integer)
          end

          cube :test_cube do
            measure([:field_one, :non_existent_field], sql: "field_one + field_two", type: :sum)
          end
        end
      end
    end

    test "raises error when multi-field measure lacks :sql option" do
      assert_raise ArgumentError, fn ->
        defmodule MeasureMissingSQL do
          use Ecto.Schema
          use PowerOfThree

          schema "test" do
            field(:field_one, :integer)
            field(:field_two, :integer)
          end

          cube :test_cube do
            measure([:field_one, :field_two], type: :sum)
          end
        end
      end
    end

    test "raises error when single-field measure lacks :type option" do
      assert_raise ArgumentError, fn ->
        defmodule MeasureMissingType do
          use Ecto.Schema
          use PowerOfThree

          schema "test" do
            field(:amount, :integer)
          end

          cube :test_cube do
            measure(:amount)
          end
        end
      end
    end
  end

  # Tests for missing Ecto.Schema fields
  describe "schema validation" do
    test "raises error when cube is defined without Ecto.Schema fields" do
      assert_raise ArgumentError, fn ->
        defmodule NoSchemaFields do
          use Ecto.Schema
          use PowerOfThree

          schema "test" do
          end

          cube :test_cube do
            measure(:count)
          end
        end
      end
    end

    test "raises error when cube is defined with only default :id field" do
      assert_raise ArgumentError, fn ->
        defmodule OnlyIdField do
          use Ecto.Schema
          use PowerOfThree

          schema "test" do
            # Ecto.Schema defines :id by default, not adding any custom fields
          end

          cube :test_cube do
            measure(:count)
          end
        end
      end
    end
  end

  # Tests for double cube definition
  describe "cube definition" do
    test "raises error when cube is defined twice" do
      assert_raise RuntimeError, ~r/cube already defined/, fn ->
        defmodule DoubleCube do
          use Ecto.Schema
          use PowerOfThree

          schema "test" do
            field(:field_one, :string)
          end

          cube :first_cube do
            dimension(:field_one)
          end

          cube :second_cube do
            dimension(:field_one)
          end
        end
      end
    end
  end

  # Tests for dimension with primary_key option
  describe "dimension primary_key" do
    test "sets primary_key when option is true on list dimension" do
      defmodule PrimaryKeyTrue do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:email, :string)
          field(:name, :string)
        end

        cube :test_cube do
          dimension([:email, :name], primary_key: true)
          measure(:count)
        end
      end

      assert PrimaryKeyTrue.__info__(:attributes)[:cube_primary_keys] == ["email||name"]
    end

    test "does not set primary_key when option is false" do
      defmodule PrimaryKeyFalse do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:email, :string)
        end

        cube :test_cube do
          dimension(:email, primary_key: false)
          measure(:count)
        end
      end

      assert PrimaryKeyFalse.__info__(:attributes)[:cube_primary_keys] == []
    end
  end

  # Tests for count measure
  describe "measure count" do
    test "creates count measure without field reference" do
      defmodule CountMeasure do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:name, :string)
        end

        cube :test_cube do
          measure(:count, description: "Total records")
        end
      end

      measures = CountMeasure.__info__(:attributes)[:measures]
      assert Enum.any?(measures, fn m -> m.type == :count end)
    end

    test "count measure defaults to 'count' name when not specified" do
      defmodule CountMeasureDefaultName do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:name, :string)
        end

        cube :test_cube do
          measure(:count)
        end
      end

      measures = CountMeasureDefaultName.__info__(:attributes)[:measures]
      count_measure = Enum.find(measures, fn m -> m.type == :count end)
      assert count_measure.name == :count
    end

    test "count measure can have custom name" do
      defmodule CountMeasureCustomName do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:name, :string)
        end

        cube :test_cube do
          measure(:count, name: :total_records)
        end
      end

      measures = CountMeasureCustomName.__info__(:attributes)[:measures]
      assert Enum.any?(measures, fn m -> m.name == :total_records end)
    end
  end

  # Tests for dimension without explicit options
  describe "dimension defaults" do
    test "dimension defaults to field name when name not specified" do
      defmodule DimensionDefaultName do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:customer_email, :string)
        end

        cube :test_cube do
          dimension(:customer_email)
        end
      end

      dimensions = DimensionDefaultName.__info__(:attributes)[:dimensions]
      assert Enum.any?(dimensions, fn d -> d.name == "customer_email" end)
    end

    test "dimension with list defaults to concatenated field names" do
      defmodule DimensionListDefaultName do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:first_name, :string)
          field(:last_name, :string)
        end

        cube :test_cube do
          dimension([:first_name, :last_name])
        end
      end

      dimensions = DimensionListDefaultName.__info__(:attributes)[:dimensions]
      assert Enum.any?(dimensions, fn d -> d.name == "first_name_last_name" end)
    end
  end

  # Tests for measure without explicit name
  describe "measure defaults" do
    test "single field measure defaults to field name when name not specified" do
      defmodule MeasureDefaultName do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:amount, :integer)
        end

        cube :test_cube do
          measure(:amount, type: :sum)
        end
      end

      measures = MeasureDefaultName.__info__(:attributes)[:measures]
      assert Enum.any?(measures, fn m -> m.name == "amount" end)
    end

    test "multi-field measure defaults to concatenated field names when name not specified" do
      defmodule MeasureListDefaultName do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:tax, :integer)
          field(:discount, :integer)
        end

        cube :test_cube do
          measure([:tax, :discount], sql: "tax + discount", type: :sum)
        end
      end

      measures = MeasureListDefaultName.__info__(:attributes)[:measures]
      assert Enum.any?(measures, fn m -> m.name == "tax_discount" end)
    end
  end

  # Tests for pass-through options
  describe "pass-through options" do
    test "dimension passes through custom options" do
      defmodule DimensionCustomOpts do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:email, :string)
        end

        cube :test_cube do
          dimension(:email,
            description: "Customer email",
            format: :link,
            custom_prop: "custom_value"
          )
        end
      end

      dimensions = DimensionCustomOpts.__info__(:attributes)[:dimensions]
      dim = Enum.find(dimensions, fn d -> d.name == "email" end)
      assert dim.description == "Customer email"
      assert dim.custom_prop == "custom_value"
    end

    test "measure passes through custom options" do
      defmodule MeasureCustomOpts do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:revenue, :integer)
        end

        cube :test_cube do
          measure(:revenue,
            type: :sum,
            description: "Total revenue",
            format: :currency,
            custom_prop: "custom_measure"
          )

          dimension(:revenue)
        end
      end

      cube_config = MeasureCustomOpts.__info__(:attributes)[:cube_config]
      measures = Enum.at(cube_config, 0).measures
      measure = Enum.find(measures, fn m -> m.name == "revenue" end)
      assert measure.description == "Total revenue"
      assert measure.custom_prop == "custom_measure"
    end
  end

  # Tests for time_dimensions macro
  describe "time_dimensions" do
    test "time_dimensions macro executes without error" do
      defmodule TimeDisDefault do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:name, :string)
          timestamps()
        end

        cube :test_cube do
          dimension(:name)
          time_dimensions()
        end
      end

      # Just verify the module was created successfully (code path tested)
      assert TimeDisDefault.__schema__(:source) == "test"
    end

    test "time_dimensions stores attribute in module" do
      defmodule TimeDisMetadata do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:name, :string)
          timestamps()
        end

        cube :test_cube do
          dimension(:name)
          time_dimensions()
        end
      end

      # time_dimensions macro registers the attribute
      # The attribute should be present in the module (code coverage path)
      assert is_list(TimeDisMetadata.__info__(:attributes)[:cube_config])
    end
  end

  # Tests for code injection detection
  describe "code injection detection" do
    test "logs debug message for unrecognized cube options" do
      # This test verifies the code path at line 208
      import ExUnit.CaptureLog

      log =
        capture_log([level: :debug], fn ->
          defmodule CodeInjectionTest do
            use Ecto.Schema
            use PowerOfThree

            schema "test" do
              field(:name, :string)
            end

            cube :test_cube,
              invalid_option: "should be logged" do
              measure(:count)
            end
          end
        end)

      assert log =~ "Detected Inrusions list:"
    end
  end

  # Tests for dimension type derivation with various Ecto types
  describe "dimension type derivation from Ecto types" do
    test "string field becomes string dimension" do
      defmodule StringFieldType do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:name, :string)
        end

        cube :test_cube do
          dimension(:name)
        end
      end

      dimensions = StringFieldType.__info__(:attributes)[:dimensions]
      dim = Enum.find(dimensions, fn d -> d.name == "name" end)
      assert dim.type == :string
    end

    test "integer field becomes number dimension" do
      defmodule IntegerFieldType do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:count, :integer)
        end

        cube :test_cube do
          dimension(:count)
        end
      end

      dimensions = IntegerFieldType.__info__(:attributes)[:dimensions]
      dim = Enum.find(dimensions, fn d -> d.name == "count" end)
      assert dim.type == :number
    end

    test "date field becomes time dimension" do
      defmodule DateFieldType do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:created_date, :date)
        end

        cube :test_cube do
          dimension(:created_date)
        end
      end

      dimensions = DateFieldType.__info__(:attributes)[:dimensions]
      dim = Enum.find(dimensions, fn d -> d.name == "created_date" end)
      assert dim.type == :time
    end

    test "naive_datetime field becomes time dimension" do
      defmodule NaiveDatetimeFieldType do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:updated_at, :naive_datetime)
        end

        cube :test_cube do
          dimension(:updated_at)
        end
      end

      dimensions = NaiveDatetimeFieldType.__info__(:attributes)[:dimensions]
      dim = Enum.find(dimensions, fn d -> d.name == "updated_at" end)
      assert dim.type == :time
    end

    test "utc_datetime field becomes time dimension" do
      defmodule UtcDatetimeFieldType do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:created_at, :utc_datetime)
        end

        cube :test_cube do
          dimension(:created_at)
        end
      end

      dimensions = UtcDatetimeFieldType.__info__(:attributes)[:dimensions]
      dim = Enum.find(dimensions, fn d -> d.name == "created_at" end)
      assert dim.type == :time
    end

    test "explicit type overrides inferred type" do
      defmodule ExplicitTypeOverride do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:code, :string)
        end

        cube :test_cube do
          dimension(:code, type: :number)
        end
      end

      dimensions = ExplicitTypeOverride.__info__(:attributes)[:dimensions]
      dim = Enum.find(dimensions, fn d -> d.name == "code" end)
      assert dim.type == :number
    end
  end

  # Tests for multi-field dimension and measure
  describe "multi-field operations" do
    test "multi-field dimension generates concatenated SQL" do
      defmodule MultiFieldDimSQL do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:first, :string)
          field(:second, :string)
          field(:third, :string)
        end

        cube :test_cube do
          dimension([:first, :second, :third])
        end
      end

      dimensions = MultiFieldDimSQL.__info__(:attributes)[:dimensions]
      dim = Enum.find(dimensions, fn d -> d.name == "first_second_third" end)
      assert dim.sql == "first||second||third"
    end

    test "multi-field measure with custom SQL" do
      defmodule MultiFieldMeasureSQL do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:amount, :integer)
          field(:quantity, :integer)
        end

        cube :test_cube do
          measure([:amount, :quantity], sql: "(amount * quantity)", type: :sum)
        end
      end

      measures = MultiFieldMeasureSQL.__info__(:attributes)[:measures]
      measure = Enum.find(measures, fn m -> m.name == "amount_quantity" end)
      assert measure.sql == "(amount * quantity)"
      assert measure.type == :number
    end
  end

  # Tests for cube configuration
  describe "cube configuration" do
    test "cube stores name and sql_table" do
      defmodule CubeConfig do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:name, :string)
        end

        cube :my_cube do
          measure(:count)
        end
      end

      cube_config = CubeConfig.__info__(:attributes)[:cube_config]
      assert Enum.at(cube_config, 0).name == :my_cube
      assert Enum.at(cube_config, 0).sql_table == "test"
    end

    test "cube includes title and description in config" do
      defmodule CubeWithMetadata do
        use Ecto.Schema
        use PowerOfThree

        schema "test" do
          field(:name, :string)
        end

        cube :test_cube,
          title: "Test Title",
          description: "Test Description" do
          measure(:count)
        end
      end

      cube_config = CubeWithMetadata.__info__(:attributes)[:cube_config]
      assert Enum.at(cube_config, 0).title == "Test Title"
      assert Enum.at(cube_config, 0).description == "Test Description"
    end
  end
end
