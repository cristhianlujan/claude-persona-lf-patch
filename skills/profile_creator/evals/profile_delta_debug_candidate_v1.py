"""Bounded ddmin for a caller-supplied sandbox-only deterministic failure predicate.

No SQL, network, LLM, modification, or runtime effect. Caller must independently
assure its predicate is replay-safe and non-mutating. A partial result is never
reported as minimal when the probe budget is exhausted.
"""
from __future__ import annotations
from collections.abc import Callable


def minimize_failure(atoms: list[str], reproduces_failure: Callable[[tuple[str, ...]], bool],
                     *, probe_budget: int = 100) -> dict:
    def blocked(reason, probes=0):
        return {"status": "BLOCK", "reason": reason, "probes": probes, "cutover_eligible": False}
    if (not isinstance(atoms, list) or not atoms or len(atoms) > 100
            or any(not isinstance(a, str) or not a for a in atoms)
            or len(set(atoms)) != len(atoms)):
        return blocked("ATOMS_INVALID")
    if not callable(reproduces_failure):
        return blocked("SAFE_PREDICATE_REQUIRED")
    if type(probe_budget) is not int or not 1 <= probe_budget <= 10000:
        return blocked("PROBE_BUDGET_INVALID")
    cache = {}
    probes = 0
    def probe(items):
        nonlocal probes
        key = tuple(items)
        if key not in cache:
            if probes >= probe_budget:
                raise RuntimeError("PROBE_BUDGET_EXHAUSTED")
            outcome = reproduces_failure(key)
            probes += 1
            if type(outcome) is not bool:
                raise ValueError("PREDICATE_NOT_BINARY")
            cache[key] = outcome
        return cache[key]
    current = atoms[:]
    try:
        if not probe(current):
            return {"status": "NOT_REPRODUCED", "probes": probes, "cutover_eligible": False}
        n = 2
        while len(current) >= 2:
            size = (len(current) + n - 1)//n
            chunks = [current[i:i+size] for i in range(0,len(current),size)]
            reduced = False
            for chunk in chunks:
                candidate = [a for a in current if a not in chunk]
                if probe(candidate):
                    current = candidate; n = max(n-1,2); reduced = True; break
            if not reduced:
                for chunk in chunks:
                    if probe(chunk):
                        current = chunk; n = max(n-1,2); reduced = True; break
            if not reduced:
                if n >= len(current): break
                n = min(len(current),n*2)
        # Independently check each single-atom removal, no success claim on budget exhaustion.
        one_minimal = all(not probe([a for a in current if a != atom]) for atom in current)
        if not one_minimal:
            return blocked("MINIMALITY_CHECK_INCONSISTENT",probes)
        return {"status": "ONE_MINIMAL_REPRODUCER", "atoms": current,
                "removed_count": len(atoms)-len(current), "probes": probes,
                "requires_safe_external_reproduction_proof": True,
                "globally_minimal": False, "cutover_eligible": False}
    except RuntimeError as exc:
        if str(exc) != "PROBE_BUDGET_EXHAUSTED": raise
        return {"status": "INCOMPLETE_BUDGET", "current_atoms": current,
                "probes": probes, "minimality_proven": False, "cutover_eligible": False}
    except ValueError as exc:
        if str(exc) != "PREDICATE_NOT_BINARY": raise
        return blocked("PREDICATE_NOT_BINARY",probes)
