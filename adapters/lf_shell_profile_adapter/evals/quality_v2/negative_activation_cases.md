# Shell Adapter Negative Activation Cases

The Shell adapter must not load for:

- text-only research or analysis with no LF screen/surface impact;
- backend/data work with no visual surface delta;
- profile maintenance that edits profile documentation only;
- an unbound profile whose request does not affect an LF screen;
- a standalone user request attempting to run the adapter as the primary worker.

For these cases the orchestrator either selects the appropriate worker without this capsule or returns routing guidance. The execution receipt must not claim a Shell adapter invocation.
