"""Trusted deployment registry. Intentionally empty until handler contract promotion.

Register only reviewed Handler instances with an exact Router operation/target
binding. Never load modules, SQL statements or Python expressions from callers.
"""
from lf_operation_executor_v1 import Handler

HANDLERS: dict[str, Handler] = {}
