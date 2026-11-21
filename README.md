# AshProvenance

A plain-data contract for explaining a value: an address for the value, PROV-DM steps that say where it came from,
typed gaps that say where the answer stops and why, and an export to PROV-O JSON-LD. It has no runtime dependencies,
no data layer and no processes.

## Parts

- `AshProvenance.Address`: `<base>/<type>/<id>[?as_of=<RFC 3339 UTC>][#<attribute>]`. Bytes outside the RFC 3986
  unreserved set are percent-encoded. A composite id renders `k1=v1;k2=v2`. `parse/2` inverts `to_iri/1`;
  `to_trace_ref/1` and `from_trace_ref/2` give the short `<type>:<id>` form.
- `AshProvenance.EntityRef`: a record version (resource, id, version number, instant) with an optional content digest
  keyed under an erasure scope.
- `AshProvenance.Plan`: `key@version#hash8`.
- `AshProvenance.Integrity`: the anchor, status and time of an integrity check on a step.
- `AshProvenance.Step`: one statement with a relation: `was_generated_by`, `was_derived_from`, `used`,
  `was_attributed_to`, `was_associated_with`, `acted_on_behalf_of`, `was_invalidated_by`, `was_revision_of` or
  `had_primary_source`.
- `AshProvenance.Gap`: where an answer stops: `unreadable`, `failed`, `erased`, `not_recorded` or `archived`.
- `AshProvenance.MatchedRules`: classifies a recorded decision evaluation as matched rules, no rule matched, or a gap.
- `AshProvenance.Explanation`: subject, steps, gaps and bounds (`max_depth`, `max_steps`, `depth`, `step_count`,
  `cut?`).
- `AshProvenance.Export.ProvO`: `to_jsonld/1` returns a JSON-LD map using the PROV-O qualified forms and an `ap:`
  namespace (`urn:ash-provenance:ns#`) for granularity, execution context, plan, summary, integrity, gaps and bounds.

Fixtures for five scenarios are in `test/fixtures/prov/`.

## Checks

    mix format --check-formatted
    mix compile --warnings-as-errors
    mix credo --strict
    mix test                        # UPDATE_FIXTURES=1 mix test rewrites the fixtures
    pip install "prov[rdf]" && python scripts/validate_prov.py
    scripts/check_xref.sh

## Licence

MIT. See `NOTICE` for the vocabularies used.
