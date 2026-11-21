defmodule AshProvenance.Integrity do
  @moduledoc """
  The result of an integrity check on a step: which anchor was checked, the verifier's status and when.

  `:audit_chain` and `:ledger_chain` take `:verified | :altered | :broken_link | :unchained`; `:signature_record` takes
  `:verified | :altered`. `:unchained` is not `:verified`. A step with no integrity means "not checked".
  """

  @enforce_keys [:anchor, :status, :verified_at]
  defstruct [:anchor, :status, :verified_at]

  @type anchor :: :audit_chain | :ledger_chain | :signature_record
  @type t :: %__MODULE__{anchor: anchor(), status: atom(), verified_at: DateTime.t()}

  @chain_statuses [:verified, :altered, :broken_link, :unchained]
  @signature_statuses [:verified, :altered]

  @doc "Builds an integrity result."
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(%{anchor: anchor, status: status, verified_at: %DateTime{} = at}) do
    if status in statuses(anchor),
      do: {:ok, %__MODULE__{anchor: anchor, status: status, verified_at: at}},
      else: {:error, {:invalid, :status}}
  end

  def new(_), do: {:error, {:invalid, :integrity}}

  @doc "Like `new/1`, raising `ArgumentError` on an error."
  @spec new!(keyword() | map()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, i} -> i
      {:error, reason} -> raise ArgumentError, "invalid integrity: #{inspect(reason)}"
    end
  end

  defp statuses(anchor) when anchor in [:audit_chain, :ledger_chain], do: @chain_statuses
  defp statuses(:signature_record), do: @signature_statuses
  defp statuses(_), do: []
end
