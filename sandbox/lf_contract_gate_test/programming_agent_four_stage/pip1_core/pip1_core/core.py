"""PIP-1 candidate contract, DAG, transitions and closure checks (pure Python)."""
from __future__ import annotations
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any, Mapping
from types import MappingProxyType
import hashlib
import json
import re

SCHEMA = 'PROGRAMMING_CHECKPOINT_INVENTORY_V1'
HEAD_RE = re.compile(r'^[0-9a-f]{40}$')
SHA_RE = re.compile(r'^[0-9a-f]{64}$')
CP_RE = re.compile(r'^(PG-(?:0[0-9]|1[0-9]|20))\.C([1-9][0-9]*)$')

class PIPError(ValueError):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code

class State(str, Enum):
    PENDING = 'PENDING'
    ELIGIBLE = 'ELIGIBLE'
    RUNNING = 'RUNNING'
    SUCCEEDED_ACCREDITED = 'SUCCEEDED_ACCREDITED'
    NOT_APPLICABLE_JUSTIFIED = 'NOT_APPLICABLE_JUSTIFIED'
    FAILED = 'FAILED'
    BLOCKED = 'BLOCKED'
    INVALIDATED = 'INVALIDATED'
    SUCCEEDED_SYNTHETIC = 'SUCCEEDED_SYNTHETIC'
    SYNTHETIC_ONLY = 'SYNTHETIC_ONLY'

SATISFIED = frozenset({State.SUCCEEDED_ACCREDITED, State.NOT_APPLICABLE_JUSTIFIED})

