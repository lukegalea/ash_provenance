defmodule AshProvenance.EntityRef do
  @moduledoc """
  A reference to a record: its resource type token, id, optional version number and instant, and an optional content
  digest.

  The digest is keyed under the subject's erasure scope (`%{scope: scope, digest: hex}`), so destroying the scope's key
  makes it unverifiable. A bare binary digest is refused with `{:error, :unkeyed_digest}`.
  """

  alias AshProvenance.Address

  @enforce_keys [:resource, :id]
  defstruct [:resource, :id, :version_number, :as_of, :content_digest]

  @type digest :: %{scope: binary(), digest: binary()}
  @type t :: %__MODULE__{
          resource: binary(),
          id: Address.id(),
          version_number: non_neg_integer() | nil,
          as_of: DateTime.t() | nil,
          content_digest: digest() | nil
        }

  @doc "Builds an entity reference."
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(%{} = opts) do
    with {:ok, resource} <- Address.validate_type(Map.get(opts, :resource)),
         {:ok, id} <- Address.validate_id(Map.get(opts, :id)),
         {:ok, version} <- validate_version(Map.get(opts, :version_number)),
         {:ok, as_of} <- Address.validate_as_of(Map.get(opts, :as_of)),
         {:ok, digest} <- validate_digest(Map.get(opts, :content_digest)) do
      {:ok, %__MODULE__{resource: resource, id: id, version_number: version, as_of: as_of, content_digest: digest}}
    end
  end

  @doc "Like `new/1`, raising `ArgumentError` on an error."
  @spec new!(keyword() | map()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, ref} -> ref
      {:error, reason} -> raise ArgumentError, "invalid entity ref: #{inspect(reason)}"
    end
  end

  @doc "The address naming this reference. Takes `base:` and optionally `attribute:`."
  @spec to_address(t(), keyword()) :: {:ok, Address.t()} | {:error, term()}
  def to_address(%__MODULE__{} = ref, opts) do
    Address.new(
      base: Keyword.fetch!(opts, :base),
      type: ref.resource,
      id: ref.id,
      attribute: Keyword.get(opts, :attribute),
      as_of: ref.as_of
    )
  end

  defp validate_version(nil), do: {:ok, nil}
  defp validate_version(n) when is_integer(n) and n >= 0, do: {:ok, n}
  defp validate_version(_), do: {:error, {:invalid, :version_number}}

  defp validate_digest(nil), do: {:ok, nil}
  defp validate_digest(bin) when is_binary(bin), do: {:error, :unkeyed_digest}

  defp validate_digest(%{scope: scope, digest: digest} = d)
       when is_binary(scope) and scope != "" and is_binary(digest) do
    if map_size(d) == 2 and Regex.match?(~r/\A[0-9a-f]{64}\z/, digest),
      do: {:ok, d},
      else: {:error, {:invalid, :content_digest}}
  end

  defp validate_digest(_), do: {:error, {:invalid, :content_digest}}
end
