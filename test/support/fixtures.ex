defmodule AshProvenance.Fixtures do
  @moduledoc false
  # Five invented scenarios used for the committed PROV-O fixtures. Ids are placeholders.

  alias AshProvenance.{Address, EntityRef, Explanation, Gap, Integrity, Plan, Step}

  @base "https://app.example.com/id"

  def base, do: @base

  def all do
    [
      {"audited_attribute", audited_attribute()},
      {"decision", decision()},
      {"impersonated_write", impersonated_write()},
      {"erased_masked_digest", erased_masked_digest()},
      {"composite_as_of_gaps", composite_as_of_gaps()}
    ]
  end

  def bounds(steps, overrides \\ %{}) do
    Map.merge(%{max_depth: 4, max_steps: 50, depth: 1, step_count: length(steps), cut?: false}, overrides)
  end

  def audited_attribute do
    subject = addr("credential", "3f6c1e0a-7b1d-4c55-9a7e-2f1d0c9b8a71", "expires_on")

    steps = [
      Step.new!(
        relation: :was_generated_by,
        entity: subject,
        activity: "audit_event:0001",
        at: ~U[2026-10-01 12:00:00Z],
        execution_context: :request,
        granularity: :value,
        value: {:value, "2027-10-01"},
        summary: "expires_on set by renew",
        integrity: Integrity.new!(anchor: :audit_chain, status: :verified, verified_at: ~U[2026-10-02 00:00:00Z])
      ),
      Step.new!(
        relation: :was_attributed_to,
        entity: subject,
        agent_label: "Dana Placeholder",
        at: ~U[2026-10-01 12:00:00Z],
        granularity: :value
      )
    ]

    Explanation.new!(subject: subject, steps: steps, gaps: [], bounds: bounds(steps))
  end

  def decision do
    subject = addr("quote", "q-100", "tier")
    input = addr("account", "a-7", "region")
    plan = Plan.parse!("pricing@3#a1b2c3d4")

    steps = [
      Step.new!(
        relation: :was_generated_by,
        entity: subject,
        activity: "decision_run:run-1",
        plan: plan,
        at: ~U[2026-10-05 08:30:00Z],
        execution_context: :job,
        granularity: :value,
        value: {:value, "gold"}
      ),
      Step.new!(
        relation: :was_derived_from,
        entity: subject,
        antecedent: input,
        activity: "decision_run:run-1",
        granularity: :value,
        value: nil
      ),
      Step.new!(
        relation: :was_associated_with,
        activity: "decision_run:run-1",
        agent_label: "pricing rules",
        plan: plan,
        granularity: :record
      )
    ]

    gaps = [
      Gap.unreadable(input) |> elem(1),
      Gap.new!(kind: :failed, of: addr("account", "a-8", "region"), summary: "evaluation raised an error")
    ]

    Explanation.new!(subject: subject, steps: steps, gaps: gaps, bounds: bounds(steps, %{depth: 2}))
  end

  def impersonated_write do
    subject = addr("note", "n-1", "body")

    steps = [
      Step.new!(
        relation: :was_associated_with,
        activity: "audit_event:0002",
        agent_label: "operator",
        at: ~U[2026-10-06 09:00:00Z],
        execution_context: :impersonation,
        granularity: :record,
        integrity: Integrity.new!(anchor: :signature_record, status: :verified, verified_at: ~U[2026-10-07 00:00:00Z])
      ),
      Step.new!(
        relation: :acted_on_behalf_of,
        agent_label: "operator",
        on_behalf_of: "subject user",
        activity: "audit_event:0002",
        granularity: :record,
        integrity: Integrity.new!(anchor: :ledger_chain, status: :unchained, verified_at: ~U[2026-10-07 00:00:00Z])
      ),
      Step.new!(
        relation: :was_generated_by,
        entity: subject,
        activity: "recipe_run:r-9",
        granularity: :value,
        integrity: Integrity.new!(anchor: :signature_record, status: :altered, verified_at: ~U[2026-10-07 00:00:00Z])
      )
    ]

    Explanation.new!(subject: subject, steps: steps, gaps: [], bounds: bounds(steps))
  end

  def erased_masked_digest do
    subject = addr("person", "p-1", "email")

    ref =
      EntityRef.new!(
        resource: "person",
        id: "p-1",
        version_number: 3,
        content_digest: %{scope: "scope-p-1", digest: String.duplicate("ab", 32)}
      )

    steps = [
      Step.new!(relation: :was_derived_from, entity: subject, antecedent: ref, granularity: :value, value: :masked),
      Step.new!(relation: :was_invalidated_by, entity: ref, activity: "shred_receipt:s-1", granularity: :record)
    ]

    gaps = [Gap.new!(kind: :erased, of: subject, receipt: "shred_receipt:s-1", summary: "subject erased")]
    Explanation.new!(subject: subject, steps: steps, gaps: gaps, bounds: bounds(steps))
  end

  def composite_as_of_gaps do
    subject =
      Address.new!(
        base: @base,
        type: "membership",
        id: [{"team_id", "7"}, {"user_id", "12"}],
        attribute: "role",
        as_of: ~U[2026-09-30 00:00:00Z]
      )

    steps = [
      Step.new!(
        relation: :was_generated_by,
        entity: subject,
        activity: "audit_event:0003",
        granularity: :value,
        value: {:value, "admin"}
      )
    ]

    gaps = [
      Gap.new!(kind: :archived, of: subject, summary: "older versions archived"),
      Gap.new!(kind: :not_recorded, of: subject)
    ]

    Explanation.new!(subject: subject, steps: steps, gaps: gaps, bounds: bounds(steps, %{cut?: true, max_depth: 1}))
  end

  defp addr(type, id, attribute), do: Address.new!(base: @base, type: type, id: id, attribute: attribute)
end
