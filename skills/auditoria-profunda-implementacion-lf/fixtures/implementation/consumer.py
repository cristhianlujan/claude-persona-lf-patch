def consume(packet):
    return (packet["a"] + packet["b"], packet["c"], packet["d"])


def apply_contract(variable1, variable2):
    if not isinstance(variable1, int) or not isinstance(variable2, str):
        raise TypeError("CONSUMER_INPUT_TYPES_INVALID")
    return variable1, variable2


def amount_consumer(packet):
    if type(packet["amount"]) is not int or packet["amount"] < 0:
        raise ValueError("AMOUNT_MUST_BE_NONNEGATIVE_INTEGER")
    return packet["amount"] + 1


def per_step_reads(db, identity):
    return [db.read(identity) for _ in range(5)]


def shared_snapshot_reads(db, identity):
    data = db.read(identity)
    return [data.copy() for _ in range(5)]
