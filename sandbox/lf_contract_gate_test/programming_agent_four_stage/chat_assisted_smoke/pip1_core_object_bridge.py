"""Pure bridge from Carril D objects to chat advisory. No DB or writes."""
from collections.abc import Mapping
from pip1_chat_advisory import advise, AdvisoryError

def advise_pip1(run, inventory, outcomes: Mapping, *, checkpoint_id: str) -> dict:
    # Import only the canonical PIP-1 core at caller-provided PYTHONPATH.
    from pip1_core.core import PIPError
    if not isinstance(outcomes, Mapping):
        raise AdvisoryError("OUTCOMES_NOT_OBJECT")
    try:
        run.validate()
        if run.pins.inventory_sha256 != inventory.digest:
            raise AdvisoryError("INVENTORY_PIN_MISMATCH")
        if checkpoint_id not in inventory.operational_ids():
            raise AdvisoryError("CHECKPOINT_NOT_IN_INVENTORY")
        item = outcomes.get(checkpoint_id)
        if item is None:
            state = "PENDING"
        else:
            state = item.state.value
        result = advise({"checkpoint_id":checkpoint_id,"state":state},expected_checkpoint=checkpoint_id)
        result["source"] = "PIP1_CORE_OBJECTS"
        result["run_id"] = run.run_id
        result["execution_id"] = run.execution_id
        return result
    except (PIPError,AttributeError,TypeError,ValueError) as exc:
        if isinstance(exc,AdvisoryError):
            raise
        raise AdvisoryError("PIP1_OBJECT_INVALID") from exc
