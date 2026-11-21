defmodule AshProvenance.Export.ProvOTest do
  use ExUnit.Case, async: true

  alias AshProvenance.{Address, Explanation, Fixtures, Gap, Integrity, Step}
  alias AshProvenance.Export.ProvO

  @fixture_dir Path.expand("../../fixtures/prov", __DIR__)

  defp graph(e), do: ProvO.to_jsonld(e)["@graph"]

  defp walk(term, fun) when is_map(term) do
    fun.(term)
    Enum.each(term, fn {_, v} -> walk(v, fun) end)
  end

  defp walk(term, fun) when is_list(term), do: Enum.each(term, &walk(&1, fun))
  defp walk(_, _), do: :ok

  defp collect_keys(term) do
    {:ok, agent} = Agent.start_link(fn -> [] end)
    walk(term, fn m -> Agent.update(agent, &(Map.keys(m) ++ &1)) end)
    keys = Agent.get(agent, & &1)
    Agent.stop(agent)
    keys
  end

  test "deterministic and context is inline" do
    e = Fixtures.decision()
    assert ProvO.to_jsonld(e) == ProvO.to_jsonld(e)
    ctx = ProvO.to_jsonld(e)["@context"]
    assert Map.keys(ctx) |> Enum.sort() == ["ap", "prov", "rdfs", "xsd"]
    assert ctx["ap"] == "urn:ash-provenance:ns#"
  end

  test "subject carries bounds" do
    [subject | _] = graph(Fixtures.composite_as_of_gaps())
    assert subject["@id"] =~ "membership/team_id=7;user_id=12?as_of=2026-09-30T00:00:00Z#role"

    assert subject["ap:bounds"] == %{
             "ap:maxDepth" => 1,
             "ap:maxSteps" => 50,
             "ap:depth" => 1,
             "ap:stepCount" => 1,
             "ap:cut" => true
           }
  end

  test "a masked value has no prov:value anywhere" do
    e = Fixtures.erased_masked_digest()
    keys = collect_keys(ProvO.to_jsonld(e))
    refute "prov:value" in keys
    assert "ap:masked" in keys
  end

  test "a later plain value cannot unmask an entity" do
    e = Fixtures.audited_attribute()

    masked =
      Step.new!(
        relation: :was_generated_by,
        entity: e.subject,
        activity: "audit_event:9",
        granularity: :value,
        value: :masked
      )

    plain =
      Step.new!(
        relation: :used,
        entity: e.subject,
        activity: "audit_event:9",
        granularity: :value,
        value: {:value, "x"}
      )

    steps = [masked, plain]
    ex = Explanation.new!(subject: e.subject, steps: steps, bounds: Fixtures.bounds(steps))
    refute "prov:value" in collect_keys(ProvO.to_jsonld(ex))
  end

  test "plain values export as prov:value" do
    keys = collect_keys(ProvO.to_jsonld(Fixtures.audited_attribute()))
    assert "prov:value" in keys
  end

  test "unchained integrity exports as unchained" do
    doc = ProvO.to_jsonld(Fixtures.impersonated_write())
    ints = for n <- doc["@graph"], i = n["ap:integrity"], do: i
    assert Enum.any?(ints, &(&1["ap:status"] == "unchained" and &1["ap:anchor"] == "ledger_chain"))
    assert Enum.any?(ints, &(&1["ap:anchor"] == "signature_record"))
  end

  test "execution_context nil and at nil are omitted" do
    subject = Address.new!(base: Fixtures.base(), type: "t", id: "1")
    step = Step.new!(relation: :used, entity: subject, activity: "audit_event:1", granularity: :value)
    ex = Explanation.new!(subject: subject, steps: [step], bounds: Fixtures.bounds([step]))
    keys = collect_keys(ProvO.to_jsonld(ex))
    refute "ap:executionContext" in keys
    refute "prov:atTime" in keys
  end

  test "an execution context and time are exported when present" do
    keys = collect_keys(ProvO.to_jsonld(Fixtures.audited_attribute()))
    assert "ap:executionContext" in keys
    assert "prov:atTime" in keys
  end

  test "an unreadable gap node has only kind and of" do
    gaps = for n <- graph(Fixtures.decision()), n["@type"] == "ap:Gap", n["ap:gapKind"] == "unreadable", do: n
    assert [node] = gaps
    assert node |> Map.keys() |> Enum.sort() == ["@id", "@type", "ap:gapKind", "ap:gapOf"]
  end

  test "an erased gap points at its receipt activity" do
    [gap] = for n <- graph(Fixtures.erased_masked_digest()), n["ap:gapKind"] == "erased", do: n
    assert gap["prov:wasInvalidatedBy"] == [%{"@id" => "https://app.example.com/id/shred_receipt/s-1"}]
  end

  test "agents are deduplicated by label" do
    agents = for n <- graph(Fixtures.impersonated_write()), n["@type"] == "prov:Agent", do: n["rdfs:label"]
    assert Enum.sort(agents) == ["operator", "subject user"]
  end

  test "association exports the plan" do
    nodes = graph(Fixtures.decision())

    assert Enum.any?(
             nodes,
             &(&1["@type"] == "prov:Plan" and &1["@id"] == "urn:ash-provenance:plan:pricing%403%23a1b2c3d4")
           )

    assert Enum.any?(nodes, &(&1["@type"] == "prov:Association" and Map.has_key?(&1, "prov:hadPlan")))
  end

  test "entity refs export version and a keyed digest" do
    node = Enum.find(graph(Fixtures.erased_masked_digest()), &Map.has_key?(&1, "ap:contentDigest"))
    assert node["ap:versionNumber"] == 3
    assert %{"ap:scope" => "scope-p-1", "ap:digest" => _} = node["ap:contentDigest"]
  end

  test "an erased gap alone and an unreadable built by hand export" do
    subject = Address.new!(base: Fixtures.base(), type: "t", id: "1")
    {:ok, gap} = Gap.unreadable(subject)
    ex = Explanation.new!(subject: subject, gaps: [gap], bounds: Fixtures.bounds([]))
    assert length(graph(ex)) == 2
    _ = Integrity
  end

  describe "fixtures" do
    test "match the committed files" do
      for {name, e} <- Fixtures.all() do
        path = Path.join(@fixture_dir, name <> ".jsonld")
        json = e |> ProvO.to_jsonld() |> sorted() |> Jason.encode!(pretty: true)

        if System.get_env("UPDATE_FIXTURES") == "1", do: File.write!(path, json <> "\n")
        assert File.read!(path) == json <> "\n", "#{name} differs; run UPDATE_FIXTURES=1 mix test"
      end
    end

    test "no unkeyed hex digests" do
      for path <- Path.wildcard(Path.join(@fixture_dir, "*.jsonld")) do
        doc = path |> File.read!() |> Jason.decode!()
        check_hex(doc, path)
      end
    end
  end

  defp check_hex(%{"ap:scope" => _} = digest_node, path) do
    Enum.each(Map.delete(digest_node, "ap:digest"), fn {_, v} -> check_hex(v, path) end)
  end

  defp check_hex(map, path) when is_map(map), do: Enum.each(map, fn {_, v} -> check_hex(v, path) end)
  defp check_hex(list, path) when is_list(list), do: Enum.each(list, &check_hex(&1, path))

  defp check_hex(str, path) when is_binary(str) do
    refute Regex.match?(~r/[0-9a-f]{32,}/, str), "#{path}: unkeyed hex string #{str}"
  end

  defp check_hex(_, _), do: :ok

  defp sorted(map) when is_map(map),
    do: map |> Enum.sort() |> Enum.map(fn {k, v} -> {k, sorted(v)} end) |> Jason.OrderedObject.new()

  defp sorted(list) when is_list(list), do: Enum.map(list, &sorted/1)
  defp sorted(other), do: other
end
