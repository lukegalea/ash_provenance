defmodule AshProvenance.ExplanationTest do
  use ExUnit.Case, async: true

  alias AshProvenance.{Explanation, Fixtures, Step}

  test "fixtures build" do
    for {_, e} <- Fixtures.all(), do: assert(%Explanation{} = e)
  end

  test "step_count must match" do
    e = Fixtures.audited_attribute()

    assert {:error, {:invalid, :step_count}} =
             Explanation.new(subject: e.subject, steps: e.steps, bounds: %{e.bounds | step_count: 0})
  end

  test "bounds are required and typed" do
    e = Fixtures.audited_attribute()
    assert {:error, {:missing, :bounds}} = Explanation.new(subject: e.subject, steps: e.steps)

    assert {:error, {:invalid, :bounds}} =
             Explanation.new(subject: e.subject, steps: e.steps, bounds: Map.delete(e.bounds, :depth))

    assert {:error, {:invalid, :bounds}} =
             Explanation.new(subject: e.subject, steps: e.steps, bounds: %{e.bounds | cut?: nil})
  end

  test "steps and gaps must come from their constructors" do
    e = Fixtures.audited_attribute()
    bad = %Step{relation: :used, granularity: :value}

    assert {:error, {:invalid, :steps}} =
             Explanation.new(subject: e.subject, steps: [bad], bounds: %{e.bounds | step_count: 1})

    assert {:error, {:invalid, :gaps}} =
             Explanation.new(subject: e.subject, steps: [], gaps: [:x], bounds: %{e.bounds | step_count: 0})
  end
end
