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

This Card is valid only when a test explicitly injects its exact ref and SHA. It must never be selected by automatic discovery outside S26 validation.
