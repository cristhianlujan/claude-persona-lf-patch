-- Réplica mínima de saly.nucleo_nodos (mismas columnas y CHECK que producción) SOLO para PG17 aislado.
CREATE TABLE saly.nucleo_nodos (
  codigo text PRIMARY KEY, padre text REFERENCES saly.nucleo_nodos(codigo), nivel text NOT NULL,
  pantalla_id integer UNIQUE, nota text, created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((nivel = 'GLOBAL') = (padre IS NULL)),
  CHECK (nivel = ANY (ARRAY['GLOBAL','AMBITO','MODULO','PANTALLA','COMPONENTE'])),
  CHECK ((nivel = 'PANTALLA') = (pantalla_id IS NOT NULL)),
  CHECK (nivel <> 'PANTALLA' OR codigo = ('PANTALLA-' || pantalla_id))
);
INSERT INTO saly.nucleo_nodos(codigo,padre,nivel) VALUES ('G',NULL,'GLOBAL'),('MOD-TEST','G','MODULO');
INSERT INTO saly.nucleo_nodos(codigo,padre,nivel,pantalla_id) VALUES ('PANTALLA-7','MOD-TEST','PANTALLA',7);
