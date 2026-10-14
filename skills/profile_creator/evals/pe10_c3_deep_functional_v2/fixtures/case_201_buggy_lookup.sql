-- Synthetic implementation excerpt representing the original root defect.
-- This query loses the original offer/obligation identity and selects one matching external ref.
SELECT c.id AS selected_obligacion
FROM cartera c
WHERE c.ref_externa = :ref_externa
ORDER BY c.carga_id ASC
LIMIT 1;
-- Reference-only lookup is not unique across cargas.
