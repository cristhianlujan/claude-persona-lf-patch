# STORY_J02_TASK_RUNTIME_SOURCE_PACK_V1

Source pack determinista para construir el `task_authority` de J02 desde un checkout exacto, sin hardcodear hashes que quedan stale.

## Qué hace

Lee únicamente seis fuentes J02 del Story Creator:

- Profile Screen Decomposer;
- agent Screen Decomposer;
- schema de screen decomposition;
- validator visual v0.8;
- judge J02;
- protocolo de decomposition.

Calcula SHA-256 directamente sobre los bytes del checkout exacto y exige un `source_revision` Git de 40 hexadecimales.

También valida que el judge leído sea exactamente `J02_SCREEN_DECOMPOSITION` v0.8, mantenga independencia worker/judge y apunte a `validate_screen_decomposition_visual.py`.

## Autoridades externas

Los siguientes refs no se inventan desde Git y deben llegar como snapshot vivo con `ref + revision + digest`:

- Profile asset;
- manifest artifact;
- J02 judge registry;
- currentness receipt.

El builder no consulta Supabase; sólo cross-bindea el snapshot entregado.

## Salida

Produce `LF_PROFILE_TASK_AUTHORITY_SNAPSHOT_V1`, listo para alimentar a `PROFILE_TASK_RUNTIME_BINDING_V1` junto con el worker binding/profile authority resueltos.

## Boundary

No registra Profile, no crea runtime binding persistente, no llama red/DB, no modifica artifacts y no activa runtime. Los hashes son derivados en ejecución, no autoridad estática almacenada.
