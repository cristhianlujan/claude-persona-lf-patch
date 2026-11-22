# Núcleo de Procesos SALY — candidato (NO migración)

Estado: CANDIDATO de QA. No se despliega ni se aplica a Supabase. Solo prueba el modelo en PG17 aislado vía PASE.
Origen: SQL de GPT (chat Saly - Planeamiento) transcrito; la indentación del original no se conservó (los hashes no coinciden con los del handoff).
v2: el proceso se ubica en un nodo MODULO de `saly.nucleo_nodos` (no se duplica jerarquía); Canal se agregaría solo por cambio gobernado del núcleo.
Límites conocidos: una sola ruta por origen; sin concurrencia ni TRUNCATE CASCADE probados; sin aprobación/activación.
