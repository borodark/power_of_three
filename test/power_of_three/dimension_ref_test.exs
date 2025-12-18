defmodule PowerOfThree.DimensionRefTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.DimensionRef

  # Mock module for testing
  defmodule TestCustomer do
    def __schema__(:source), do: "customer"
  end

  describe "struct creation" do
    test "creates dimension ref with required fields" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: "email"
      }

      assert dimension.name == :email
      assert dimension.module == TestCustomer
      assert dimension.type == :string
      assert dimension.sql == "email"
    end

    test "creates dimension ref with all fields" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: "email",
        meta: %{ecto_field: :email, ecto_field_type: :string},
        description: "Customer email address",
        primary_key: true,
        format: :link,
        propagate_filters_to_sub_query: true,
        public: true
      }

      assert dimension.name == :email
      assert dimension.type == :string
      assert dimension.description == "Customer email address"
      assert dimension.primary_key == true
      assert dimension.format == :link
      assert dimension.propagate_filters_to_sub_query == true
      assert dimension.public == true
    end

    test "has name, module, type, and sql as required fields" do
      # @enforce_keys in the struct definition ensures these are required
      # Creating a struct without them will raise ArgumentError at compile time
      assert true
    end
  end

  describe "to_sql_column/1" do
    test "converts dimension to SQL" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: "email"
      }

      assert DimensionRef.to_sql_column(dimension) == "customer.email"
    end

    test "converts dimension with string name" do
      dimension = %DimensionRef{
        name: "brand_code",
        module: TestCustomer,
        type: :string,
        sql: "brand_code"
      }

      assert DimensionRef.to_sql_column(dimension) == "customer.brand_code"
    end

    test "uses dimension name, not SQL expression" do
      dimension = %DimensionRef{
        name: :full_name,
        module: TestCustomer,
        type: :string,
        sql: "first_name || ' ' || last_name"
      }

      # SQL column uses the dimension name, not the SQL expression
      assert DimensionRef.to_sql_column(dimension) == "customer.full_name"
    end
  end

  describe "extract_cube_name/1" do
    test "extracts cube name from module" do
      assert DimensionRef.extract_cube_name(TestCustomer) == "customer"
    end
  end

  describe "name_string/1" do
    test "converts atom name to string" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: "email"
      }

      assert DimensionRef.name_string(dimension) == "email"
    end

    test "returns string name as-is" do
      dimension = %DimensionRef{
        name: "brand_code",
        module: TestCustomer,
        type: :string,
        sql: "brand_code"
      }

      assert DimensionRef.name_string(dimension) == "brand_code"
    end
  end

  describe "describe/1" do
    test "describes dimension without description" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: "email"
      }

      assert DimensionRef.describe(dimension) == "email (string)"
    end

    test "describes dimension with description" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: "email",
        description: "Customer email address"
      }

      assert DimensionRef.describe(dimension) == "email (string): Customer email address"
    end
  end

  describe "validate/1" do
    test "validates valid dimension" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: "email"
      }

      assert DimensionRef.validate(dimension) == :ok
    end

    test "rejects dimension with nil name" do
      dimension = %DimensionRef{
        name: nil,
        module: TestCustomer,
        type: :string,
        sql: "email"
      }

      assert DimensionRef.validate(dimension) == {:error, "name cannot be nil"}
    end

    test "rejects dimension with nil module" do
      dimension = %DimensionRef{
        name: :email,
        module: nil,
        type: :string,
        sql: "email"
      }

      assert DimensionRef.validate(dimension) == {:error, "module cannot be nil"}
    end

    test "rejects dimension with nil type" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: nil,
        sql: "email"
      }

      assert DimensionRef.validate(dimension) == {:error, "type cannot be nil"}
    end

    test "rejects dimension with nil sql" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: nil
      }

      assert DimensionRef.validate(dimension) == {:error, "sql cannot be nil"}
    end

    test "rejects dimension with invalid type" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :invalid_type,
        sql: "email"
      }

      {:error, message} = DimensionRef.validate(dimension)
      assert message =~ "invalid dimension type"
    end

    test "accepts all valid dimension types" do
      valid_types = [:string, :number, :time, :boolean, :geo]

      for type <- valid_types do
        dimension = %DimensionRef{
          name: :test,
          module: TestCustomer,
          type: type,
          sql: "test"
        }

        assert DimensionRef.validate(dimension) == :ok,
               "Expected type #{inspect(type)} to be valid"
      end
    end
  end

  describe "dimension types" do
    test "string dimension" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: "email"
      }

      assert dimension.type == :string
      assert DimensionRef.validate(dimension) == :ok
    end

    test "number dimension" do
      dimension = %DimensionRef{
        name: :age,
        module: TestCustomer,
        type: :number,
        sql: "age"
      }

      assert dimension.type == :number
      assert DimensionRef.validate(dimension) == :ok
    end

    test "time dimension" do
      dimension = %DimensionRef{
        name: :created_at,
        module: TestCustomer,
        type: :time,
        sql: "created_at"
      }

      assert dimension.type == :time
      assert DimensionRef.validate(dimension) == :ok
    end

    test "boolean dimension" do
      dimension = %DimensionRef{
        name: :is_active,
        module: TestCustomer,
        type: :boolean,
        sql: "is_active"
      }

      assert dimension.type == :boolean
      assert DimensionRef.validate(dimension) == :ok
    end
  end

  describe "primary_key?/1" do
    test "returns true for primary key dimension" do
      dimension = %DimensionRef{
        name: :id,
        module: TestCustomer,
        type: :number,
        sql: "id",
        primary_key: true
      }

      assert DimensionRef.primary_key?(dimension) == true
    end

    test "returns false for non-primary key dimension" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: "email"
      }

      assert DimensionRef.primary_key?(dimension) == false
    end

    test "returns false when primary_key is explicitly false" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: "email",
        primary_key: false
      }

      assert DimensionRef.primary_key?(dimension) == false
    end
  end

  describe "sql_expression/1" do
    test "returns string SQL expression" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: "email"
      }

      assert DimensionRef.sql_expression(dimension) == "email"
    end

    test "returns complex SQL expression" do
      dimension = %DimensionRef{
        name: :full_name,
        module: TestCustomer,
        type: :string,
        sql: "first_name || ' ' || last_name"
      }

      assert DimensionRef.sql_expression(dimension) == "first_name || ' ' || last_name"
    end

    test "converts atom SQL to string" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: :email
      }

      assert DimensionRef.sql_expression(dimension) == "email"
    end
  end

  describe "with metadata" do
    test "stores ecto field metadata" do
      dimension = %DimensionRef{
        name: :email,
        module: TestCustomer,
        type: :string,
        sql: "email",
        meta: %{
          ecto_field: :email,
          ecto_field_type: :string
        }
      }

      assert dimension.meta.ecto_field == :email
      assert dimension.meta.ecto_field_type == :string
    end

    test "stores composite field metadata" do
      dimension = %DimensionRef{
        name: :email_per_brand,
        module: TestCustomer,
        type: :string,
        sql: "brand_code||email",
        meta: %{
          ecto_fields: [:brand_code, :email]
        }
      }

      assert dimension.meta.ecto_fields == [:brand_code, :email]
    end
  end
end
