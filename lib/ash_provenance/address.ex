defmodule AshProvenance.Address do
  @moduledoc """
  The address of a value: `<base>/<type>/<id>[?as_of=<RFC 3339 UTC>][#<attribute>]`.

  `base` is an absolute http(s) URI with no trailing slash, query or fragment. `type` is a token
  matching `^[a-z][a-z0-9_]*$`; `"source"` is reserved for sources that are not records. `id` is a binary or a
  non-empty list of `{key, value}` string pairs (a composite key, in the caller's order).

  Every byte outside the RFC 3986 unreserved set is percent-encoded with upper-case hex. A composite id renders as
  `k1=v1;k2=v2`, each key and value encoded separately, so a binary id is never ambiguous with a composite one.
  """

  @enforce_keys [:base, :type, :id]
  defstruct [:base, :type, :id, :attribute, :as_of]

  @type id :: binary() | [{binary(), binary()}, ...]
  @type t :: %__MODULE__{
          base: binary(),
          type: binary(),
          id: id(),
          attribute: binary() | nil,
          as_of: DateTime.t() | nil
        }

  @type error :: {:error, term()}

  @type_regex ~r/\A[a-z][a-z0-9_]*\z/
  @reserved_type "source"

  @doc "Builds an address from `base`, `type`, `id` and optional `attribute` and `as_of`."
  @spec new(keyword() | map()) :: {:ok, t()} | error()
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(%{} = opts) do
    with {:ok, base} <- validate_base(Map.get(opts, :base)),
         {:ok, type} <- validate_type(Map.get(opts, :type)),
         {:ok, id} <- validate_id(Map.get(opts, :id)),
         {:ok, attribute} <- validate_attribute(Map.get(opts, :attribute)),
         {:ok, as_of} <- validate_as_of(Map.get(opts, :as_of)) do
      {:ok, %__MODULE__{base: base, type: type, id: id, attribute: attribute, as_of: as_of}}
    end
  end

  @doc "Like `new/1`, raising `ArgumentError` on an error."
  @spec new!(keyword() | map()) :: t()
  def new!(opts), do: bang(new(opts))

  @doc "Renders the IRI."
  @spec to_iri(t()) :: binary()
  def to_iri(%__MODULE__{} = a) do
    a.base <> "/" <> a.type <> "/" <> encode_id(a.id) <> as_of_query(a.as_of) <> attribute_fragment(a.attribute)
  end

  @doc "Parses an IRI produced by `to_iri/1`. Requires `base: base`."
  @spec parse(binary(), keyword()) :: {:ok, t()} | error()
  def parse(iri, opts) when is_binary(iri) do
    base = Keyword.fetch!(opts, :base)
    prefix = base <> "/"

    with {:ok, base} <- validate_base(base),
         true <- String.starts_with?(iri, prefix) || {:error, :base_mismatch},
         rest = binary_part(iri, byte_size(prefix), byte_size(iri) - byte_size(prefix)),
         {path_query, fragment} = split_first(rest, "#"),
         {path, query} = split_first(path_query, "?"),
         {:ok, [type, encoded_id]} <- split_path(path),
         {:ok, id} <- decode_id(encoded_id),
         {:ok, as_of} <- parse_query(query),
         {:ok, attribute} <- decode_fragment(fragment) do
      new(base: base, type: type, id: id, attribute: attribute, as_of: as_of)
    end
  end

  def parse(_, _), do: {:error, :not_a_binary}

  @doc "The trace reference `<type>:<encoded id>` (no base, attribute or as_of)."
  @spec to_trace_ref(t()) :: binary()
  def to_trace_ref(%__MODULE__{type: type, id: id}), do: type <> ":" <> encode_id(id)

  @doc "Inverse of `to_trace_ref/1`. Takes `base:` and optionally `attribute:` and `as_of:`."
  @spec from_trace_ref(binary(), keyword()) :: {:ok, t()} | error()
  def from_trace_ref(ref, opts) when is_binary(ref) do
    with {:ok, type, encoded} <- split_trace_ref(ref),
         {:ok, id} <- decode_id(encoded) do
      new(
        base: Keyword.fetch!(opts, :base),
        type: type,
        id: id,
        attribute: Keyword.get(opts, :attribute),
        as_of: Keyword.get(opts, :as_of)
      )
    end
  end

  def from_trace_ref(_, _), do: {:error, :not_a_binary}

  @doc false
  @spec split_trace_ref(binary()) :: {:ok, binary(), binary()} | error()
  def split_trace_ref(ref) do
    case String.split(ref, ":", parts: 2) do
      [type, encoded] when encoded != "" ->
        if Regex.match?(@type_regex, type), do: {:ok, type, encoded}, else: {:error, {:invalid, :type}}

      _ ->
        {:error, :invalid_trace_ref}
    end
  end

  @doc false
  @spec valid_type?(term()) :: boolean()
  def valid_type?(type), do: is_binary(type) and type != @reserved_type and Regex.match?(@type_regex, type)

  @doc false
  @spec validate_type(term()) :: {:ok, binary()} | error()
  def validate_type(@reserved_type), do: {:error, {:reserved, :type}}

  def validate_type(type) when is_binary(type) do
    if Regex.match?(@type_regex, type), do: {:ok, type}, else: {:error, {:invalid, :type}}
  end

  def validate_type(_), do: {:error, {:invalid, :type}}

  @doc false
  @spec validate_id(term()) :: {:ok, id()} | error()
  def validate_id(id) when is_binary(id) and id != "" do
    if String.valid?(id), do: {:ok, id}, else: {:error, {:invalid, :id}}
  end

  def validate_id([_ | _] = pairs) do
    if Enum.all?(pairs, &valid_pair?/1), do: {:ok, pairs}, else: {:error, {:invalid, :id}}
  end

  def validate_id(_), do: {:error, {:invalid, :id}}

  @doc false
  @spec validate_as_of(term()) :: {:ok, DateTime.t() | nil} | error()
  def validate_as_of(nil), do: {:ok, nil}
  def validate_as_of(%DateTime{} = dt), do: {:ok, to_utc(dt)}
  def validate_as_of(_), do: {:error, {:invalid, :as_of}}

  @doc false
  @spec to_utc(DateTime.t()) :: DateTime.t()
  def to_utc(%DateTime{utc_offset: 0, std_offset: 0, time_zone: "Etc/UTC"} = dt), do: dt

  def to_utc(%DateTime{} = dt) do
    dt
    |> DateTime.to_naive()
    |> NaiveDateTime.add(-(dt.utc_offset + dt.std_offset), :second)
    |> DateTime.from_naive!("Etc/UTC")
  end

  @doc false
  @spec encode_id(id()) :: binary()
  def encode_id(id) when is_binary(id), do: encode(id)

  def encode_id(pairs) when is_list(pairs),
    do: Enum.map_join(pairs, ";", fn {k, v} -> encode(k) <> "=" <> encode(v) end)

  @doc false
  @spec decode_id(binary()) :: {:ok, id()} | error()
  def decode_id(""), do: {:error, :empty_id}

  def decode_id(encoded) do
    if String.contains?(encoded, "=") do
      encoded |> String.split(";") |> Enum.reduce_while({:ok, []}, &decode_pair/2) |> reverse_ok()
    else
      with {:ok, id} <- decode(encoded), do: validate_id(id)
    end
  end

  @doc false
  @spec encode(binary()) :: binary()
  def encode(bin) when is_binary(bin), do: for(<<b <- bin>>, into: "", do: encode_byte(b))

  @doc false
  @spec decode(binary()) :: {:ok, binary()} | error()
  def decode(bin), do: decode(bin, [])

  defp decode(<<>>, acc), do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}

  defp decode(<<?%, h1, h2, rest::binary>>, acc) do
    case Integer.parse(<<h1, h2>>, 16) do
      {n, ""} when h1 != ?+ and h1 != ?- -> decode(rest, [n | acc])
      _ -> {:error, :bad_escape}
    end
  end

  defp decode(<<?%, _::binary>>, _), do: {:error, :bad_escape}
  defp decode(<<b, rest::binary>>, acc), do: decode(rest, [b | acc])

  defp decode_pair(part, {:ok, acc}) do
    with [k, v] <- String.split(part, "=", parts: 2),
         {:ok, k} when k != "" <- decode(k),
         {:ok, v} <- decode(v) do
      {:cont, {:ok, [{k, v} | acc]}}
    else
      _ -> {:halt, {:error, {:invalid, :id}}}
    end
  end

  defp reverse_ok({:ok, pairs}), do: validate_id(Enum.reverse(pairs))
  defp reverse_ok(error), do: error

  defp encode_byte(b) when b in ?A..?Z or b in ?a..?z or b in ?0..?9 or b in [?-, ?., ?_, ?~], do: <<b>>
  defp encode_byte(b), do: "%" <> Base.encode16(<<b>>)

  defp valid_pair?({k, v}), do: is_binary(k) and k != "" and is_binary(v) and String.valid?(k) and String.valid?(v)
  defp valid_pair?(_), do: false

  defp validate_base(base) when is_binary(base) do
    case URI.parse(base) do
      %URI{scheme: scheme, host: host, query: nil, fragment: nil}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        if String.ends_with?(base, "/") or String.contains?(base, ["?", "#", " "]),
          do: {:error, {:invalid, :base}},
          else: {:ok, base}

      _ ->
        {:error, {:invalid, :base}}
    end
  end

  defp validate_base(_), do: {:error, {:invalid, :base}}

  defp validate_attribute(nil), do: {:ok, nil}

  defp validate_attribute(attr) when is_binary(attr) and attr != "" do
    if String.valid?(attr), do: {:ok, attr}, else: {:error, {:invalid, :attribute}}
  end

  defp validate_attribute(_), do: {:error, {:invalid, :attribute}}

  defp as_of_query(nil), do: ""
  defp as_of_query(%DateTime{} = dt), do: "?as_of=" <> DateTime.to_iso8601(dt)

  defp attribute_fragment(nil), do: ""
  defp attribute_fragment(attr), do: "#" <> encode(attr)

  defp split_first(bin, sep) do
    case String.split(bin, sep, parts: 2) do
      [a, b] -> {a, b}
      [a] -> {a, nil}
    end
  end

  defp split_path(path) do
    case String.split(path, "/") do
      [_type, _id] = parts -> {:ok, parts}
      _ -> {:error, :invalid_path}
    end
  end

  defp parse_query(nil), do: {:ok, nil}

  defp parse_query("as_of=" <> ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, 0} -> if String.ends_with?(ts, "Z"), do: {:ok, dt}, else: {:error, {:invalid, :as_of}}
      _ -> {:error, {:invalid, :as_of}}
    end
  end

  defp parse_query(_), do: {:error, {:invalid, :query}}

  defp decode_fragment(nil), do: {:ok, nil}
  defp decode_fragment(""), do: {:error, {:invalid, :attribute}}
  defp decode_fragment(fragment), do: decode(fragment)

  defp bang({:ok, value}), do: value
  defp bang({:error, reason}), do: raise(ArgumentError, "invalid: #{inspect(reason)}")
end
