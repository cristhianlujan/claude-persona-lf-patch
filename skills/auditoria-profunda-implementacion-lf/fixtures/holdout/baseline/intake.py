from settlement import settle

def source():
    return {"account": "A17", "gross": 12, "currency": "PEN", "revision_nonce": "N19"}

def dispatch():
    record = source()
    payload = {"account": record["account"], "gross": record["gross"]}
    revision = record["revision_nonce"]
    return settle(payload)

def act(status):
    if status == "QUEUED":
        return "RUN"
    if status == "CANCELLED":
        return "STOP"
