# NON_CANONICAL_ARTIFACT_SET_V1

Status: CANDIDATE / READ_ONLY

Purpose: allow one governed LF profile execution to compare one or more already-bound visual artifacts without registering, mutating, or promoting a canonical screen.

## Router boundary

The caller enters through `ACT-0001 -> PERFIL -> PROFILE_EXECUTION`. `NON_CANONICAL_ARTIFACT` is a Router-resolved subject mode, not an `asset_type` and must not be sent as one.

The route is eligible only when Input Governance resolves the request as:

- `status=ADVISORY_READ_ONLY`
- `decision=ADVISORY`
- `subject_mode=NON_CANONICAL_ARTIFACT`
- `continuation_allowed=true`
- `operation_must_equal=EJECUCION_PERFIL_LF`
- `read_only=true`
- `no_write=true`
- `no_promotion=true`
- `canonical_registration_required=false`
- `artifact_binding_required_before_profile_execution=true`

A canonical Input Governance receipt is forbidden in this mode. Canonical screen requests remain on the existing blocking Input Governance path.

## Artifact set contract

`NON_CANONICAL_ARTIFACT_SET_V1` contains 1..8 artifacts. Every item must bind:

- unique `artifact_ref`;
- unique SHA-256 image identity;
- positive `width_px` and `height_px` dimensions;
- the existing `Artifact` envelope. On a structural-cache miss, source-bound observations are required by the existing structural pipeline; source-bound image bytes remain optional and are used only by the existing targeted reread path.

Duplicate references or duplicate SHA-256 values fail closed. Multi-artifact full-image model transport is not authorized by this contract; `send_image_to_model` must remain false. The contract does not synthesize OCR or visual facts. Each artifact is prepared independently by the existing structural context pipeline and the resulting contexts are combined into one immutable artifact-set context before profile execution.

## Runtime route

The runtime endpoint is `POST /v1/profile/artifact-set-execute`. It executes exactly one governed profile against the combined artifact-set context and emits the normal profile execution provenance and semantic gates. The route never authorizes downstream writes by itself.

## Intended use

Example: compare two approved payment screens to identify `SHELL_LOCKED`, persistent navigation, and the variable `SCREEN_SLOT` while preserving both images as non-canonical evidence and without changing B2B canonical screen rules, fields, or states.

## Explicit non-actions

This contract does not:

- create or update a canonical screen;
- run canonical Curator/Validator as a prerequisite for visual comparison;
- permit writes, promotion, or production activation;
- weaken profile output validators or semantic quality gates;
- convert `NON_CANONICAL_ARTIFACT` into a Router asset type.
