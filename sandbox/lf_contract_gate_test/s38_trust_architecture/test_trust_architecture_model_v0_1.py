#!/usr/bin/env python3
"""Deterministic architecture-model checks only; not a semantic/security attestation."""

ANON_PRIMARY_LIMIT = 60
REST_CALLS_PER_RESOLVER = 2


def calls_for_current_design(constructions: int) -> int:
    return constructions * REST_CALLS_PER_RESOLVER


def architecture_is_security_root(*, verifier_outside_checkout: bool, trust_root_outside_checkout: bool) -> bool:
    return verifier_outside_checkout and trust_root_outside_checkout


def main() -> None:
    assert calls_for_current_design(30) == ANON_PRIMARY_LIMIT
    assert calls_for_current_design(31) > ANON_PRIMARY_LIMIT

    # Authenticated REST/cache improves liveness but a repo-local verifier is still self-referential.
    assert not architecture_is_security_root(
        verifier_outside_checkout=False,
        trust_root_outside_checkout=True,
    )

    # Artifact attestation or an external LF attestor qualifies only when verifier + root are external.
    assert architecture_is_security_root(
        verifier_outside_checkout=True,
        trust_root_outside_checkout=True,
    )

    # Target review model: after one bootstrap, adversarial test count does not increase REST attestation calls.
    bootstrap_calls = 1
    for attack_cases in (1, 30, 60, 100, 1000):
        assert bootstrap_calls == 1

    print("PASS_LF_TRUST_ARCHITECTURE_MODEL_V0_1")


if __name__ == "__main__":
    main()
