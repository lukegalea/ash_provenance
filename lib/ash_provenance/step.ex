defmodule AshProvenance.Step do
  @moduledoc """
  One PROV-DM statement about a value or record.

  `relation` selects the statement; the fields it requires are checked by `new/1`:

    * `:was_generated_by`, `:used`, `:was_invalidated_by` need `entity` and `activity`
    * `:was_derived_from`, `:was_revision_of`, `:had_primary_source` need `entity` and `antecedent`
    * `:was_attributed_to` needs `entity` and `agent_label`
    * `:was_associated_with` needs `activity` and `agent_label`
    * `:acted_on_behalf_of` needs `agent_label` and `on_behalf_of`; `on_behalf_of` is refused elsewhere

  `entity` and `antecedent` are an `AshProvenance.EntityRef` or `AshProvenance.Address`. `activity` is a trace
  reference `"<type>:<encoded id>"`. `agent_label` is a display label, never an identifier. A nil `execution_context`
  means "not recorded". `value` is `nil` (none shown), `:masked` (a value the reader may not see) or `{:value, scalar}`.
  A nil `integrity` means "not checked".
  """

  alias AshProvenance.{Address, EntityRef, Integrity, Plan}

  @relations [
    :was_generated_by,
    :was_derived_from,
    :used,
    :was_attributed_to,
    :was_associated_with,
    :acted_on_behalf_of,
    :was_invalidated_by,
    :was_revision_of,
    :had_primary_source
  ]

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

  @fields [
    :relation,
    :entity,
    :antecedent,
    :activity,
    :agent_label,
    :on_behalf_of,
    :plan,
    :at,
    :execution_context,
    :granularity,
    :value,
    :summary,
    :integrity
  ]

  @enforce_keys [:relation, :granularity]
  defstruct @fields

  @type ref :: EntityRef.t() | Address.t()
  @type value :: nil | :masked | {:value, binary() | number() | boolean()}
  @type t :: %__MODULE__{
          relation: atom(),
          entity: ref() | nil,
          antecedent: ref() | nil,
          activity: binary() | nil,
          agent_label: binary() | nil,
          on_behalf_of: binary() | nil,
          plan: Plan.t() | nil,
          at: DateTime.t() | nil,
          execution_context: atom() | nil,
          granularity: :value | :record,
          value: value(),
          summary: binary() | nil,
          integrity: Integrity.t() | nil
        }

  @doc "The relations a step may have."
  @spec relations() :: [atom()]
  def relations, do: @relations

  @doc "Builds a step."
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(%{relation: relation} = opts) when relation in @relations do
    with :ok <- check_required(relation, opts),
         :ok <- check_on_behalf_of(relation, opts),
         :ok <- check_all(opts) do
      {:ok, struct!(__MODULE__, Map.take(opts, @fields))}
    end
  end

  def new(_), do: {:error, {:invalid, :relation}}

  @doc "Like `new/1`, raising `ArgumentError` on an error."
  @spec new!(keyword() | map()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, step} -> step
      {:error, reason} -> raise ArgumentError, "invalid step: #{inspect(reason)}"
    end
  end

  defp check_required(relation, opts) do
    case Enum.find(Map.fetch!(@required, relation), &is_nil(Map.get(opts, &1))) do
      nil -> :ok
      field -> {:error, {:missing, field}}
    end
  end

  defp check_on_behalf_of(:acted_on_behalf_of, _), do: :ok
  defp check_on_behalf_of(_, %{on_behalf_of: nil}), do: :ok
  defp check_on_behalf_of(_, %{on_behalf_of: _}), do: {:error, {:not_allowed, :on_behalf_of}}
  defp check_on_behalf_of(_, _), do: :ok

  defp check_all(opts) do
    Enum.find_value(@fields -- [:relation], :ok, fn field ->
      if valid?(field, Map.get(opts, field)), do: nil, else: {:error, {:invalid, field}}
    end)
  end

  defp valid?(field, nil) when field != :granularity, do: true
  defp valid?(field, %mod{}) when field in [:entity, :antecedent], do: mod in [EntityRef, Address]
  defp valid?(:activity, ref), do: match?({:ok, _, _}, ref |> trace_ref())
  defp valid?(field, label) when field in [:agent_label, :on_behalf_of], do: label?(label)
  defp valid?(:plan, %Plan{}), do: true
  defp valid?(:at, %DateTime{}), do: true
  defp valid?(:execution_context, ctx), do: is_atom(ctx) and not is_boolean(ctx)
  defp valid?(:granularity, g), do: g in [:value, :record]
  defp valid?(:value, :masked), do: true
  defp valid?(:value, {:value, v}), do: is_binary(v) or is_number(v) or is_boolean(v)
  defp valid?(:summary, s), do: is_binary(s) and byte_size(s) <= 280 and String.valid?(s)
  defp valid?(:integrity, %Integrity{}), do: true
  defp valid?(_, _), do: false

  defp label?(label), do: is_binary(label) and label != "" and String.valid?(label)

  defp trace_ref(ref) when is_binary(ref), do: Address.split_trace_ref(ref)
  defp trace_ref(_), do: :error
end
