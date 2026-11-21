defmodule AshProvenance.DepsTest do
  use ExUnit.Case, async: true

  test "the only dependencies are jason, stream_data and credo, dev and test only" do
    deps = Mix.Project.config()[:deps]
    assert deps |> Enum.map(&elem(&1, 0)) |> Enum.sort() == [:credo, :jason, :stream_data]
    assert Enum.all?(deps, fn {_, _, opts} -> opts[:only] == [:dev, :test] end)
  end
end
