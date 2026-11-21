defmodule AshProvenance.MatchedRulesTest do
  use ExUnit.Case, async: true

  alias AshProvenance.MatchedRules

  @after_cutoff ~U[2026-10-01 00:00:00Z]
  @before_cutoff ~U[2026-09-22 23:59:59Z]

  test "every row" do
    assert {:matched, ["r1"]} = MatchedRules.classify(["r1"], nil, nil, @before_cutoff)
    assert {:matched, ["r1"]} = MatchedRules.classify(["r1"], :first, :boom, @after_cutoff)
    assert {:gap, :failed} = MatchedRules.classify([], :first, :boom, @after_cutoff)
    assert {:gap, :failed} = MatchedRules.classify([], nil, :boom, @before_cutoff)
    assert {:gap, :not_recorded} = MatchedRules.classify([], nil, nil, @after_cutoff)
    assert {:gap, :not_recorded} = MatchedRules.classify([], :first, nil, @before_cutoff)
    assert {:gap, :not_recorded} = MatchedRules.classify([], :first, nil, nil)
    assert :no_rule_matched = MatchedRules.classify([], :first, nil, @after_cutoff)
    assert :no_rule_matched = MatchedRules.classify([], :first, nil, ~U[2026-09-23 00:00:00Z])
  end
end
