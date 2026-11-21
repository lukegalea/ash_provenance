defmodule AshProvenance.PlanTest do
  use ExUnit.Case, async: true

  alias AshProvenance.Plan

  test "formats with the first 8 lower-case hex characters" do
    assert {:ok, "pricing@3#a1b2c3d4"} = Plan.format("pricing", "3", "A1B2C3D4E5F6")
  end

  test "parse and format round-trip" do
    assert {:ok, %Plan{key: "k", version: "3", hash8: "a1b2c3d4"} = p} = Plan.parse("k@3#a1b2c3d4")
    assert Plan.format(p) == "k@3#a1b2c3d4"
  end

  test "definition refs have no hash" do
    assert {:ok, %Plan{hash8: nil} = p} = Plan.from_definition_ref("k@3")
    assert Plan.format(p) == "k@3"
    assert {:error, _} = Plan.from_definition_ref("k@3#a1b2c3d4")
  end

  test "refusals" do
    assert {:error, _} = Plan.parse("nokey")
    assert {:error, _} = Plan.parse("k@3#zz")
    assert {:error, _} = Plan.format("k", "3", "abc")
    assert {:error, _} = Plan.parse("k@3#a1b2c3d4#x")
  end
end
