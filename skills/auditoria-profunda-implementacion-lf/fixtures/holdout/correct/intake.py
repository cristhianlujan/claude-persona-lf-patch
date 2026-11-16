from settlement import settle

def source():
    return {"account": "A17", "gross": 12, "currency": "PEN", "revision_nonce": "N19"}

def dispatch():
    record = source()
    payload = {"account": record["account"], "gross": record["gross"], "currency": record["currency"]}
    revision = record["revision_nonce"]
    return settle(payload, revision)

def act(status):
    if status == "QUEUED":
        return "RUN"
    if status == "CANCELLED":
        return "STOP"
    if status == "WAITING_FUNDS":
        return "DEFER"
