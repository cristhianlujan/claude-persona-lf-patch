"""SALY: simple 30-second state wait; no new image dispatch or DB writes."""
import time

INTERVAL_SECONDS = 30

def wait_for_close(readback, *, sleep=time.sleep, monotonic=time.monotonic,
                   interval=INTERVAL_SECONDS, timeout=900):
    """Readback must return order_status, run_state, evidence_verified, qa_passed."""
    if interval <= 0 or timeout <= 0:
        raise ValueError("INVALID_WAIT_POLICY")
    deadline = monotonic() + timeout
    checks = 0
    while True:
        checks += 1
        state = readback()
        if not isinstance(state, dict):
            return {"status": "READBACK_INVALID", "checks": checks}
        order = state.get("order_status")
        run = state.get("run_state")
        if (order == "TERMINADO" and run == "EXITOSO"
                and state.get("evidence_verified") is True
                and state.get("qa_passed") is True):
            return {"status": "TERMINADO_VERIFICADO", "checks": checks, "state": state}
        if order == "TERMINADO":
            return {"status": "CIERRE_NO_VERIFICADO", "checks": checks, "state": state}
        if run in ("FALLIDO", "ERROR", "CANCELADO") or order in ("CANCELADO", "BLOQUEADO_QA"):
            return {"status": "FALLO", "checks": checks, "state": state}
        now = monotonic()
        if now >= deadline:
            return {"status": "TIMEOUT_PENDIENTE", "checks": checks, "state": state}
        sleep(min(interval, deadline - now))