@dataclass(frozen=True)
class Pins:
    head_sha: str
    catalog_sha256: str
    contract_sha256: str
    inventory_sha256: str
    def validate(self) -> None:
        if not HEAD_RE.fullmatch(self.head_sha) or any(not SHA_RE.fullmatch(x) for x in (self.catalog_sha256, self.contract_sha256, self.inventory_sha256)):
            raise PIPError('INVALID_EXACT_PINS')
    def fingerprint(self) -> str:
        self.validate()
        return hashlib.sha256(json.dumps(self.__dict__, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

@dataclass(frozen=True)
class Receipt:
    execution_id: str
    run_id: str
    checkpoint_id: str
    source_head_sha: str
    context_fingerprint: str
    provider_ref: str
    receipt_sha256: str
    verdict: str
    # A fixture is explicitly not an operational receipt.
    provenance: str = 'SYNTHETIC_FIXTURE'
    def valid(self, run: 'RunContract', cp: str, *, operational: bool = False) -> bool:
        return all((
            self.execution_id == run.execution_id,
            self.run_id == run.run_id,
            self.checkpoint_id == cp,
            self.source_head_sha == run.pins.head_sha,
            self.context_fingerprint == run.pins.fingerprint(),
            bool(self.provider_ref.strip()),
            bool(SHA_RE.fullmatch(self.receipt_sha256)),
            self.verdict == 'PASS',
            (not operational or self.provenance == 'PROVIDER_VERIFIED'),
        ))

@dataclass(frozen=True)
class RunContract:
    pipeline_code: str
    pipeline_version: str
    execution_id: str
    run_id: str
    executor_id: str
    scope_ref: str
    pins: Pins
    authority_status: str = 'CANDIDATE_NOT_APPROVED'
    def validate(self) -> None:
        self.pins.validate()
        if self.pipeline_code != 'PIP-1' or not self.pipeline_version or not all((self.execution_id, self.run_id, self.executor_id, self.scope_ref)):
            raise PIPError('INVALID_RUN_CONTRACT')
        if self.authority_status != 'CANDIDATE_NOT_APPROVED':
            raise PIPError('AUTHORITY_ESCALATION_FORBIDDEN')

@dataclass(frozen=True)
class Outcome:
    state: State
    code: str
    reason: str
    receipt: Receipt | None = None

@dataclass(frozen=True)
class Inventory:
    version: str
    digest: str
    pg00: frozenset[str]
    checkpoints: Mapping[str, tuple[str, ...]]
    requires: Mapping[str, frozenset[str]]
    excluded: frozenset[str]  # proposal references; only non-baseline IDs are excluded checkpoints
    excluded_checkpoint_ids: frozenset[str] = frozenset()
    def operational_ids(self) -> frozenset[str]:
        return frozenset(cp for cps in self.checkpoints.values() for cp in cps)
    def all_ids(self) -> frozenset[str]:
        return self.operational_ids() | self.pg00
    def topo_layers(self) -> tuple[tuple[str, ...], ...]:
        remaining = set(self.checkpoints)
        layers = []
        while remaining:
            eligible = tuple(sorted(u for u in remaining if not (self.requires[u] & remaining)))
            if not eligible:
                raise PIPError('DAG_CYCLE')
            layers.append(eligible)
            remaining.difference_update(eligible)
        return tuple(layers)
    def eligible(self, unit: str, accredited: Mapping[str, Outcome]) -> bool:
        if unit not in self.checkpoints:
            raise PIPError('UNKNOWN_UNIT')
        for dep in self.requires[unit]:
            for cp in self.checkpoints[dep]:
                outcome = accredited.get(cp)
                if outcome is None or outcome.state not in SATISFIED:
                    return False
        return True

def load_inventory(path: str | Path, *, expected_digest: str | None = None, expected_file_sha256: str | None = None, strict_candidate: bool = True) -> Inventory:
    def no_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict:
        d = {}
        for key, val in pairs:
            if key in d:
                raise PIPError('DUPLICATE_JSON_KEY')
            d[key] = val
        return d
    source_path = Path(path)
    if source_path.stat().st_size > 2_000_000:
        raise PIPError('INVENTORY_SIZE_LIMIT')
    raw = source_path.read_bytes()
    if strict_candidate and expected_file_sha256 is None and expected_digest is None:
        raise PIPError('EXTERNAL_PIN_REQUIRED')
    if expected_file_sha256 is not None:
        if not SHA_RE.fullmatch(expected_file_sha256):
            raise PIPError('INVALID_EXPECTED_FILE_SHA256')
        if hashlib.sha256(raw).hexdigest() != expected_file_sha256:
            raise PIPError('FULL_FILE_SHA256_MISMATCH')
    obj = json.loads(raw.decode('utf-8'), object_pairs_hook=no_duplicate_pairs)
    if not isinstance(obj, dict) or not isinstance(obj.get('inventory_core'), dict):
        raise PIPError('INVALID_INVENTORY_SHAPE')
    if obj.get('authority_status') != 'CANDIDATE_NOT_APPROVED':
        raise PIPError('INVENTORY_AUTHORITY_NOT_CANDIDATE')
    core = obj['inventory_core']
    if obj.get('canonicalization') != 'json utf8 sort_keys true ensure_ascii false separators comma colon; hash over inventory_core only' and strict_candidate:
        raise PIPError('CANONICALIZATION_UNRECOGNIZED')
    if core.get('schema') != SCHEMA:
        raise PIPError('INVENTORY_SCHEMA_MISMATCH')
    # inventory_core is authoritative input; checksum uses the format declared by the source.
    canonical = json.dumps(core, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    digest = hashlib.sha256(canonical).hexdigest()
    if obj.get('inventory_digest_sha256') != digest or (expected_digest is not None and expected_digest != digest):
        raise PIPError('INVENTORY_DIGEST_MISMATCH')
    pg00_rows = core['external_prerequisite']['checkpoints']
    pg00 = frozenset(c['checkpoint_id'] for c in pg00_rows)
    if len(pg00) != len(pg00_rows) or len(pg00) != 11 or any(not cp.startswith('PG-00.C') for cp in pg00):
        raise PIPError('PG00_PREREQUISITES_INVALID')
    checkpoints: dict[str, tuple[str, ...]] = {}
    for unit in core['operational_units']:
        uid = unit['unit_id']
        if uid in checkpoints or not re.fullmatch(r'PG-(?:0[1-9]|1[0-9]|20)', uid):
            raise PIPError('DUPLICATE_OR_UNKNOWN_UNIT')
        cps = tuple(c['checkpoint_id'] for c in unit['checkpoints'] if c.get('status') == 'REQUIRED')
        if (
            len(cps) != len(unit['checkpoints'])
            or len(cps) != len(set(cps))
            or any((match := CP_RE.fullmatch(cp)) is None or match.group(1) != uid for cp in cps)
        ):
            raise PIPError('CHECKPOINT_ID_OR_STATUS_INVALID')
        checkpoints[uid] = cps
    if len(checkpoints) != 20 or set(checkpoints) != {f'PG-{n:02}' for n in range(1,21)} or sum(map(len, checkpoints.values())) != 97:
        raise PIPError('REQUIRED_CHECKPOINT_COVERAGE_MISMATCH')
    edges = core['requires_edges']
    requires: dict[str, set[str]] = {u: set() for u in checkpoints}
    pairs = set()
    for edge in edges:
        u, dep = edge['from'], edge['requires']
        if u not in requires or dep not in requires:
            raise PIPError('UNKNOWN_DEPENDENCY')
        if (u, dep) in pairs:
            raise PIPError('DUPLICATE_DEPENDENCY')
        pairs.add((u, dep))
        requires[u].add(dep)
    if len(edges) != 22:
        raise PIPError('DEPENDENCY_COUNT_MISMATCH')
    proposals = obj.get('excluded_proposals', [])
    excludes = frozenset(x['checkpoint_id'] for x in proposals)
    baseline = frozenset(cp for rows in checkpoints.values() for cp in rows) | pg00
    excluded_ids = excludes - baseline
    if len(proposals) != len(excludes) or excluded_ids != frozenset({'PG-07.C7'}):
        raise PIPError('EXCLUDED_PROPOSAL_MISMATCH')
    if any((p['checkpoint_id'] == 'PG-07.C7') != (p.get('reason') == 'PROPOSED_NOT_REQUIRED') for p in proposals):
        raise PIPError('EXCLUDED_PROPOSAL_SEMANTICS_INVALID')
    inv = Inventory(obj['inventory_version'], digest, pg00, MappingProxyType(checkpoints), MappingProxyType({k:frozenset(v) for k,v in requires.items()}), excludes, excluded_ids)
    inv.topo_layers()
    if len(inv.all_ids()) != 108:
        raise PIPError('TOTAL_CHECKPOINT_COUNT_MISMATCH')
    if strict_candidate and (obj['inventory_version'] != '0.1.1-candidate' or obj.get('approval_ref') is not None or obj.get('pg00_certification_ref') is not None):
        raise PIPError('CANDIDATE_AUTHORITY_DRIFT')
    return inv

ALLOWED = {
    State.PENDING: frozenset({State.ELIGIBLE, State.BLOCKED, State.INVALIDATED}),
    State.ELIGIBLE: frozenset({State.RUNNING, State.BLOCKED, State.INVALIDATED}),
    State.RUNNING: frozenset({State.SUCCEEDED_SYNTHETIC, State.SUCCEEDED_ACCREDITED, State.NOT_APPLICABLE_JUSTIFIED, State.FAILED, State.BLOCKED, State.INVALIDATED}),
    State.BLOCKED: frozenset({State.PENDING, State.INVALIDATED}),
    State.FAILED: frozenset({State.PENDING, State.INVALIDATED}),
    State.INVALIDATED: frozenset({State.PENDING}),
    State.SUCCEEDED_ACCREDITED: frozenset({State.INVALIDATED}),
    State.SUCCEEDED_SYNTHETIC: frozenset({State.INVALIDATED}),
    State.NOT_APPLICABLE_JUSTIFIED: frozenset({State.INVALIDATED}),
}

def _assert_run_inventory(run: RunContract, inventory: Inventory) -> None:
    if run.pins.inventory_sha256 != inventory.digest:
        raise PIPError('RUN_INVENTORY_PIN_MISMATCH')


def _verified_dependencies(inventory: Inventory, run: RunContract, unit: str,
                           outcomes: Mapping[str, Outcome]) -> None:
    for dep in inventory.requires[unit]:
        for prior_cp in inventory.checkpoints[dep]:
            prior = outcomes.get(prior_cp)
            if prior is None:
                raise PIPError('DEPENDENCY_UNSATISFIED')
            if (prior.state not in (State.SUCCEEDED_ACCREDITED, State.SUCCEEDED_SYNTHETIC) or prior.receipt is None
                    or not prior.receipt.valid(run, prior_cp, operational=False)):
                raise PIPError('PREREQUISITE_EVIDENCE_UNVERIFIED')


def transition(current: State, target: State, *, run: RunContract, checkpoint_id: str, inventory: Inventory,
               outcomes: Mapping[str, Outcome], receipt: Receipt | None = None,
               reason: str = '', na_authority_ref: str = '', operational: bool = False) -> Outcome:
    run.validate()
    _assert_run_inventory(run, inventory)
    if checkpoint_id not in inventory.operational_ids():
        raise PIPError('UNKNOWN_CHECKPOINT')
    if operational and target in (State.ELIGIBLE, State.SUCCEEDED_ACCREDITED, State.SUCCEEDED_SYNTHETIC):
        raise PIPError('EXTERNAL_RECEIPT_AUTHORITY_NOT_INTEGRATED')
    if operational and target == State.NOT_APPLICABLE_JUSTIFIED:
        raise PIPError('EXTERNAL_NA_AUTHORITY_NOT_INTEGRATED')
    observed = outcomes.get(checkpoint_id)
    # Caller-supplied current is not an authority. A missing entry means PENDING only.
    authoritative = observed.state if observed is not None else State.PENDING
    if current != authoritative:
        raise PIPError('CURRENT_STATE_MISMATCH')
    if target not in ALLOWED[current]:
        raise PIPError('ILLEGAL_TRANSITION')
    unit = checkpoint_id.split('.')[0]
    if target in (State.ELIGIBLE, State.RUNNING, State.SUCCEEDED_SYNTHETIC,
                  State.SUCCEEDED_ACCREDITED):
        _verified_dependencies(inventory, run, unit, outcomes)
    if target == State.SUCCEEDED_ACCREDITED:
        # The local fixture cannot be claimed as accredited.
        raise PIPError('EXTERNAL_RECEIPT_AUTHORITY_NOT_INTEGRATED')
    if target == State.SUCCEEDED_SYNTHETIC:
        if receipt is None or not receipt.valid(run, checkpoint_id, operational=False):
            raise PIPError('RECEIPT_INVALID_OR_FOREIGN')
        if receipt.provenance != 'SYNTHETIC_FIXTURE':
            raise PIPError('SYNTHETIC_PROVENANCE_REQUIRED')
    if target == State.NOT_APPLICABLE_JUSTIFIED and not (reason.strip() and na_authority_ref.strip()):
        raise PIPError('NA_AUTHORITY_MISSING')
    if target in (State.BLOCKED, State.FAILED, State.INVALIDATED) and not reason.strip():
        raise PIPError('TYPED_REASON_REQUIRED')
    return Outcome(target, target.value, reason or 'GUARD_SATISFIED', receipt)

def material_drift(run: RunContract, observed: Pins) -> bool:
    return run.pins.fingerprint() != observed.fingerprint()

def invalidated_descendants(inventory: Inventory, changed_unit: str) -> frozenset[str]:
    if changed_unit not in inventory.checkpoints:
        raise PIPError('UNKNOWN_UNIT')
    found = {changed_unit}
    while True:
        newer = found | {u for u, dependencies in inventory.requires.items() if dependencies & found}
        if newer == found:
            break
        found = newer
    return frozenset(cp for u in found for cp in inventory.checkpoints[u])

def verify_closure(inventory: Inventory, run: RunContract, outcomes: Mapping[str, Outcome], *, operational: bool = False) -> Outcome:
    run.validate()
    _assert_run_inventory(run, inventory)
    if operational:
        raise PIPError('EXTERNAL_CLOSURE_AUTHORITY_NOT_INTEGRATED')
    required = inventory.operational_ids()
    if set(outcomes) - required:
        raise PIPError('UNKNOWN_CHECKPOINT_IN_CLOSURE')
    if required - set(outcomes):
        raise PIPError('REQUIRED_CHECKPOINT_MISSING')
    # Stable validation order: dependency failures precede local state failures.
    # Never iterate frozenset keys when determining an externally visible error.
    ordered = tuple(cp for layer in inventory.topo_layers()
                    for unit in layer for cp in inventory.checkpoints[unit])
    for cp in ordered:
        unit = cp.split('.')[0]
        for dep in sorted(inventory.requires[unit]):
            for prior_cp in inventory.checkpoints[dep]:
                if outcomes[prior_cp].state not in (State.SUCCEEDED_SYNTHETIC, State.SUCCEEDED_ACCREDITED):
                    raise PIPError('DEPENDENCY_UNSATISFIED')
    for cp in ordered:
        outcome = outcomes[cp]
        if outcome.state == State.NOT_APPLICABLE_JUSTIFIED:
            raise PIPError('NA_CLOSURE_AUTHORITY_NOT_VERIFIABLE')
        if outcome.state not in (State.SUCCEEDED_SYNTHETIC, State.SUCCEEDED_ACCREDITED):
            raise PIPError('REQUIRED_CHECKPOINT_PENDING')
        if outcome.receipt is None or not outcome.receipt.valid(run, cp):
            raise PIPError('CLOSURE_RECEIPT_INVALID')
        if outcome.state == State.SUCCEEDED_ACCREDITED and outcome.receipt.provenance != 'PROVIDER_VERIFIED':
            raise PIPError('CLOSURE_ACCREDITATION_PROVENANCE_INVALID')
    # Never conflate a synthetic closure with accredited provider evidence.
    return Outcome(State.SYNTHETIC_ONLY, 'SYNTHETIC_CLOSURE', 'ALL_REQUIRED_SYNTHETIC_OR_FIXTURE')
