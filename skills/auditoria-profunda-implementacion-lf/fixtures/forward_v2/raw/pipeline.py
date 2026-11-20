from producer import prepare
from consumer import assess


def run(portfolio_key, execution_id, *, currency, source_revision, as_of):
    message = prepare(portfolio_key, execution_id, currency=currency, source_revision=source_revision)
    return assess(message)
