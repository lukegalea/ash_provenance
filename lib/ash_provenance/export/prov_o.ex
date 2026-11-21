defmodule AshProvenance.Export.ProvO do
  @moduledoc """
  Exports an `AshProvenance.Explanation` as a PROV-O JSON-LD document (a plain map with string keys).

  Each step becomes the unqualified PROV-O triple plus the qualified form (`prov:qualifiedGeneration` and so on), whose
  blank node carries `prov:atTime`, the plan and the `ap:` fields (`urn:ash-provenance:ns#`): `ap:granularity`,
  `ap:executionContext` (absent when not recorded), `ap:plan`, `ap:summary` and `ap:integrity`.

  A `:masked` value is exported as `ap:masked: true` and never as `prov:value`. An `:unreadable` gap exports only its
  kind and `ap:gapOf`. The output is deterministic: nodes appear in first-use order and qualified nodes are blank nodes numbered in that
  order; agents and gaps have URN identifiers, because PROV tooling requires every element to be named. The caller encodes the map to JSON.
  """

  alias AshProvenance.{Address, EntityRef, Explanation, Gap, Integrity, Plan, Step}

  @context %{
    "prov" => "http://www.w3.org/ns/prov#",
    "rdfs" => "http://www.w3.org/2000/01/rdf-schema#",
    "xsd" => "http://www.w3.org/2001/XMLSchema#",
    "ap" => "urn:ash-provenance:ns#"
  }

  # relation => {unqualified property, qualified property, qualified class}
  @relations %{
    was_generated_by: {"prov:wasGeneratedBy", "prov:qualifiedGeneration", "prov:Generation"},
    used: {"prov:used", "prov:qualifiedUsage", "prov:Usage"},
    was_derived_from: {"prov:wasDerivedFrom", "prov:qualifiedDerivation", "prov:Derivation"},
    was_revision_of: {"prov:wasRevisionOf", "prov:qualifiedRevision", "prov:Revision"},
    had_primary_source: {"prov:hadPrimarySource", "prov:qualifiedPrimarySource", "prov:PrimarySource"},
    was_attributed_to: {"prov:wasAttributedTo", "prov:qualifiedAttribution", "prov:Attribution"},
    was_associated_with: {"prov:wasAssociatedWith", "prov:qualifiedAssociation", "prov:Association"},
    acted_on_behalf_of: {"prov:actedOnBehalfOf", "prov:qualifiedDelegation", "prov:Delegation"},
    was_invalidated_by: {"prov:wasInvalidatedBy", "prov:qualifiedInvalidation", "prov:Invalidation"}
  }

  @doc "Returns the JSON-LD document for the explanation."
  @spec to_jsonld(Explanation.t()) :: map()
  def to_jsonld(%Explanation{} = explanation) do
    base = explanation.subject.base
    subject_id = Address.to_iri(explanation.subject)

    acc =
      %{base: base, order: [], nodes: %{}, blank: 0, gaps: 0, agents: %{}}
      |> add_node(subject_id, "prov:Entity")
      |> put_one(subject_id, "ap:bounds", bounds(explanation.bounds))

    acc = Enum.reduce(explanation.steps, acc, &add_step/2)
    acc = Enum.reduce(explanation.gaps, acc, &add_gap/2)

    %{"@context" => @context, "@graph" => Enum.map(Enum.reverse(acc.order), &Map.fetch!(acc.nodes, &1))}
  end

  defp bounds(b) do
    %{
      "ap:maxDepth" => b.max_depth,
      "ap:maxSteps" => b.max_steps,
      "ap:depth" => b.depth,
      "ap:stepCount" => b.step_count,
      "ap:cut" => b.cut?
    }
  end

  # steps

  defp add_step(%Step{relation: :acted_on_behalf_of} = step, acc) do
    {delegate, acc} = agent(acc, step.agent_label)
    {responsible, acc} = agent(acc, step.on_behalf_of)
    {activity, acc} = activity(acc, step.activity)

    {unq, qual, class} = Map.fetch!(@relations, :acted_on_behalf_of)

    qualified = [{"prov:agent", ref(responsible)} | optional("prov:hadActivity", activity && ref(activity))]

    acc
    |> put_many(delegate, unq, ref(responsible))
    |> qualify(delegate, qual, class, qualified, step)
  end

  defp add_step(%Step{relation: relation} = step, acc) do
    {unq, qual, class} = Map.fetch!(@relations, relation)
    {entity, acc} = entity(acc, step.entity)
    {activity, acc} = activity(acc, step.activity)
    {antecedent, acc} = entity(acc, step.antecedent)
    {agent, acc} = agent_for(acc, step.agent_label)
    {plan, acc} = plan(acc, relation, step.plan)

    {holder, target, extra} =
      case relation do
        :was_generated_by ->
          {entity, activity, [{"prov:activity", ref(activity)}]}

        :was_invalidated_by ->
          {entity, activity, [{"prov:activity", ref(activity)}]}

        :used ->
          {activity, entity, [{"prov:entity", ref(entity)}]}

        :was_attributed_to ->
          {entity, agent, [{"prov:agent", ref(agent)}]}

        :was_associated_with ->
          {activity, agent, [{"prov:agent", ref(agent)}] ++ optional("prov:hadPlan", plan && ref(plan))}

        _derivation ->
          {entity, antecedent,
           [{"prov:entity", ref(antecedent)}] ++ optional("prov:hadActivity", activity && ref(activity))}
      end

    acc
    |> put_many(holder, unq, ref(target))
    |> qualify(holder, qual, class, extra, step)
    |> put_value(entity, step.value)
  end

  defp qualify(acc, holder, qual, class, props, %Step{} = step) do
    {id, acc} = blank(acc)

    props =
      props ++
        optional("prov:atTime", step.at && datetime(step.at)) ++
        [{"ap:granularity", Atom.to_string(step.granularity)}] ++
        optional("ap:executionContext", step.execution_context && Atom.to_string(step.execution_context)) ++
        optional("ap:plan", step.plan && Plan.format(step.plan)) ++
        optional("ap:summary", step.summary) ++
        optional("ap:integrity", step.integrity && integrity(step.integrity))

    acc
    |> add_node(id, class)
    |> then(fn acc -> Enum.reduce(props, acc, fn {k, v}, a -> put_one(a, id, k, v) end) end)
    |> put_many(holder, qual, ref(id))
  end

  defp integrity(%Integrity{anchor: anchor, status: status, verified_at: at}) do
    %{
      "ap:anchor" => Atom.to_string(anchor),
      "ap:status" => Atom.to_string(status),
      "ap:verifiedAt" => datetime(at)
    }
  end

  defp put_value(acc, nil, _), do: acc
  defp put_value(acc, _entity, nil), do: acc

  defp put_value(acc, entity, :masked),
    do: acc |> update_node(entity, &(&1 |> Map.delete("prov:value") |> Map.put("ap:masked", true)))

  defp put_value(acc, entity, {:value, v}) do
    update_node(acc, entity, fn node ->
      if Map.has_key?(node, "ap:masked"), do: node, else: Map.put(node, "prov:value", v)
    end)
  end

  # gaps

  defp add_gap(%Gap{} = gap, acc) do
    id = "urn:ash-provenance:gap:#{acc.gaps}"
    acc = add_node(%{acc | gaps: acc.gaps + 1}, id, "ap:Gap")
    acc = put_one(acc, id, "ap:gapKind", Atom.to_string(gap.kind))
    acc = if gap.of, do: put_one(acc, id, "ap:gapOf", ref(Address.to_iri(gap.of))), else: acc
    acc = if gap.summary, do: put_one(acc, id, "ap:summary", gap.summary), else: acc
    acc = if gap.at, do: put_one(acc, id, "ap:at", datetime(gap.at)), else: acc

    case gap.receipt do
      nil ->
        acc

      receipt ->
        {activity, acc} = activity(acc, receipt)
        put_many(acc, id, "prov:wasInvalidatedBy", ref(activity))
    end
  end

  # nodes

  defp entity(acc, nil), do: {nil, acc}

  defp entity(acc, %Address{} = address) do
    id = Address.to_iri(address)
    {id, add_node(acc, id, "prov:Entity")}
  end

  defp entity(acc, %EntityRef{} = ref) do
    {:ok, address} = EntityRef.to_address(ref, base: acc.base)
    id = Address.to_iri(address)

    acc =
      acc
      |> add_node(id, "prov:Entity")
      |> then(fn a -> if ref.version_number, do: put_one(a, id, "ap:versionNumber", ref.version_number), else: a end)
      |> then(fn a ->
        case ref.content_digest do
          nil ->
            a

          %{scope: scope, digest: digest} ->
            put_one(a, id, "ap:contentDigest", %{"ap:scope" => scope, "ap:digest" => digest})
        end
      end)

    {id, acc}
  end

  defp activity(acc, nil), do: {nil, acc}

  defp activity(acc, trace_ref) do
    {:ok, type, encoded} = Address.split_trace_ref(trace_ref)
    id = acc.base <> "/" <> type <> "/" <> encoded
    {id, add_node(acc, id, "prov:Activity")}
  end

  defp agent_for(acc, nil), do: {nil, acc}
  defp agent_for(acc, label), do: agent(acc, label)

  defp agent(acc, label) do
    case acc.agents do
      %{^label => id} ->
        {id, acc}

      _ ->
        id = "urn:ash-provenance:agent:" <> Address.encode(label)
        acc = %{add_node(acc, id, "prov:Agent") | agents: Map.put(acc.agents, label, id)}
        {id, put_one(acc, id, "rdfs:label", label)}
    end
  end

  defp plan(acc, :was_associated_with, %Plan{} = plan) do
    id = "urn:ash-provenance:plan:" <> Address.encode(Plan.format(plan))
    {id, add_node(acc, id, "prov:Plan")}
  end

  defp plan(acc, _, _), do: {nil, acc}

  defp blank(acc), do: {"_:b#{acc.blank}", %{acc | blank: acc.blank + 1}}

  defp add_node(acc, id, type) do
    case acc.nodes do
      %{^id => _} -> acc
      nodes -> %{acc | order: [id | acc.order], nodes: Map.put(nodes, id, %{"@id" => id, "@type" => type})}
    end
  end

  defp update_node(acc, id, fun), do: %{acc | nodes: Map.update!(acc.nodes, id, fun)}
  defp put_one(acc, id, key, value), do: update_node(acc, id, &Map.put(&1, key, value))

  defp put_many(acc, id, key, value) do
    update_node(acc, id, &Map.update(&1, key, [value], fn existing -> append_new(existing, value) end))
  end

  defp append_new(existing, value), do: if(value in existing, do: existing, else: existing ++ [value])

  defp ref(id), do: %{"@id" => id}
  defp optional(_key, nil), do: []
  defp optional(key, value), do: [{key, value}]

  defp datetime(%DateTime{} = dt),
    do: %{"@value" => dt |> Address.to_utc() |> DateTime.to_iso8601(), "@type" => "xsd:dateTime"}
end
