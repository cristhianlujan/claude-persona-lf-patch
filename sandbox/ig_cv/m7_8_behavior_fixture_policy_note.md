# M7.8 behavior fixture policy

Generic control tests select by behavior precondition, not fixed screen identity. If no live target currently exhibits the required STALE condition, R17 must create a controlled rollback-only stale condition on a dynamically selected current high-complexity screen and prove that all source/run/function changes roll back. Screen identity is incidental evidence only.
