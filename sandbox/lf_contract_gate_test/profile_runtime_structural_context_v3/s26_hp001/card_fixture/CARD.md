# CARD — S26 CARD_BOUND Test Fixture

Status: TEST_FIXTURE_ONLY
Runtime: DISABLED_OUTSIDE_EXPLICIT_TEST_INJECTION
Automatic discovery: FORBIDDEN
Production authority: NONE

## Purpose

Exercise the S26 Gate C `CARD_BOUND` branch without granting product, business, legal, routing, deployment or production authority.

## Applicability

- surface_code: UI_SCREEN_DESIGN
- task_code: CREATE_NEW

## Required input fields

- profile_slug
- task_mode
- output_contract_version
- domain_scope

## Safety

This Card source fixture is valid only for sandbox validation. The test copies these exact bytes into an ephemeral repository under a `cards/` path and explicitly injects its exact ref and SHA into the real resolver. It must never be selected by automatic discovery or persisted under the governed `cards/` namespace.
