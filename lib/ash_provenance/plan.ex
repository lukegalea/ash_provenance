defmodule AshProvenance.Plan do
  @moduledoc """
  A plan reference, `key@version#hash8`: a definition key, its version and the first 8 lower-case hex characters of the
  definition's SHA-256. `from_definition_ref/1` takes `key@version` and leaves `hash8` nil.
  """

  @enforce_keys [:key, :version]
  defstruct [:key, :version, :hash8]

  @type t :: %__MODULE__{key: binary(), version: binary(), hash8: binary() | nil}

  @token ~r/\A[^@#\s]+\z/

  @doc "Builds a plan."
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(%{key: key, version: version} = opts) when is_binary(key) and is_binary(version) do
    hash8 = Map.get(opts, :hash8)

    cond do
      not (Regex.match?(@token, key) and Regex.match?(@token, version)) ->
        {:error, {:invalid, :key_or_version}}

      is_nil(hash8) or (is_binary(hash8) and Regex.match?(~r/\A[0-9a-f]{8}\z/, hash8)) ->
        {:ok, struct!(__MODULE__, %{key: key, version: version, hash8: hash8})}

      true ->
        {:error, {:invalid, :hash8}}
    end
  end

  def new(_), do: {:error, {:invalid, :plan}}

  @doc "Formats `key@version#hash8` from a SHA-256 hex digest, keeping its first 8 characters."
  @spec format(binary(), binary(), binary()) :: {:ok, binary()} | {:error, term()}
  def format(key, version, sha256_hex) when is_binary(sha256_hex) do
    with {:ok, plan} <- new(key: key, version: version, hash8: sha256_hex |> String.slice(0, 8) |> String.downcase()) do
      {:ok, format(plan)}
    end
  end

  @doc "Renders a plan; without a hash the `#` is omitted."
  @spec format(t()) :: binary()
  def format(%__MODULE__{key: key, version: version, hash8: nil}), do: key <> "@" <> version
  def format(%__MODULE__{key: key, version: version, hash8: hash8}), do: key <> "@" <> version <> "#" <> hash8

  @doc "Parses `key@version#hash8` or `key@version`."
  @spec parse(binary()) :: {:ok, t()} | {:error, term()}
  def parse(string) when is_binary(string) do
    with [key, rest] <- String.split(string, "@", parts: 2),
         [version | hash] <- String.split(rest, "#") do
      case hash do
        [] -> new(key: key, version: version)
        [hash8] -> new(key: key, version: version, hash8: hash8)
        _ -> {:error, :invalid_plan}
      end
    else
      _ -> {:error, :invalid_plan}
    end
  end

  @doc "Like `parse/1`, raising `ArgumentError` on an error."
  @spec parse!(binary()) :: t()
  def parse!(string) do
    case parse(string) do
      {:ok, plan} -> plan
      {:error, reason} -> raise ArgumentError, "invalid plan: #{inspect(reason)}"
    end
  end

  @doc "A plan from a `key@version` definition reference, with no hash."
  @spec from_definition_ref(binary()) :: {:ok, t()} | {:error, term()}
  def from_definition_ref(ref) when is_binary(ref) do
    if String.contains?(ref, "#"), do: {:error, :invalid_plan}, else: parse(ref)
  end
end
