defmodule AshProvenance.EntityRefTest do
  use ExUnit.Case, async: true

  alias AshProvenance.EntityRef

  @digest String.duplicate("0f", 32)

  test "builds with a keyed digest and names an address" do
    ref =
      EntityRef.new!(resource: "person", id: "p-1", version_number: 2, content_digest: %{scope: "s", digest: @digest})

    assert {:ok, a} = EntityRef.to_address(ref, base: "https://app.example.com/id", attribute: "email")
    assert AshProvenance.Address.to_iri(a) == "https://app.example.com/id/person/p-1#email"
  end

  test "a bare digest is refused" do
    assert {:error, :unkeyed_digest} = EntityRef.new(resource: "person", id: "p-1", content_digest: @digest)
  end

  test "a short or upper-case digest, or an empty scope, is refused" do
    assert {:error, _} = EntityRef.new(resource: "person", id: "p-1", content_digest: %{scope: "s", digest: "abcd"})

    assert {:error, _} =
             EntityRef.new(resource: "person", id: "p-1", content_digest: %{scope: "s", digest: String.upcase(@digest)})

    assert {:error, _} = EntityRef.new(resource: "person", id: "p-1", content_digest: %{scope: "", digest: @digest})
  end

  test "bad version and resource" do
    assert {:error, _} = EntityRef.new(resource: "person", id: "p-1", version_number: -1)
    assert {:error, _} = EntityRef.new(resource: "source", id: "p-1")
  end
end
