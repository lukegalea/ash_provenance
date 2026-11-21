defmodule AshProvenance.StepTest do
  use ExUnit.Case, async: true

  alias AshProvenance.{Address, Step}

  @addr Address.new!(base: "https://app.example.com/id", type: "t", id: "1")

  @required %{
    was_generated_by: [:entity, :activity],
    used: [:entity, :activity],
    was_invalidated_by: [:entity, :activity],
    was_derived_from: [:entity, :antecedent],
    was_revision_of: [:entity, :antecedent],
    had_primary_source: [:entity, :antecedent],
    was_attributed_to: [:entity, :agent_label],
    was_associated_with: [:activity, :agent_label],
    acted_on_behalf_of: [:agent_label, :on_behalf_of]
  }

  @values %{entity: @addr, antecedent: @addr, activity: "audit_event:1", agent_label: "label", on_behalf_of: "other"}

  defp base(relation),
    do: Map.merge(%{relation: relation, granularity: :value}, Map.take(@values, Map.fetch!(@required, relation)))

  test "every relation builds with its required fields" do
    for relation <- Step.relations(), do: assert({:ok, %Step{}} = Step.new(base(relation)))
  end

  test "each relation refuses each missing required field" do
    for {relation, fields} <- @required, field <- fields do
      assert {:error, {:missing, ^field}} = Step.new(Map.delete(base(relation), field))
    end
  end

  test "on_behalf_of is refused on other relations" do
    assert {:error, {:not_allowed, :on_behalf_of}} = Step.new(Map.put(base(:was_generated_by), :on_behalf_of, "x"))
  end

  test "summary over 280 bytes is refused" do
    assert {:ok, _} = Step.new(Map.put(base(:used), :summary, String.duplicate("a", 280)))
    assert {:error, {:invalid, :summary}} = Step.new(Map.put(base(:used), :summary, String.duplicate("a", 281)))
  end

  test "granularity is required and closed; values are typed" do
    assert {:error, _} = Step.new(Map.delete(base(:used), :granularity))
    assert {:error, _} = Step.new(Map.put(base(:used), :granularity, :other))
    assert {:ok, _} = Step.new(Map.put(base(:used), :value, :masked))
    assert {:ok, _} = Step.new(Map.put(base(:used), :value, {:value, 3}))
    assert {:error, _} = Step.new(Map.put(base(:used), :value, {:value, %{}}))
    assert {:error, _} = Step.new(Map.put(base(:used), :value, {:masked, 1}))
  end

  test "activity must be a trace ref; unknown relation refused" do
    assert {:error, {:invalid, :activity}} = Step.new(Map.put(base(:used), :activity, "nocolon"))
    assert {:error, {:invalid, :relation}} = Step.new(%{relation: :nope, granularity: :value})
  end
end
