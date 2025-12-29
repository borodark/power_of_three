defmodule PowerOfThree.FilterConditionTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.{FilterCondition, DimensionRef, MeasureRef}

  setup do
    brand_dim = %DimensionRef{
      name: :brand,
      sql: "brand_code",
      type: :string,
      module: Customer
    }

    count_measure = %MeasureRef{
      name: :count,
      type: :count,
      module: Customer
    }

    {:ok, brand: brand_dim, count: count_measure}
  end

  describe "validate/1" do
    test "validates valid filter conditions", %{brand: brand} do
      assert :ok = FilterCondition.validate({brand, :==, "BQ"})
      assert :ok = FilterCondition.validate({brand, :!=, "Corona"})
      assert :ok = FilterCondition.validate({brand, :in, ["BQ", "Corona"]})
    end

    test "rejects invalid operators", %{brand: brand} do
      assert {:error, _} = FilterCondition.validate({brand, :invalid, "BQ"})
    end

    test "rejects invalid column references" do
      assert {:error, _} = FilterCondition.validate({:not_a_ref, :==, "BQ"})
    end

    test "rejects non-tuple formats" do
      assert {:error, _} = FilterCondition.validate("invalid")
    end
  end

  describe "to_cube_filter/1" do
    test "converts equality condition", %{brand: brand} do
      {:ok, filter} = FilterCondition.to_cube_filter({brand, :==, "BQ"})

      assert filter["member"] == "power_customers.brand"
      assert filter["operator"] == "equals"
      assert filter["values"] == ["BQ"]
    end

    test "converts not equals condition", %{brand: brand} do
      {:ok, filter} = FilterCondition.to_cube_filter({brand, :!=, "Corona"})

      assert filter["member"] == "power_customers.brand"
      assert filter["operator"] == "notEquals"
      assert filter["values"] == ["Corona"]
    end

    test "converts greater than condition", %{count: count} do
      {:ok, filter} = FilterCondition.to_cube_filter({count, :>, 1000})

      assert filter["member"] == "power_customers.count"
      assert filter["operator"] == "gt"
      assert filter["values"] == [1000]
    end

    test "converts IN condition", %{brand: brand} do
      {:ok, filter} = FilterCondition.to_cube_filter({brand, :in, ["BQ", "Corona", "Heineken"]})

      assert filter["member"] == "power_customers.brand"
      assert filter["operator"] == "equals"
      assert filter["values"] == ["BQ", "Corona", "Heineken"]
    end

    test "converts IS NULL condition", %{brand: brand} do
      {:ok, filter} = FilterCondition.to_cube_filter({brand, :is_nil, nil})

      assert filter["member"] == "power_customers.brand"
      assert filter["operator"] == "notSet"
      assert filter["values"] == []
    end

    test "converts IS NOT NULL condition", %{brand: brand} do
      {:ok, filter} = FilterCondition.to_cube_filter({brand, :is_not_nil, nil})

      assert filter["member"] == "power_customers.brand"
      assert filter["operator"] == "set"
      assert filter["values"] == []
    end
  end

  describe "to_sql/1" do
    test "converts equality condition", %{brand: brand} do
      {:ok, sql} = FilterCondition.to_sql({brand, :==, "BQ"})
      assert sql == "brand = 'BQ'"
    end

    test "converts not equals condition", %{brand: brand} do
      {:ok, sql} = FilterCondition.to_sql({brand, :!=, "Corona"})
      assert sql == "brand != 'Corona'"
    end

    test "converts greater than condition", %{count: count} do
      {:ok, sql} = FilterCondition.to_sql({count, :>, 1000})
      assert sql == "count > 1000"
    end

    test "converts less than or equal condition", %{count: count} do
      {:ok, sql} = FilterCondition.to_sql({count, :<=, 500})
      assert sql == "count <= 500"
    end

    test "converts IN condition", %{brand: brand} do
      {:ok, sql} = FilterCondition.to_sql({brand, :in, ["BQ", "Corona", "Heineken"]})
      assert sql == "brand IN ('BQ', 'Corona', 'Heineken')"
    end

    test "converts NOT IN condition", %{brand: brand} do
      {:ok, sql} = FilterCondition.to_sql({brand, :not_in, ["BQ", "Corona"]})
      assert sql == "brand NOT IN ('BQ', 'Corona')"
    end

    test "converts LIKE condition", %{brand: brand} do
      {:ok, sql} = FilterCondition.to_sql({brand, :like, "%Light%"})
      assert sql == "brand LIKE '%Light%'"
    end

    test "converts IS NULL condition", %{brand: brand} do
      {:ok, sql} = FilterCondition.to_sql({brand, :is_nil, nil})
      assert sql == "brand IS NULL"
    end

    test "converts IS NOT NULL condition", %{brand: brand} do
      {:ok, sql} = FilterCondition.to_sql({brand, :is_not_nil, nil})
      assert sql == "brand IS NOT NULL"
    end

    test "escapes single quotes in values", %{brand: brand} do
      {:ok, sql} = FilterCondition.to_sql({brand, :==, "O'Doul's"})
      assert sql == "brand = 'O''Doul''s'"
    end

    test "handles numeric values", %{count: count} do
      {:ok, sql} = FilterCondition.to_sql({count, :==, 42})
      assert sql == "count = 42"
    end
  end
end
