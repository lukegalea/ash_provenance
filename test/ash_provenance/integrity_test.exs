defmodule AshProvenance.IntegrityTest do
  use ExUnit.Case, async: true

  alias AshProvenance.Integrity

  @at ~U[2026-10-01 00:00:00Z]

  test "chain anchors take the four statuses" do
    for anchor <- [:audit_chain, :ledger_chain], status <- [:verified, :altered, :broken_link, :unchained] do
      assert {:ok, %Integrity{}} = Integrity.new(anchor: anchor, status: status, verified_at: @at)
    end
  end

  test "signature records take two" do
    assert {:ok, _} = Integrity.new(anchor: :signature_record, status: :altered, verified_at: @at)
    assert {:error, _} = Integrity.new(anchor: :signature_record, status: :unchained, verified_at: @at)
    assert {:error, _} = Integrity.new(anchor: :signature_record, status: :broken_link, verified_at: @at)
  end

  test "verified_at is required and anchors are closed" do
    assert {:error, _} = Integrity.new(anchor: :audit_chain, status: :verified)
    assert {:error, _} = Integrity.new(anchor: :audit_chain, status: :verified, verified_at: "now")
    assert {:error, _} = Integrity.new(anchor: :other, status: :verified, verified_at: @at)
  end
end
