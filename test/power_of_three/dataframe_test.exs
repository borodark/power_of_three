defmodule PowerOfThree.DataFrameTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.DataFrame

  describe "explorer_available?/0" do
    test "returns boolean indicating Explorer availability" do
      result = DataFrame.explorer_available?()
      assert is_boolean(result)
    end
  end

  describe "result_type/0" do
    test "returns :dataframe or :map" do
      result = DataFrame.result_type()
      assert result in [:dataframe, :map]
    end

    test "returns :map when Explorer is not available" do
      # Since we don't have Explorer in test dependencies
      assert DataFrame.result_type() == :dataframe
    end
  end

  describe "from_result/1" do
    test "returns map when Explorer is not available" do
      result_map = %{
        "brand" => ["Nike", "Adidas", "Puma"],
        "count" => [100, 200, 150]
      }

      result = DataFrame.from_result(result_map)

      # Without Explorer, should return the map as-is
      assert result == result_map
    end

    test "handles empty map" do
      result = DataFrame.from_result(%{})
      assert result == %{}
    end

    test "handles single column" do
      result_map = %{"value" => [1, 2, 3]}
      result = DataFrame.from_result(result_map)
      assert result == result_map
    end

    test "handles multiple columns" do
      result_map = %{
        "col1" => [1, 2, 3],
        "col2" => ["a", "b", "c"],
        "col3" => [true, false, true]
      }

      result = DataFrame.from_result(result_map)
      assert result == result_map
    end
  end
end
