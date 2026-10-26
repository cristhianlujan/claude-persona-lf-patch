"""Explicit source-only composition. No entrypoint, environment or file loading."""
from __future__ import annotations

from analysis_a6_a9_ro_transport_v1 import A6A9CompletionObserver, PsycopgReadOne

DISABLED_CONFIG = {"schema_version": "A6_A9_COMPLETION_SHADOW_CONFIGURATION_V1",
                   "enabled": False, "bindings": []}


def create_a6_a9_app(settings=None, *, config=None, connection=None, engine_factory=None):
    """Compose existing app; caller supplies already approved settings/config.

    No model invocation, DB connection or engine initialization at composition.
    Enabled does not authorize deployment, producer execution or admission.
    """
    from profile_runtime_api.app import create_app
    selected = dict(DISABLED_CONFIG) if config is None else config
    # Validate even when disabled; never silently convert bad config to enabled.
    observer = A6A9CompletionObserver.from_config(selected, None)
    kwargs = {} if engine_factory is None else {"engine_factory": engine_factory}
    if selected["enabled"] is False:
        return create_app(settings, **kwargs)
    read_one = PsycopgReadOne(connection=connection)
    observer = A6A9CompletionObserver.from_config(selected, read_one)
    return create_app(settings, completion_observer=observer, **kwargs)
