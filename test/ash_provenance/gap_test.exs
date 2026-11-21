defmodule AshProvenance.GapTest do
  use ExUnit.Case, async: true

  alias AshProvenance.{Address, Gap}

  @of Address.new!(base: "https://app.example.com/id", type: "t", id: "1")

  test "all five kinds build" do
    for kind <- [:unreadable, :failed, :erased, :not_recorded, :archived],
        do: assert({:ok, %Gap{}} = Gap.new(kind: kind, of: @of))

    assert {:error, _} = Gap.new(kind: :other)
  end

  test "unreadable carries only kind and of" do
    assert {:ok, %Gap{kind: :unreadable, of: @of}} = Gap.unreadable(@of)
    assert {:error, {:not_allowed, :summary}} = Gap.new(kind: :unreadable, of: @of, summary: "x")
    assert {:error, {:not_allowed, :receipt}} = Gap.new(kind: :unreadable, of: @of, receipt: "shred:1")
    assert {:error, {:not_allowed, :at}} = Gap.new(kind: :unreadable, of: @of, at: ~U[2026-01-01 00:00:00Z])
  end

  test "receipt only on erased" do
    assert {:ok, _} = Gap.new(kind: :erased, of: @of, receipt: "shred_receipt:1")
    assert {:error, {:not_allowed, :receipt}} = Gap.new(kind: :failed, of: @of, receipt: "shred_receipt:1")
    assert {:error, {:invalid, :receipt}} = Gap.new(kind: :erased, receipt: "nocolon")
  end

  test "summary is at most 280 bytes" do
    assert {:error, {:invalid, :summary}} = Gap.new(kind: :failed, summary: String.duplicate("a", 281))
  end
end
