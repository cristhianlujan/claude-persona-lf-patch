# Adapter Behavioral Evidence Boundary

A deterministic fixture, schema check, validator run, example or judge simulation proves contract behavior only. It does not prove that a live LF profile execution actually resolved or applied an adapter.

A behavioral claim that an adapter was applied requires all of the following:

- canonical Router/profile execution identity;
- exact adapter code and version;
- exact adapter source hash and runtime capsule hash;
- activation reason derived from governed binding/applicability;
- `lf_adapter_invocations` evidence in the execution receipt;
- profile raw output bound to that execution;
- deterministic validation of the adapter result;
- semantic review where required by the adapter;
- evidence that the adapter was applied exactly once;
- evidence that an unbound execution did not load the adapter capsule.

Infrastructure/model adapter metadata is not LF adapter evidence and must remain in a separate field/namespace.

Runtime-disabled candidate packages may demonstrate contract-quality PASS, but must not be reported as live runtime PASS until canonical execution evidence exists.
