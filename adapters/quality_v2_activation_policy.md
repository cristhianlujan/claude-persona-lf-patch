# Adapter Activation Policy V2

The operational activation decision belongs to the canonical Router/orchestrator execution path. Profiles may declare dependency/applicability but must not self-dispatch adapters as independent workers.

Resolution order:
1. Router resolves target profile/operation.
2. Governed adapter bindings/applicability are resolved.
3. Only applicable compact capsules are attached to the same execution.
4. Execution receipt records each applied LF adapter exactly once.
5. Missing evidence for an applicable adapter prevents fully verified closure.

A user or profile naming an adapter directly does not create an operational adapter invocation by itself.
