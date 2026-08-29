# Quality V2 Scope Boundaries

This remediation changes candidate adapter contracts/evidence only.

It does not:
- enable runtime;
- promote adapters to VALIDATED;
- enable automatic impact;
- modify production;
- authorize an independent adapter model call;
- replace specialist profile authority.

Runtime enforcement requires the canonical execution surface to resolve governed adapter bindings and persist `lf_adapter_invocations` evidence before a live invocation claim can pass.
