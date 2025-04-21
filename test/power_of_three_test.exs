defmodule PowerOfThreeTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use Ecto.Schema

    schema "my schema" do
      field(:name, :string, default: "eric", autogenerate: {String, :upcase, ["eric"]})
      field(:email, :string, read_after_writes: true)
      field(:password, :string, redact: true)
      field(:temp, :any, default: "temp", virtual: true, redact: true)
      field(:count, :decimal, read_after_writes: true, source: :cnt)
      field(:array, {:array, :string})
      field(:uuid, Ecto.UUID, autogenerate: true)
      field(:no_query_load, :string, load_in_query: false)
      field(:unwritable, :string, writable: :never)
      field(:non_updatable, :string, writable: :insert)
    end
  end

  test "schema metadata" do
    assert Schema.__schema__(:source) == "my schema"
    assert Schema.__schema__(:prefix) == nil

    assert Schema.__schema__(:fields) ==
             [
               :id,
               :name,
               :email,
               :password,
               :count,
               :array,
               :uuid,
               :no_query_load,
               :unwritable,
               :non_updatable
             ]

    assert Schema.__schema__(:insertable_fields) ==
             {[
                :non_updatable,
                :no_query_load,
                :uuid,
                :array,
                :count,
                :password,
                :email,
                :name,
                :id
              ], [:unwritable]}

    assert Schema.__schema__(:updatable_fields) ==
             {[:no_query_load, :uuid, :array, :count, :password, :email, :name, :id],
              [:non_updatable, :unwritable]}

    assert Schema.__schema__(:virtual_fields) == [:temp]

    assert Schema.__schema__(:query_fields) ==
             [
               :id,
               :name,
               :email,
               :password,
               :count,
               :array,
               :uuid,
               :unwritable,
               :non_updatable
             ]

    assert Schema.__schema__(:read_after_writes) == [:email, :count]
    assert Schema.__schema__(:primary_key) == [:id]
    assert Schema.__schema__(:autogenerate_id) == {:id, :id, :id}
    assert Schema.__schema__(:autogenerate_fields) == [:name, :uuid]
  end

  test "types metadata" do
    assert Schema.__schema__(:type, :id) == :id
    assert Schema.__schema__(:type, :name) == :string
    assert Schema.__schema__(:type, :email) == :string
    assert Schema.__schema__(:type, :array) == {:array, :string}
  end

  test "sources metadata" do
    assert Schema.__schema__(:field_source, :id) == :id
    assert Schema.__schema__(:field_source, :name) == :name
    assert Schema.__schema__(:field_source, :email) == :email
    assert Schema.__schema__(:field_source, :array) == :array
    assert Schema.__schema__(:field_source, :count) == :cnt
    assert Schema.__schema__(:field_source, :xyz) == nil
  end

  test "changeset metadata" do
    assert Schema.__changeset__() |> Map.drop([:comment, :permalink]) ==
             %{
               name: :string,
               email: :string,
               password: :string,
               count: :decimal,
               array: {:array, :string},
               temp: :any,
               id: :id,
               uuid: Ecto.UUID,
               no_query_load: :string,
               unwritable: :string,
               non_updatable: :string
             }
  end

  test "autogenerate metadata (private)" do
    assert Schema.__schema__(:autogenerate) ==
             [{[:name], {String, :upcase, ["eric"]}}, {[:uuid], {Ecto.UUID, :autogenerate, []}}]

    assert Schema.__schema__(:autoupdate) == []
  end

  test "skip field with define_field false" do
    refute Schema.__schema__(:type, :permalink_id)
  end

  test "primary key operations" do
    assert Ecto.primary_key(%Schema{}) == [id: nil]
    assert Ecto.primary_key(%Schema{id: "hello"}) == [id: "hello"]
  end

  test "reads and writes metadata" do
    schema = %Schema{}
    assert schema.__meta__.source == "my schema"
    assert schema.__meta__.prefix == nil
    schema = Ecto.put_meta(schema, source: "new schema")
    assert schema.__meta__.source == "new schema"
    schema = Ecto.put_meta(schema, prefix: "prefix")
    assert schema.__meta__.prefix == "prefix"
    assert Ecto.get_meta(schema, :prefix) == "prefix"
    assert Ecto.get_meta(schema, :source) == "new schema"
    assert schema.__meta__.schema == Schema

    schema = Ecto.put_meta(schema, context: "foobar", state: :loaded)
    assert schema.__meta__.state == :loaded
    assert schema.__meta__.context == "foobar"
    assert Ecto.get_meta(schema, :state) == :loaded
    assert Ecto.get_meta(schema, :context) == "foobar"
  end

  test "raises on invalid state in metadata" do
    assert_raise ArgumentError, "invalid state nil", fn ->
      Ecto.put_meta(%Schema{}, state: nil)
    end
  end

  test "raises on unknown meta key in metadata" do
    assert_raise ArgumentError, "unknown meta key :foo", fn ->
      Ecto.put_meta(%Schema{}, foo: :bar)
    end
  end

  test "preserves schema on up to date metadata" do
    old_schema = %Schema{}
    new_schema = Ecto.put_meta(old_schema, source: "my schema", state: :built, prefix: nil)
    assert :erts_debug.same(old_schema, new_schema)
  end

  test "inspects metadata" do
    schema = %Schema{}
    assert inspect(schema.__meta__) == "#Ecto.Schema.Metadata<:built, \"my schema\">"

    schema = Ecto.put_meta(%Schema{}, context: <<0>>)
    assert inspect(schema.__meta__) == "#Ecto.Schema.Metadata<:built, \"my schema\", <<0>>>"
  end

  test "defaults" do
    assert %Schema{}.name == "eric"
    assert %Schema{}.array == nil
  end

  test "redacted_fields" do
    assert Schema.__schema__(:redact_fields) == [:temp, :password]
  end

  defmodule SchemaWithRedactAllExceptPrimaryKeys do
    use Ecto.Schema

    @schema_redact :all_except_primary_keys
    schema "my_schema" do
      field(:password, :string)
      field(:temp, :any, default: "temp", virtual: true)
    end
  end

  defmodule SchemaWithoutDeriveInspect do
    use Ecto.Schema

    @derive_inspect_for_redacted_fields false

    schema "my_schema" do
      field(:password, :string, redact: true)
    end
  end

  test "doesn't derive inspect" do
    assert inspect(%SchemaWithoutDeriveInspect{password: "hunter2"}) =~ "hunter2"
  end

  ## Schema prefix

  defmodule SchemaWithPrefix do
    use Ecto.Schema

    @schema_prefix "tenant"
    schema "company" do
      field(:name)
    end
  end

  defmodule SchemaWithNonStringPrefix do
    use Ecto.Schema

    @schema_prefix %{key: :tenant}
    schema "company" do
      field(:name)
    end
  end

  test "schema prefix metadata" do
    assert SchemaWithPrefix.__schema__(:source) == "company"
    assert SchemaWithPrefix.__schema__(:prefix) == "tenant"
    assert %SchemaWithPrefix{}.__meta__.source == "company"
    assert %SchemaWithPrefix{}.__meta__.prefix == "tenant"
  end

  test "schema prefix in queries from" do
    import Ecto.Query

    query = from(SchemaWithPrefix, select: 1)
    assert query.from.prefix == "tenant"

    query = from({"another_company", SchemaWithPrefix}, select: 1)
    assert query.from.prefix == "tenant"

    from = SchemaWithPrefix
    query = from(from, select: 1)
    assert query.from.prefix == "tenant"

    from = {"another_company", SchemaWithPrefix}
    query = from(from, select: 1)
    assert query.from.prefix == "tenant"
  end

  test "schema non-string prefix metadata" do
    assert SchemaWithNonStringPrefix.__schema__(:source) == "company"
    assert SchemaWithNonStringPrefix.__schema__(:prefix) == %{key: :tenant}
    assert %SchemaWithNonStringPrefix{}.__meta__.source == "company"
    assert %SchemaWithNonStringPrefix{}.__meta__.prefix == %{key: :tenant}
  end

  test "schema non-string prefix in queries from" do
    import Ecto.Query

    query = from(SchemaWithNonStringPrefix, select: 1)
    assert query.from.prefix == %{key: :tenant}

    query = from({"another_company", SchemaWithNonStringPrefix}, select: 1)
    assert query.from.prefix == %{key: :tenant}

    from = SchemaWithNonStringPrefix
    query = from(from, select: 1)
    assert query.from.prefix == %{key: :tenant}

    from = {"another_company", SchemaWithNonStringPrefix}
    query = from(from, select: 1)
    assert query.from.prefix == %{key: :tenant}
  end

  ## Schema context
  defmodule SchemaWithContext do
    use Ecto.Schema

    @schema_context %{some: :data}
    schema "company" do
      field(:name)
    end
  end

  test "schema context metadata" do
    assert %SchemaWithContext{}.__meta__.context == %{some: :data}
  end

  ## Composite primary keys

  defmodule SchemaCompositeKeys do
    use Ecto.Schema

    # Extra key without disabling @primary_key
    schema "composite_keys" do
      field(:second_id, :id, primary_key: true)
      field(:name)
    end
  end

  # Associative_entity map example:
  # https://en.wikipedia.org/wiki/Associative_entity
  defmodule AssocCompositeKeys do
    use Ecto.Schema

    @primary_key false
    schema "student_course_registers" do
      belongs_to(:student, Student, primary_key: true)
      belongs_to(:course, Course, foreign_key: :course_ref_id, primary_key: true)
    end
  end

  test "composite primary keys" do
    assert SchemaCompositeKeys.__schema__(:primary_key) == [:id, :second_id]
    assert AssocCompositeKeys.__schema__(:primary_key) == [:student_id, :course_ref_id]

    c = %SchemaCompositeKeys{id: 1, second_id: 2}
    assert Ecto.primary_key(c) == [id: 1, second_id: 2]
    assert Ecto.primary_key!(c) == [id: 1, second_id: 2]

    sc = %AssocCompositeKeys{student_id: 1, course_ref_id: 2}
    assert Ecto.primary_key!(sc) == [student_id: 1, course_ref_id: 2]
  end

  ## Errors

  test "field name clash" do
    assert_raise ArgumentError, ~r"field/association :name already exists on schema", fn ->
      defmodule SchemaFieldNameClash do
        use Ecto.Schema

        schema "clash" do
          field(:name, :string)
          field(:name, :integer)
        end
      end
    end
  end

  test "default of invalid type" do
    assert_raise ArgumentError,
                 ~s/value "1" is invalid for type :integer, can't set default/,
                 fn ->
                   defmodule SchemaInvalidDefault do
                     use Ecto.Schema

                     schema "invalid_default" do
                       field(:count, :integer, default: "1")
                     end
                   end
                 end

    assert_raise ArgumentError, ~s/value 1 is invalid for type :string, can't set default/, fn ->
      defmodule SchemaInvalidDefault do
        use Ecto.Schema

        schema "invalid_default" do
          field(:count, :string, default: 1)
        end
      end
    end
  end

  test "skipping validations on invalid types" do
    defmodule SchemaSkipValidationsDefault do
      use Ecto.Schema

      schema "invalid_default" do
        # Without skip_default_validation this would fail to compile
        field(:count, :integer, default: "1", skip_default_validation: true)
      end
    end
  end

  test "invalid option for field" do
    assert_raise ArgumentError, ~s/invalid option :starts_on for field\/3/, fn ->
      defmodule SchemaInvalidFieldOption do
        use Ecto.Schema

        schema "invalid_option" do
          field(:count, :integer, starts_on: 3)
        end
      end
    end

    # doesn't validate for parameterized types
    defmodule SchemaInvalidOptionParameterized do
      use Ecto.Schema

      schema "invalid_option_parameterized" do
        field(:my_enum, Ecto.Enum, values: [:a, :b], random_option: 3)
        field(:my_enums, Ecto.Enum, values: [:a, :b], random_option: 3)
      end
    end
  end

  test "invalid field type" do
    assert_raise ArgumentError, "invalid type {:apa} for field :name", fn ->
      defmodule SchemaInvalidFieldType do
        use Ecto.Schema

        schema "invalidtype" do
          field(:name, {:apa})
        end
      end
    end

    assert_raise ArgumentError, "unknown type OMG for field :name", fn ->
      defmodule SchemaInvalidFieldType do
        use Ecto.Schema

        schema "invalidtype" do
          field(:name, OMG)
        end
      end
    end

    assert_raise ArgumentError, "unknown type :jsonb for field :name", fn ->
      defmodule SchemaInvalidFieldType do
        use Ecto.Schema

        schema "invalidtype" do
          field(:name, {:array, :jsonb})
        end
      end
    end
  end

  test "fail invalid schema" do
    assert_raise ArgumentError, "schema source must be a string, got: :hello", fn ->
      defmodule SchemaFail do
        use Ecto.Schema

        schema :hello do
          field(:x, :string)
          field(:pk, :integer, primary_key: true)
        end
      end
    end
  end

  test "defining schema twice will result with meaningful error" do
    quoted = """
    defmodule DoubleSchema do
      use Ecto.Schema

      schema "my schema" do
        field :name, :string
      end

      schema "my schema" do
        field :name, :string
      end
    end
    """

    message = "schema already defined for DoubleSchema on line 4"

    assert_raise RuntimeError, message, fn ->
      Code.compile_string(quoted, "example.ex")
    end
  end

  describe "type :any" do
    test "raises on non-virtual" do
      assert_raise ArgumentError, ~r"only virtual fields can have type :any", fn ->
        defmodule FieldAny do
          use Ecto.Schema

          schema "anything" do
            field(:json, :any)
          end
        end
      end
    end

    defmodule FieldAnyVirtual do
      use Ecto.Schema

      schema "anything" do
        field(:json, :any, virtual: true)
      end
    end

    test "is allowed if virtual" do
      assert %{json: :any} = FieldAnyVirtual.__changeset__()
    end

    defmodule FieldAnyNested do
      use Ecto.Schema

      schema "anything" do
        field(:json, {:array, :any})
      end
    end

    test "is allowed if nested" do
      assert %{json: {:array, :any}} = FieldAnyNested.__changeset__()
    end
  end

  describe "preload_order option" do
    test "allows MFA" do
      defmodule MFA do
        use Ecto.Schema

        schema "assoc" do
          many_to_many(:posts, Post,
            join_through: "through",
            preload_order: {__MODULE__, :fun, []}
          )
        end
      end
    end

    test "invalid option" do
      message =
        "expected `:preload_order` for :posts to be a keyword list, a list of atoms/fields or a {Mod, fun, args} tuple, got: `:title`"

      assert_raise ArgumentError, message, fn ->
        defmodule ThroughMatch do
          use Ecto.Schema

          schema "assoc" do
            has_many(:posts, Post, preload_order: :title)
          end
        end
      end
    end

    test "invalid direction" do
      message =
        "expected `:preload_order` for :posts to be a keyword list or a list of atoms/fields, " <>
          "got: `[invalid_direction: :title]`, `:invalid_direction` is not a valid direction"

      assert_raise ArgumentError, message, fn ->
        defmodule ThroughMatch do
          use Ecto.Schema

          schema "assoc" do
            has_many(:posts, Post, preload_order: [invalid_direction: :title])
          end
        end
      end
    end

    test "invalid item" do
      message =
        "expected `:preload_order` for :posts to be a keyword list or a list of atoms/fields, " <>
          "got: `[\"text\"]`, `\"text\"` is not valid"

      assert_raise ArgumentError, message, fn ->
        defmodule ThroughMatch do
          use Ecto.Schema

          schema "assoc" do
            has_many(:posts, Post, preload_order: ["text"])
          end
        end
      end
    end
  end

  test "raises on :source field not using atom key" do
    assert_raise ArgumentError,
                 ~s(the :source for field `name` must be an atom, got: "string"),
                 fn ->
                   defmodule InvalidCustomSchema do
                     use Ecto.Schema

                     schema "users" do
                       field(:name, :string, source: "string")
                     end
                   end
                 end
  end
end
