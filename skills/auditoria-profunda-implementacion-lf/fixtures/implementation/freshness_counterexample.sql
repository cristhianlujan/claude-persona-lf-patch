-- PostgreSQL candidate ONLY: not executed on any database by this package.
-- A consumer that requires immediate balances cannot use periodic refresh.
CREATE MATERIALIZED VIEW balances_stale AS
SELECT tenant, sum(amount) AS balance FROM payments GROUP BY tenant;
