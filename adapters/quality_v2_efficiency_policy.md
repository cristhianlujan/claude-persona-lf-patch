# Adapter Efficiency Policy V2

The adapter layer is optimized for conditional prompt composition:

- applicable adapter: compact capsule + resolved task-specific binding data;
- non-applicable adapter: no prompt payload;
- authoring docs, full schemas, examples and judges stay outside ordinary prompt context;
- no independent model call for the adapter;
- telemetry should distinguish profile source size, adapter capsule size and model input/output tokens when the runtime exposes them.
