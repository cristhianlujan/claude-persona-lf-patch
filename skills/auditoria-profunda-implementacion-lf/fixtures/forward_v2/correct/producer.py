def prepare(portfolio_key, execution_id, *, currency, source_revision):
    return {
        "portfolio_key": portfolio_key,
        "execution_id": execution_id,
        "currency": currency,
        "source_revision": source_revision,
    }
