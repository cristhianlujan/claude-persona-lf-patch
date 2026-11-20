-- Núcleo de reglas, fase F0: corrección B14 del árbol de alcance (no copiar relaciones derivables).
-- Los nodos de pantalla dejan de repetir el código de la pantalla: se identifican por su id estable
-- (PANTALLA-<id>) y el código vigente se lee siempre de lf_ops.pantallas mediante la vista.
UPDATE lf_ops.nucleo_nodos
   SET codigo = 'PANTALLA-' || pantalla_id
 WHERE nivel = 'PANTALLA';

ALTER TABLE lf_ops.nucleo_nodos
  ADD CONSTRAINT nucleo_nodos_pantalla_por_id
  CHECK (nivel <> 'PANTALLA' OR codigo = 'PANTALLA-' || pantalla_id);

CREATE VIEW lf_ops.v_nucleo_nodos WITH (security_invoker = true) AS
SELECT n.codigo,
       n.padre,
       n.nivel,
       n.pantalla_id,
       p.codigo AS pantalla_codigo,
       COALESCE(p.codigo, n.codigo) AS etiqueta,
       n.nota
  FROM lf_ops.nucleo_nodos n
  LEFT JOIN lf_ops.pantallas p ON p.id = n.pantalla_id;
COMMENT ON VIEW lf_ops.v_nucleo_nodos IS
  'Árbol de alcance con el código vigente de cada pantalla leído de lf_ops.pantallas (no se copia).';
REVOKE ALL ON lf_ops.v_nucleo_nodos FROM PUBLIC;
REVOKE ALL ON lf_ops.v_nucleo_nodos FROM anon, authenticated;
