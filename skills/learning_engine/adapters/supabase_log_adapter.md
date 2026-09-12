# Supabase Log Adapter — LF Learning Engine

## Purpose

Define how an approved learning event may be logged in Supabase after explicit approval.

## Rules

- Read from Supabase is allowed for source verification.
- Writes to Supabase are blocked unless explicitly approved.
- Any approved write must include operation id, source authority, actor, timestamp, target asset, status, and no-impact or impact statement.
- Never update ACT-0046 state from this pack.
- Never treat a log write as approval of the learning candidate.

## Blockers

- Missing explicit approval.
- Missing source authority.
- Missing target asset.
- Runtime enablement request.
- Production general enablement request.
