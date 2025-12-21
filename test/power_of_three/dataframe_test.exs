defmodule PowerOfThree.CubeFrameTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.CubeFrame

  describe "result_type/0" do
    test "returns :dataframe" do
      assert :dataframe == CubeFrame.result_type()
    end
  end

  describe "from_result/1" do
    test "returns DF" do
      result_map = %{
        "brand" => ["Nike", "Adidas", "Puma"],
        "count" => [100, 200, 150]
      }

      assert {3, 2} == CubeFrame.from_result(result_map) |> Explorer.DataFrame.shape()
    end

    test "handles empty map" do
      result = CubeFrame.from_result(%{})
      result |> IO.inspect(label: "VVV %{} VVV")

      assert %Explorer.Series{
               # %Explorer.PolarsBackend.Series{ },  resource: _,
               data: _,
               dtype: :null,
               name: nil,
               remote: nil
             } = result
    end

    test "handles single column" do
      result_map = %{"value" => [1, 2, 3]}
      # |> IO.inspect(label: "=##--->-")
      result = CubeFrame.from_result(result_map)
      assert [1, 2, 3] == result |> Explorer.Series.to_list()
    end

    test "handles multiple columns" do
      result_map = %{
        "col1" => [1, 2, 3],
        "col2" => ["a", "b", "c"],
        "col3" => [true, false, true]
      }

      result = CubeFrame.from_result(result_map) |> IO.inspect(label: ">>>>>")
      assert result |> Explorer.DataFrame.to_columns() == result_map
    end
  end
end
