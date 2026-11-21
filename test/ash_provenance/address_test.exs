defmodule AshProvenance.AddressTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AshProvenance.Address

  @base "https://app.example.com/id"

  test "renders the example IRIs" do
    a =
      Address.new!(base: @base, type: "credential", id: "3f6c1e0a-7b1d-4c55-9a7e-2f1d0c9b8a71", attribute: "expires_on")

    assert Address.to_iri(a) == "https://app.example.com/id/credential/3f6c1e0a-7b1d-4c55-9a7e-2f1d0c9b8a71#expires_on"

    m = Address.new!(base: @base, type: "membership", id: [{"team_id", "7"}, {"user_id", "12"}], attribute: "role")
    assert Address.to_iri(m) == "https://app.example.com/id/membership/team_id=7;user_id=12#role"
    assert {:ok, ^m} = Address.parse(Address.to_iri(m), base: @base)
  end

  test "as_of is shifted to UTC and rendered in the query" do
    {:ok, dt, _} = DateTime.from_iso8601("2026-01-02T03:04:05.250+01:00")
    a = Address.new!(base: @base, type: "t", id: "1", as_of: dt)
    assert Address.to_iri(a) == @base <> "/t/1?as_of=2026-01-02T02:04:05.250Z"
    assert {:ok, ^a} = Address.parse(Address.to_iri(a), base: @base)
  end

  test "special bytes are percent-encoded" do
    a = Address.new!(base: @base, type: "t", id: "a=b;c/d e")
    assert Address.to_iri(a) == @base <> "/t/a%3Db%3Bc%2Fd%20e"
  end

  describe "refusals" do
    test "reserved type" do
      assert {:error, {:reserved, :type}} = Address.new(base: @base, type: "source", id: "x")
    end

    test "bad type, empty ids" do
      assert {:error, _} = Address.new(base: @base, type: "Bad", id: "x")
      assert {:error, _} = Address.new(base: @base, type: "t", id: [])
      assert {:error, _} = Address.new(base: @base, type: "t", id: "")
    end

    test "trailing slash and other bad bases" do
      assert {:error, _} = Address.new(base: @base <> "/", type: "t", id: "x")
      assert {:error, _} = Address.new(base: "ftp://x.example.com", type: "t", id: "x")
      assert {:error, _} = Address.new(base: @base <> "?q=1", type: "t", id: "x")
    end

    test "parse refuses a different base" do
      assert {:error, :base_mismatch} = Address.parse("https://other.example.com/id/t/1", base: @base)
    end

    test "parse refuses a bad escape" do
      assert {:error, :bad_escape} = Address.parse(@base <> "/t/a%zz", base: @base)
      assert {:error, :bad_escape} = Address.parse(@base <> "/t/a%4", base: @base)
    end

    test "parse refuses an empty id, a reserved type, an offset" do
      assert {:error, _} = Address.parse(@base <> "/t/", base: @base)
      assert {:error, _} = Address.parse(@base <> "/source/x", base: @base)
      assert {:error, _} = Address.parse(@base <> "/t/1?as_of=2026-01-02T03:04:05%2B01:00", base: @base)
      assert {:error, _} = Address.parse(@base <> "/t/1?as_of=2026-01-02T03:04:05+01:00", base: @base)
      assert {:error, _} = Address.parse(@base <> "/t/1?other=1", base: @base)
    end

    test "trace ref with no colon or with the reserved type" do
      assert {:error, _} = Address.from_trace_ref("nocolon", base: @base)
      assert {:error, _} = Address.from_trace_ref("source:name", base: @base)
    end
  end

  test "trace refs" do
    a = Address.new!(base: @base, type: "audit_event", id: "a b", attribute: "x", as_of: ~U[2026-01-01 00:00:00Z])
    assert Address.to_trace_ref(a) == "audit_event:a%20b"

    assert {:ok, back} =
             Address.from_trace_ref("audit_event:a%20b", base: @base, attribute: "x", as_of: ~U[2026-01-01 00:00:00Z])

    assert back == a
  end

  defp text, do: StreamData.string(:printable, min_length: 1)

  defp weird do
    StreamData.string(Enum.concat([?a..?z, [?=, ?;, ?%, ?/, ??, ?#, ?\s, ?:, 0x00E9, 0x4E2D, 0x1F600]]), min_length: 1)
  end

  defp id_gen do
    StreamData.one_of([
      text(),
      weird(),
      StreamData.string(Enum.concat([?0..?9, ?a..?f, [?-]]), min_length: 36, max_length: 36),
      StreamData.list_of(StreamData.tuple({weird(), StreamData.one_of([weird(), StreamData.constant("")])}),
        min_length: 1,
        max_length: 4
      )
    ])
  end

  property "parse inverts to_iri" do
    check all(
            id <- id_gen(),
            attr <- StreamData.one_of([StreamData.constant(nil), weird()]),
            secs <- StreamData.one_of([StreamData.constant(nil), StreamData.integer(0..4_000_000_000)])
          ) do
      as_of = secs && DateTime.from_unix!(secs)
      a = Address.new!(base: @base, type: "thing", id: id, attribute: attr, as_of: as_of)
      assert {:ok, ^a} = Address.parse(Address.to_iri(a), base: @base)
    end
  end

  property "from_trace_ref inverts to_trace_ref" do
    check all(id <- id_gen()) do
      a = Address.new!(base: @base, type: "thing", id: id)
      assert {:ok, ^a} = Address.from_trace_ref(Address.to_trace_ref(a), base: @base)
    end
  end
end
