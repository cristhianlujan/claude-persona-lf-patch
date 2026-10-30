# PG-00_C3 — frontera de confianza del verificador candidato

Estado: **NO AUTORIZA**. Debe leerse antes de integrar `pg00_c3_source_verify_candidate_v1.py`.

El módulo compara contenido y SHA256 del archivo en un commit exacto. **No autentica por sí mismo** el origen GitHub: `AuthenticatedGitRead.source_authenticated` es suministrado por el adaptador y puede falsificarse en un ensayo o por un llamador. Por diseño la función **siempre devuelve verified=false y decision=BLOCK** incluso si ambos hashes coinciden.

No usar en PG-01_C4 ni PG-02 como gate de admisión. Para pasar a producción: integrar adaptador de GitHub confiable con identidad y commit exactos no controlables por la solicitud; resolver lectura de DB autorizada desde fuente propia y recibo Train/PASE exact-head; comprobar vinculación criptográfica de digest raw, versión y reglas a release; hacer pruebas independientes con PostgreSQL real, forgery y drift; someter a revisión y transporte gobernado.

Límites de pruebas: el archivo `test_pg00_c3_source_verify_candidate_v1.py` contiene casos negativos y un caso de hash coincidente que aun así BLOQUEA. No se ejecutó en host remoto en esta sesión por una restricción de ejecución; no declarar PASS de runtime sin recibo.
