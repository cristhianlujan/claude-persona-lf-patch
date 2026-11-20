"""Raw fixture code, intentionally executable only in isolated local tests."""
from consumer import apply_contract


def origin():
    return {"a": 4, "b": 5, "c": "tenant-1", "d": "revision-1"}


def broken_transport():
    data = origin()
    variable1 = data["a"]
    variable2 = data["c"]
    return apply_contract(variable1)


def correct_transport():
    data = origin()
    variable1 = data["a"]
    variable2 = data["c"]
    return apply_contract(variable1, variable2)


def broken_payload():
    data = origin()
    return {"a": data["a"], "b": data["b"]}


def correct_payload():
    return origin()


def broken_branch(state):
    if state == "READY":
        return "EXECUTE"


def correct_branch(state):
    if state == "READY":
        return "EXECUTE"
    elif state == "RETRY":
        return "REQUEUE"
    elif state == "BLOCKED":
        return "STOP"
    raise ValueError("UNKNOWN_STATE")


def broken_comment(context):
    return "Hay un problema. Revisar el backend."


def correct_comment(context):
    return {"cause": context["trace"], "location": context["location"],
            "impact": "No se entrega el tenant al consumidor",
            "correction": "apply_contract(variable1, variable2)",
            "test": "assert correct_transport() == (4, 'tenant-1')"}
