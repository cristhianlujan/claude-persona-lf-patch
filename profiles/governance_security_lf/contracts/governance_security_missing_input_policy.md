# Governance Security Missing Input Policy

Status: CANDIDATE_READ_ONLY

## Rule
Do not guess operational authority. If an input is missing, classify whether it can be resolved from Supabase/GitHub readback or whether protocol requires a user decision.

## Resolve Internally
Resolve from official sources when missing input is: asset state, canonical path, runtime flag, impact flag, current repository content, current manifest, or readback existence.

## User Decision Required
Ask only if the protocol requires explicit user choice or if multiple official assets conflict and no source outranks the other.

## Block
Block when the assistant would need to invent scope, state, actor, destination, approval, or protocol step.
