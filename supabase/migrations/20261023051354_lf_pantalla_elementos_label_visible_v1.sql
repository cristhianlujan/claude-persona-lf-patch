-- LF: los elementos de pantalla (botones, enlaces, acciones) no tenian donde guardar su texto visible, a diferencia de
-- lf_ops.campos_pantallas.label_visible. Hallazgo al pedir "renombrar el boton principal del login B2B a Acceder":
-- B2B_AUTH001_SUBMIT (PRIMARY_CTA de B2B-AUTH-001) no tiene texto en ninguna tabla (27 PRIMARY_CTA en 16 pantallas, ninguno con texto).
-- Cambio: columna label_visible (nullable, no vacia si existe) en lf_ops.pantalla_elementos y el valor 'Acceder' SOLO para B2B_AUTH001_SUBMIT.
-- Los demas elementos quedan en NULL (su texto no se inventa). Idempotente. Aplica solo por ACTUALIZACION_DB_LF / Merge Train.
BEGIN;

ALTER TABLE lf_ops.pantalla_elementos ADD COLUMN IF NOT EXISTS label_visible text;

DO $c$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='lf_ops.pantalla_elementos'::regclass AND conname='pantalla_elementos_label_visible_check') THEN
    ALTER TABLE lf_ops.pantalla_elementos
      ADD CONSTRAINT pantalla_elementos_label_visible_check CHECK (label_visible IS NULL OR btrim(label_visible) <> '');
  END IF;
END
$c$;

COMMENT ON COLUMN lf_ops.pantalla_elementos.label_visible IS
'Texto visible del elemento (p. ej. el texto del boton). Equivale a lf_ops.campos_pantallas.label_visible. NULL = aun no definido; no se inventa.';

DO $u$
DECLARE
  v_total_antes bigint; v_con_label_antes bigint; v_n integer;
  v_pid bigint; v_label text;
BEGIN
  SELECT count(*) INTO v_total_antes FROM lf_ops.pantalla_elementos;
  SELECT count(*) INTO v_con_label_antes FROM lf_ops.pantalla_elementos WHERE label_visible IS NOT NULL;
  SELECT id INTO v_pid FROM lf_ops.pantallas WHERE codigo='B2B-AUTH-001';
  IF v_pid IS NULL THEN RAISE EXCEPTION 'LABEL_VISIBLE_PANTALLA_NO_ENCONTRADA'; END IF;

  UPDATE lf_ops.pantalla_elementos
     SET label_visible='Acceder', updated_at=now()
   WHERE pantalla_id=v_pid AND element_code='B2B_AUTH001_SUBMIT' AND element_role='PRIMARY_CTA'
     AND label_visible IS DISTINCT FROM 'Acceder';
  GET DIAGNOSTICS v_n = ROW_COUNT;

  -- Ensayo (cualquier fallo revierte todo)
  SELECT label_visible INTO v_label FROM lf_ops.pantalla_elementos WHERE pantalla_id=v_pid AND element_code='B2B_AUTH001_SUBMIT';
  IF v_label IS DISTINCT FROM 'Acceder' THEN RAISE EXCEPTION 'LABEL_VISIBLE_BOTON_NO_QUEDO_%', v_label; END IF;
  IF (SELECT count(*) FROM lf_ops.pantalla_elementos) IS DISTINCT FROM v_total_antes THEN
    RAISE EXCEPTION 'LABEL_VISIBLE_CONTEO_CAMBIO'; END IF;
  -- Solo ese elemento tiene texto (mas los que ya lo tuvieran antes: ninguno)
  IF (SELECT count(*) FROM lf_ops.pantalla_elementos WHERE label_visible IS NOT NULL) IS DISTINCT FROM v_con_label_antes + (CASE WHEN v_n=1 THEN 1 ELSE 0 END) THEN
    RAISE EXCEPTION 'LABEL_VISIBLE_OTROS_ELEMENTOS_TOCADOS'; END IF;
  IF (SELECT count(*) FROM lf_ops.pantalla_elementos WHERE pantalla_id=v_pid AND label_visible IS NOT NULL) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'LABEL_VISIBLE_OTROS_ELEMENTOS_DEL_LOGIN_TOCADOS'; END IF;
  -- Autenticacion, validaciones y campos del login intactos
  IF (SELECT count(*) FROM lf_ops.campos_pantallas WHERE pantalla_id=v_pid AND label_visible IN ('Correo electrónico','Contraseña')) IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'LABEL_VISIBLE_CAMPOS_LOGIN_CAMBIARON'; END IF;
END
$u$;

COMMIT;
