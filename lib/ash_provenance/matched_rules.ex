defmodule AshProvenance.MatchedRules do
  @moduledoc """
  Classifies a recorded decision evaluation into an answer or a gap.

  Evaluations recorded before `2026-09-23T00:00:00Z` did not store the matched rule ids, so an empty list there says
  nothing about whether a rule matched.
  """

  @cutoff ~U[2026-09-23 00:00:00Z]

  @type result :: {:matched, [term(), ...]} | :no_rule_matched | {:gap, :failed} | {:gap, :not_recorded}

  @doc """
  Classifies by, in order: non-empty ids are `{:matched, ids}`; an error is `{:gap, :failed}`; a nil hit policy, or a
  record from before the cutoff (or with no time), is `{:gap, :not_recorded}`; anything else is `:no_rule_matched`.
  """
  @spec classify([term()], term(), term(), DateTime.t() | nil) :: result()
  def classify([_ | _] = ids, _hit_policy, _error, _recorded_at), do: {:matched, ids}
  def classify([], _hit_policy, error, _recorded_at) when not is_nil(error), do: {:gap, :failed}
  def classify([], nil, nil, _recorded_at), do: {:gap, :not_recorded}
  def classify([], _hit_policy, nil, nil), do: {:gap, :not_recorded}

  def classify([], _hit_policy, nil, %DateTime{} = recorded_at) do
    case DateTime.compare(recorded_at, @cutoff) do
      :lt -> {:gap, :not_recorded}
      _ -> :no_rule_matched
    end
  end
end
