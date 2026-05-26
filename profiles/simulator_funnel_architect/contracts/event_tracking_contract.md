# Event Tracking Contract

## Purpose
Define the event plan for the simulator funnel.

## Required event fields
- `event_name`
- `funnel_step`
- `trigger`
- `payload_fields`
- `success_signal`
- `failure_signal`
- `privacy_note`
- `qa_check`

## Core events
- `home_simulator_cta_click`
- `simulator_started`
- `simulator_step_completed`
- `simulator_result_viewed`
- `lead_capture_started`
- `lead_capture_submitted`
- `fallback_lead_capture_triggered`
- `conversion_completed`

## Rules
Events must be observable, named consistently and connected to funnel decisions. Do not track sensitive data unless Legal/Data explicitly approves the field.

## Hard fail
Fail if an event lacks trigger, payload, success signal or QA check.

## Research basis
- Internal LF: ACT-0015 recommends tracking Home to Simulator to Result to Conversion.
- Own repo: schema and judge pattern from existing profile packs.
- Critical/risk: analytics integrity and privacy handoff.
- Adapted into: `contracts/event_tracking_contract.md`.
- Reason for location: event design belongs in its own reusable contract.
