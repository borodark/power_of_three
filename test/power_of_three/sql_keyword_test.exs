defmodule PowerOfThree.SqlKeywordTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  describe "SQL keyword detection" do
    test "warns when schema source is an unqualified SQL keyword" do
      log =
        capture_log([level: :warning], fn ->
          defmodule UnqualifiedOrderCube do
            use Ecto.Schema
            use PowerOfThree

            # Using "order" as schema source triggers warning (it's a SQL keyword)
            schema "order" do
              field(:customer_email, :string)
              field(:total, :integer)
              timestamps()
            end

            # sql_table is automatically inferred from schema "order"
            cube(:test_order_cube)
          end
        end)

      assert log =~ "sql_table \"order\" is a SQL keyword"
      assert log =~ "Consider using schema-qualified name"
      assert log =~ "sql_table: \"public.order\""
    end

    test "only logs debug when schema source is schema-qualified SQL keyword" do
      # Debug messages won't appear in warning-level capture
      log =
        capture_log([level: :warning], fn ->
          defmodule QualifiedOrderCube do
            use Ecto.Schema
            use PowerOfThree

            # Schema-qualified "public.order" should only log debug, not warning
            schema "public.order" do
              field(:customer_email, :string)
              field(:total, :integer)
              timestamps()
            end

            # sql_table is automatically inferred from schema "public.order"
            cube(:test_qualified_order_cube)
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

            # sql_table is automatically inferred from schema "customers" (not a keyword)
            cube(:test_safe_cube)
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

  describe "sql_table validation" do
    test "raises error when sql_table is explicitly provided" do
      # Explicitly providing sql_table is not allowed - it must be inferred
      assert_raise ArgumentError,
                   ~r/Explicitly providing sql_table is not allowed/,
                   fn ->
                     defmodule ExplicitSqlTableCube do
                       use Ecto.Schema
                       use PowerOfThree

                       schema "orders" do
                         field(:total, :integer)
                         timestamps()
                       end

                       # This should raise an error - sql_table must be inferred
                       cube(:mismatched_cube, sql_table: "customers")
                     end
                   end
    end

    test "automatically infers sql_table from Ecto schema source" do
      # This should compile without warnings
      log =
        capture_log([level: :info], fn ->
          defmodule MatchedTableCube do
            use Ecto.Schema
            use PowerOfThree

            schema "products" do
              field(:name, :string)
              timestamps()
            end

            # sql_table is automatically inferred from schema "products"
            cube(:matched_cube)
          end
        end)

      # Should log that sql_table was inferred
      assert log =~ "sql_table inferred from Ecto schema source: \"products\""
      assert PowerOfThree.SqlKeywordTest.MatchedTableCube.__schema__(:source) == "products"
    end

    test "works with schema-qualified table names" do
      # Schema-qualified names should also be inferred correctly
      log =
        capture_log([level: :info], fn ->
          defmodule QualifiedTableCube do
            use Ecto.Schema
            use PowerOfThree

            schema "public.events" do
              field(:event_type, :string)
              timestamps()
            end

            # sql_table is automatically inferred from schema "public.events"
            cube(:events_cube)
          end
        end)

      assert log =~ "sql_table inferred from Ecto schema source: \"public.events\""

      assert PowerOfThree.SqlKeywordTest.QualifiedTableCube.__schema__(:source) ==
               "public.events"
    end

    test "infers sql_table from Ecto schema source when not provided" do
      log =
        capture_log([level: :info], fn ->
          defmodule InferredTableCube do
            use Ecto.Schema
            use PowerOfThree

            schema "inventory" do
              field(:item_name, :string)
              field(:quantity, :integer)
              timestamps()
            end

            # sql_table is always inferred from Ecto schema source
            cube(:inventory_cube)
          end
        end)

      # Should log that sql_table was inferred from schema source
      assert log =~ "sql_table inferred from Ecto schema source: \"inventory\""

      # Verify the cube was created with the correct schema source
      assert PowerOfThree.SqlKeywordTest.InferredTableCube.__schema__(:source) == "inventory"
    end

    test "infers sql_table from schema source even when cube name differs" do
      log =
        capture_log([level: :info], fn ->
          defmodule DefaultNameCube do
            use Ecto.Schema
            use PowerOfThree

            schema "products" do
              field(:name, :string)
              timestamps()
            end

            # Cube name is :my_products, but sql_table should be inferred as "products"
            cube(:my_products)
          end
        end)

      assert log =~ "sql_table inferred from Ecto schema source: \"products\""
    end

    test "raises error when Ecto.Schema is not used" do
      # PowerOfThree requires Ecto.Schema with fields
      assert_raise ArgumentError,
                   ~r/Please.*use Ecto.Schema.*define some fields first/,
                   fn ->
                     defmodule NoSchemaCube do
                       # Intentionally not using Ecto.Schema - should fail with Ecto.Schema error
                       use PowerOfThree

                       cube(:simple_cube)
                     end
                   end
    end
  end
end
