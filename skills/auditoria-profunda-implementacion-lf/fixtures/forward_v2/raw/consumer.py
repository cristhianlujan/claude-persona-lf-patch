def assess(message, *, as_of):
    if message["currency"] not in ("PEN", "USD"):
        raise ValueError("CURRENCY_UNSUPPORTED")
    if message["source_revision"] != as_of:
        raise ValueError("SOURCE_REVISION_STALE")
    return {"decision": "READY", "execution_id": message["execution_id"]}
