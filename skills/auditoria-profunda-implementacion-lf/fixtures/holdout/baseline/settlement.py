def settle(payload, revision):
    return payload["account"], payload["gross"], payload["currency"], revision
