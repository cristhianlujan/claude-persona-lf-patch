# LF Global Technical Inventory — Asset Composition Projection v1

This directory extends the existing `LF_GLOBAL_TECHNICAL_INVENTORY_V1` capability. It does **not** create a new inventory, registry, authority, or runtime.

## Boundary

Canonical ownership remains in the existing source systems:

- asset identity: `public.lf_activos`;
- Story Creator artifact state: `private.lf_skill_artifacts`;
- capability/profile/other asset composition: their already-governed registry, manifest or `lf_activos.metadata` source;
- repository objects: discovery snapshots only.

`inventory.*` remains a discovery/index/impact projection. A projected component or artifact never promotes, validates or changes the canonical source.

## Pattern

```text
canonical asset
  -> HAS_COMPONENT -> derived COMPONENT
  -> OWNS_ARTIFACT -> canonical artifact projection (when a canonical artifact registry exists)

COMPONENT
  -> COMPOSED_OF -> canonical artifact or physical/candidate object

canonical artifact
  -> MATERIALIZES_AS -> repo/db/edge physical object
```

The normalized projection envelope is `ASSET_COMPOSITION_V1`. Source-specific adapters may produce that envelope, but they may not infer undeclared components. The envelope must bind to a canonical source ref + SHA/version.

## Authority binding

A composition payload is accepted only when its authority can be verified from structured inventory metadata. The validator fails closed unless `authority.source_ref` is active, `source_of_truth=true`, and its `definition_sha256` and `source_version` exactly match the payload. A syntactically valid but stale SHA is therefore rejected.

Membership classes are also evidence-bound:

- `CANONICAL_ARTIFACT` requires an `artifact://` inventory object with `source_of_truth=true`;
- `CANDIDATE_OBJECT` must not use an `artifact://` ref and requires `source_of_truth=false`;
- reference-only legacy inventory rows may still be indexed for discovery, but cannot prove canonical authority or canonical/candidate classification.

## Scope semantics

- `COMPLETE_ASSET`: the payload declares the complete component set for the asset. `scope.component_codes` must be empty.
- `COMPONENT_SET`: the payload is intentionally partial and may touch only the exact component codes listed in `scope.component_codes`.

This prevents an incremental pilot from retiring unrelated components.

## Story Creator pilot

`story_creator_j02_asset_composition_v1.json` is a **projection fixture**, not authority. It binds to the current canonical `ART_MANIFEST` SHA/version and declares only `J02_SCREEN_DECOMPOSITION`.

The pilot intentionally preserves mixed canonicality:

- current `private.lf_skill_artifacts` rows are `CANONICAL_ARTIFACT` members;
- J02 v0.8/visual validators and fixtures that exist only as repository candidates remain `CANDIDATE_OBJECT` members;
- no candidate object is reclassified or promoted by the projection.

## Deterministic validator

`validate_asset_composition_v1.py` is read-only. It accepts a composition payload plus an inventory snapshot and emits the derived component/dependency plan. It fails closed on missing asset/source/member refs, duplicate components/members, scope drift, authority SHA/version drift, missing authority metadata, or canonical/candidate class mismatch.

The validator performs no network, Supabase or GitHub write.
