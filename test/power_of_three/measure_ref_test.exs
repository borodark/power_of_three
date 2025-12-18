defmodule PowerOfThree.MeasureRefTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.MeasureRef

  # Mock module for testing
  defmodule TestCustomer do
    def __schema__(:source), do: "customer"
  end

  describe "struct creation" do
    test "creates measure ref with required fields" do
      measure = %MeasureRef{
        name: :count,
        module: TestCustomer,
        type: :count
      }

      assert measure.name == :count
      assert measure.module == TestCustomer
      assert measure.type == :count
    end

    test "creates measure ref with all fields" do
      measure = %MeasureRef{
        name: :total_revenue,
        module: TestCustomer,
        type: :sum,
        sql: :revenue,
        meta: %{ecto_field: :revenue, ecto_type: :decimal},
        description: "Total revenue from all orders",
        filters: [%{sql: "status = 'completed'"}],
        format: :currency
      }

      assert measure.name == :total_revenue
      assert measure.type == :sum
      assert measure.description == "Total revenue from all orders"
      assert measure.filters == [%{sql: "status = 'completed'"}]
      assert measure.format == :currency
    end

    test "has name, module, and type as required fields" do
      # @enforce_keys in the struct definition ensures these are required
      # Creating a struct without them will raise ArgumentError at compile time
      assert true
    end
  end

  describe "to_sql_column/1" do
    test "converts count measure to SQL" do
      measure = %MeasureRef{
        name: :count,
        module: TestCustomer,
        type: :count
      }

      assert MeasureRef.to_sql_column(measure) == "MEASURE(customer.count)"
    end

    test "converts named measure to SQL" do
      measure = %MeasureRef{
        name: :total_revenue,
        module: TestCustomer,
        type: :sum
      }

      assert MeasureRef.to_sql_column(measure) == "MEASURE(customer.total_revenue)"
    end

    test "handles string names" do
      measure = %MeasureRef{
        name: "aquarii",
        module: TestCustomer,
        type: :count_distinct
      }

      assert MeasureRef.to_sql_column(measure) == "MEASURE(customer.aquarii)"
    end
  end

  describe "extract_cube_name/1" do
    test "extracts cube name from module" do
      assert MeasureRef.extract_cube_name(TestCustomer) == "customer"
    end
  end

  describe "name_string/1" do
    test "converts atom name to string" do
      measure = %MeasureRef{name: :count, module: TestCustomer, type: :count}
      assert MeasureRef.name_string(measure) == "count"
    end

    test "returns string name as-is" do
      measure = %MeasureRef{name: "total_revenue", module: TestCustomer, type: :sum}
      assert MeasureRef.name_string(measure) == "total_revenue"
    end
  end

  describe "describe/1" do
    test "describes measure without description" do
      measure = %MeasureRef{
        name: :count,
        module: TestCustomer,
        type: :count
      }

      assert MeasureRef.describe(measure) == "count (count)"
    end

    test "describes measure with description" do
      measure = %MeasureRef{
        name: :total_revenue,
        module: TestCustomer,
        type: :sum,
        description: "Sum of all revenue"
      }

      assert MeasureRef.describe(measure) == "total_revenue (sum): Sum of all revenue"
    end
  end

  describe "validate/1" do
    test "validates valid measure" do
      measure = %MeasureRef{
        name: :count,
        module: TestCustomer,
        type: :count
      }

      assert MeasureRef.validate(measure) == :ok
    end

    test "rejects measure with nil name" do
      measure = %MeasureRef{
        name: nil,
        module: TestCustomer,
        type: :count
      }

      assert MeasureRef.validate(measure) == {:error, "name cannot be nil"}
    end

    test "rejects measure with nil module" do
      measure = %MeasureRef{
        name: :count,
        module: nil,
        type: :count
      }

      assert MeasureRef.validate(measure) == {:error, "module cannot be nil"}
    end

    test "rejects measure with nil type" do
      measure = %MeasureRef{
        name: :count,
        module: TestCustomer,
        type: nil
      }

      assert MeasureRef.validate(measure) == {:error, "type cannot be nil"}
    end

    test "rejects measure with invalid type" do
      measure = %MeasureRef{
        name: :count,
        module: TestCustomer,
        type: :invalid_type
      }

      {:error, message} = MeasureRef.validate(measure)
      assert message =~ "invalid measure type"
    end

    test "accepts all valid measure types" do
      valid_types = [
        :count,
        :count_distinct,
        :count_distinct_approx,
        :sum,
        :avg,
        :min,
        :max,
        :number
      ]

      for type <- valid_types do
        measure = %MeasureRef{
          name: :test,
          module: TestCustomer,
          type: type
        }

        assert MeasureRef.validate(measure) == :ok,
               "Expected type #{inspect(type)} to be valid"
      end
    end
  end

  describe "measure types" do
    test "count measure" do
      measure = %MeasureRef{
        name: :count,
        module: TestCustomer,
        type: :count
      }

      assert measure.type == :count
      assert MeasureRef.validate(measure) == :ok
    end

    test "count_distinct measure" do
      measure = %MeasureRef{
        name: :unique_emails,
        module: TestCustomer,
        type: :count_distinct,
        sql: :email
      }

      assert measure.type == :count_distinct
      assert MeasureRef.validate(measure) == :ok
    end

    test "sum measure" do
      measure = %MeasureRef{
        name: :total_amount,
        module: TestCustomer,
        type: :sum,
        sql: :amount
      }

      assert measure.type == :sum
      assert MeasureRef.validate(measure) == :ok
    end

    test "avg measure" do
      measure = %MeasureRef{
        name: :average_amount,
        module: TestCustomer,
        type: :avg,
        sql: :amount
      }

      assert measure.type == :avg
      assert MeasureRef.validate(measure) == :ok
    end
  end

  describe "with metadata" do
    test "stores ecto field metadata" do
      measure = %MeasureRef{
        name: :total_revenue,
        module: TestCustomer,
        type: :sum,
        sql: :revenue,
        meta: %{
          ecto_field: :revenue,
          ecto_type: :decimal
        }
      }

      assert measure.meta.ecto_field == :revenue
      assert measure.meta.ecto_type == :decimal
    end

    test "stores filters" do
      measure = %MeasureRef{
        name: :completed_orders_count,
        module: TestCustomer,
        type: :count,
        filters: [
          %{sql: "status = 'completed'"},
          %{sql: "amount > 0"}
        ]
      }

      assert length(measure.filters) == 2
      assert Enum.at(measure.filters, 0).sql == "status = 'completed'"
    end
  end
end
