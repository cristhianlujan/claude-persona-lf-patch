# Single-call Invariant

An LF adapter may alter context composition, validation and binding, but must not create a separate LLM reasoning round-trip. The specialist execution remains the only model call for the task unless another independently governed worker is subsequently selected by the orchestrator for a different operation.
