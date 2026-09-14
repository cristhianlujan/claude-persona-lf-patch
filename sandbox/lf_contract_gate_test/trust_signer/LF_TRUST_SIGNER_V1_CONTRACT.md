# LF Trusted Attestation Signer V1

This reusable workflow is an external trust producer for LF candidate evidence. The caller checkout is untrusted input; the workflow definition at its immutable signer commit is the trusted builder.

For profile `S38_DG_IR008` it hard-codes the runtime and evidence TCB surfaces, recomputes Git blob and SHA-256 identities from the exact caller source commit, independently verifies every declared historical pin, and emits one deterministic subject manifest. `actions/attest` binds that subject to the reusable workflow identity and source repository digest through GitHub OIDC/Sigstore.

Independent verification must supply the expected signer workflow and exact signer commit digest out-of-band. A candidate checkout, its policy, or its resolver must not select that digest. After downloading the attestation bundle/trusted root once, repeated adversarial checks may be performed offline.

The attestation is provenance only. It grants no merge, Golden, runtime, scheduler, production, or promotion authority.
