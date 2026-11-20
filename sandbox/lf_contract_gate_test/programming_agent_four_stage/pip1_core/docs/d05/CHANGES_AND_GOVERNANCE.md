# D-05: cambios, gobernanza y decisiones

- D-05.1 PARTIAL: GitHub connected HEAD exact + blob SHA, corroboración del SHA256 externo del usuario; no bytes materializados localmente.
- D-05.2 BLOCKED: chequeo DAG del contenido real por JS conectado PASS; loader Python y mutaciones reales no ejecutados.
- D-05.3 PASS LOCAL: 53/53 unit tests, compileall, git diff checks. Nuevo cambio F05: verificador requiere SHA256 completo (además de blob SHA1) antes de crear output; 2 regresiones de control.
- D-05.4 NOT_RUN: PASE en checkout LF no disponible; reglamento `AGENTS.md` y `CLAUDE.md` releídos desde GitHub. PASE required; Train única vía de merge; clasificar paths antes de push; no tocar flujos.
- D-05.5 PASS DOCUMENTAL: diff, integración y review checklist. Revisión de Claude NOT_RUN.
- D-05.6 PREPARED/NOT_PUBLISHED: borrador PR sin publicar; no commit remoto.
- F01-F04 documentados en `docs/D04_ADVERSARIAL_REVIEW.md`. F05 en lote actual. No nuevos cambios de autoridad ni PG00.
- Decisiones owner: autorización posterior de push/draft PR; política de N/A y evidencia externa; seleccionar rutas clasificadas por PASE; GO al inventario por carril responsable.
