defmodule AshProvenance.Explanation do
  @moduledoc """
  The answer to "where did this value come from": the subject address, the steps, the gaps and the bounds the walk ran
  under.

  `bounds` is `%{max_depth, max_steps, depth, step_count, cut?}`. `step_count` must equal the number of steps, and
  `cut?: true` is the only way an answer may stop short: there is no silent cap.
  """

  alias AshProvenance.{Address, Gap, Step}

  @enforce_keys [:subject, :steps, :gaps, :bounds]
  defstruct [:subject, :steps, :gaps, :bounds]

  @type bounds :: %{
          max_depth: non_neg_integer(),
          max_steps: non_neg_integer(),
          depth: non_neg_integer(),
          step_count: non_neg_integer(),
          cut?: boolean()
        }
  @type t :: %__MODULE__{subject: Address.t(), steps: [Step.t()], gaps: [Gap.t()], bounds: bounds()}

  @int_keys [:max_depth, :max_steps, :depth, :step_count]

  @doc "Builds an explanation. `gaps` defaults to `[]`, `steps` to `[]`; `bounds` is required."
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(%{} = opts) do
    steps = Map.get(opts, :steps, [])
    gaps = Map.get(opts, :gaps, [])

    with {:ok, subject} <- check_subject(Map.get(opts, :subject)),
         :ok <- check_all(steps, Step, :steps),
         :ok <- check_all(gaps, Gap, :gaps),
         {:ok, bounds} <- check_bounds(Map.get(opts, :bounds), length(steps)) do
      {:ok, %__MODULE__{subject: subject, steps: steps, gaps: gaps, bounds: bounds}}
    end
  end

  @doc "Like `new/1`, raising `ArgumentError` on an error."
  @spec new!(keyword() | map()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, e} -> e
      {:error, reason} -> raise ArgumentError, "invalid explanation: #{inspect(reason)}"
    end
  end

  defp check_subject(%Address{} = a) do
    if Address.new(Map.from_struct(a)) == {:ok, a}, do: {:ok, a}, else: {:error, {:invalid, :subject}}
  end

  defp check_subject(_), do: {:error, {:invalid, :subject}}

  defp check_all(items, mod, field) when is_list(items) do
    if Enum.all?(items, &built_by_constructor?(&1, mod)), do: :ok, else: {:error, {:invalid, field}}
  end

  defp check_all(_, _, field), do: {:error, {:invalid, field}}

  defp built_by_constructor?(%mod{} = item, mod), do: mod.new(Map.from_struct(item)) == {:ok, item}
  defp built_by_constructor?(_, _), do: false

  defp check_bounds(%{cut?: cut} = bounds, count) when is_boolean(cut) do
    cond do
      Map.keys(bounds) -- [:cut? | @int_keys] != [] -> {:error, {:invalid, :bounds}}
      not Enum.all?(@int_keys, &non_neg_int?(Map.get(bounds, &1))) -> {:error, {:invalid, :bounds}}
      bounds.step_count != count -> {:error, {:invalid, :step_count}}
      true -> {:ok, bounds}
    end
  end

  defp check_bounds(nil, _), do: {:error, {:missing, :bounds}}
  defp check_bounds(_, _), do: {:error, {:invalid, :bounds}}

  defp non_neg_int?(n), do: is_integer(n) and n >= 0
end
