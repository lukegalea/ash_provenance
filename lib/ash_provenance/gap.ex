defmodule AshProvenance.Gap do
  @moduledoc """
  A place where an explanation stops, and why.

  Kinds: `:unreadable` (the reader may not see the antecedent), `:failed`, `:erased`, `:not_recorded`, `:archived`.
  `of` is the address of the readable value this is an antecedent of. `receipt` is a trace reference to the shred
  receipt and is allowed only on `:erased`. An `:unreadable` gap carries only `kind` and `of`: no receipt, time or
  summary, so nothing about the hidden row leaks.
  """

  alias AshProvenance.Address

  @kinds [:unreadable, :failed, :erased, :not_recorded, :archived]

  @enforce_keys [:kind]
  defstruct [:kind, :of, :receipt, :at, :summary]

  @type t :: %__MODULE__{
          kind: atom(),
          of: Address.t() | nil,
          receipt: binary() | nil,
          at: DateTime.t() | nil,
          summary: binary() | nil
        }

  @doc "Builds a gap."
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(%{kind: kind} = opts) when kind in @kinds do
    gap = struct!(__MODULE__, Map.take(opts, [:kind, :of, :receipt, :at, :summary]))

    with :ok <- check_of(gap.of),
         :ok <- check_receipt(gap),
         :ok <- check_at(gap.at),
         :ok <- check_summary(gap.summary),
         :ok <- check_unreadable(gap) do
      {:ok, gap}
    end
  end

  def new(_), do: {:error, {:invalid, :kind}}

  @doc "Like `new/1`, raising `ArgumentError` on an error."
  @spec new!(keyword() | map()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, gap} -> gap
      {:error, reason} -> raise ArgumentError, "invalid gap: #{inspect(reason)}"
    end
  end

  @doc "An `:unreadable` gap for the value at `of`."
  @spec unreadable(Address.t() | nil) :: {:ok, t()} | {:error, term()}
  def unreadable(of), do: new(kind: :unreadable, of: of)

  defp check_of(nil), do: :ok
  defp check_of(%Address{}), do: :ok
  defp check_of(_), do: {:error, {:invalid, :of}}

  defp check_receipt(%{receipt: nil}), do: :ok

  defp check_receipt(%{kind: :erased, receipt: receipt}) when is_binary(receipt) do
    case Address.split_trace_ref(receipt) do
      {:ok, _, _} -> :ok
      _ -> {:error, {:invalid, :receipt}}
    end
  end

  defp check_receipt(_), do: {:error, {:not_allowed, :receipt}}

  defp check_at(nil), do: :ok
  defp check_at(%DateTime{}), do: :ok
  defp check_at(_), do: {:error, {:invalid, :at}}

  defp check_summary(nil), do: :ok

  defp check_summary(s) when is_binary(s) and byte_size(s) <= 280,
    do: if(String.valid?(s), do: :ok, else: {:error, {:invalid, :summary}})

  defp check_summary(_), do: {:error, {:invalid, :summary}}

  defp check_unreadable(%{kind: :unreadable} = gap) do
    case Enum.find([:receipt, :at, :summary], &(Map.get(gap, &1) != nil)) do
      nil -> :ok
      field -> {:error, {:not_allowed, field}}
    end
  end

  defp check_unreadable(_), do: :ok
end
