# Núcleo de Procesos SALY — candidato (NO migración)

Estado: CANDIDATO de QA. No se despliega ni se aplica a Supabase. Solo prueba el modelo en PG17 aislado vía PASE.
Origen: SQL de GPT (chat Saly - Planeamiento) transcrito; la indentación del original no se conservó (los hashes no coinciden con los del handoff).
Pendiente de decisión: reutilizar `nucleo_nodos`/`nucleo_relaciones`/`saly.transiciones` antes de cualquier migración.
Límites conocidos: una sola ruta por origen; sin concurrencia ni TRUNCATE CASCADE probados; sin aprobación/activación.
