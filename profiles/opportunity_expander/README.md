# Opportunity Expander LF — Candidate Pack

Governed S37-WP01 candidate profile for expanding the solution space around an already-authorized LF task.

The profile is advisory and read-only. It preserves the baseline, separates in-scope improvements from scope-changing opportunities, and explores five lanes: CORE, ADJACENT, BUSINESS, DATA and FRONTIER.

It does not search freely for Cards or domain capabilities. When additional governed context is required it returns `NEEDS_CAPABILITY_CONTEXT` with typed `capability_requests`; Router/Orchestrator is responsible for resolving and materializing the requested capability before a second pass.

This pack is candidate-only. It does not authorize runtime, production, Golden, scheduler, canonical business writes or automatic scope expansion.
