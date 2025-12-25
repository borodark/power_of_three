defmodule PowerOfThree.SqlKeywordTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  describe "SQL keyword detection" do
    test "warns when sql_table is an unqualified SQL keyword" do
      log =
        capture_log([level: :warning], fn ->
          defmodule UnqualifiedOrderCube do
            use Ecto.Schema
            use PowerOfThree

            schema "orders" do
              field(:customer_email, :string)
              field(:total, :integer)
              timestamps()
            end

            # This should trigger a warning because "order" is a SQL keyword
            cube :test_order_cube, sql_table: "order"
          end
        end)

      assert log =~ "sql_table \"order\" is a SQL keyword"
      assert log =~ "Consider using schema-qualified name"
      assert log =~ "sql_table: \"public.order\""
    end

    test "only logs debug when sql_table is schema-qualified SQL keyword" do
      # Debug messages won't appear in warning-level capture
      log =
        capture_log([level: :warning], fn ->
          defmodule QualifiedOrderCube do
            use Ecto.Schema
            use PowerOfThree

            schema "orders" do
              field(:customer_email, :string)
              field(:total, :integer)
              timestamps()
            end

            # This should NOT warn because it's schema-qualified
            cube :test_qualified_order_cube, sql_table: "public.order"
          end
        end)

      # Should not contain warning
      refute log =~ "sql_table \"public.order\" is a SQL keyword"
    end

    test "does not warn for non-keyword table names" do
      log =
        capture_log([level: :warning], fn ->
          defmodule SafeTableCube do
            use Ecto.Schema
            use PowerOfThree

            schema "customers" do
              field(:name, :string)
              timestamps()
            end

            cube :test_safe_cube, sql_table: "customers"
          end
        end)

      refute log =~ "SQL keyword"
    end

    test "detects common SQL keywords" do
      # Test a few common SQL keywords
      assert PowerOfThree.is_sql_keyword?("order")
      assert PowerOfThree.is_sql_keyword?("user")
      assert PowerOfThree.is_sql_keyword?("group")
      assert PowerOfThree.is_sql_keyword?("table")
      assert PowerOfThree.is_sql_keyword?("select")
      assert PowerOfThree.is_sql_keyword?("from")
      assert PowerOfThree.is_sql_keyword?("where")

      # Test schema-qualified versions
      assert PowerOfThree.is_sql_keyword?("public.order")
      assert PowerOfThree.is_sql_keyword?("schema.user")

      # Test non-keywords
      refute PowerOfThree.is_sql_keyword?("orders")
      refute PowerOfThree.is_sql_keyword?("customers")
      refute PowerOfThree.is_sql_keyword?("products")
    end

    test "detects Cube.js keywords" do
      assert PowerOfThree.is_sql_keyword?("cube")
      assert PowerOfThree.is_sql_keyword?("dimension")
      assert PowerOfThree.is_sql_keyword?("measure")
      refute PowerOfThree.is_sql_keyword?("cubes")
      refute PowerOfThree.is_sql_keyword?("dimensions")
    end

    test "is_schema_qualified? detects schema prefixes" do
      assert PowerOfThree.is_schema_qualified?("public.order")
      assert PowerOfThree.is_schema_qualified?("my_schema.my_table")
      refute PowerOfThree.is_schema_qualified?("order")
      refute PowerOfThree.is_schema_qualified?("customers")
    end
  end
end
