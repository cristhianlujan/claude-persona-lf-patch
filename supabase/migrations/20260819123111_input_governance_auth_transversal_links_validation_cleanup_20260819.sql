-- Link already-canonical transversal rules to active B2B auth screens that were missing the relation.
insert into lf_ops.reglas_pantallas (regla_id,pantalla_id,nota)
select r.id,p.id,'Relación transversal materializada por alcance canónico B2B; no duplica contenido de regla.'
from lf_ops.reglas r
join lf_ops.pantallas p on p.codigo in ('B2B-AUTH-002','B2B-AUTH-003','B2B-AUTH-004','B2B-AUTH-006') and p.activa=true
where r.codigo in (
  'B2B-RULE-A11Y-003','B2B-RULE-A11Y-004',
  'B2B-RULE-THEME-001','B2B-RULE-THEME-002','B2B-RULE-THEME-003',
  'B2B-RULE-ANALYTICS-001','B2B-RULE-COMPAT-001'
)
on conflict (regla_id,pantalla_id) do nothing;

-- Field-level AUTH validations already carry their own canonical user copy.
-- Remove incorrect links to file-upload error catalog entries (VAL-008/009).
update lf_ops.campos_validaciones v
set error_id=null,
    error_code=null,
    updated_at=now()
where v.codigo in (
  'B2B_VAL_LOGIN_PASSWORD_REQUIRED',
  'B2B_VAL_LOGIN_EMAIL_FORMAT',
  'B2B_VAL_RECOVERY_EMAIL_REQUIRED',
  'B2B_VAL_RECOVERY_EMAIL_FORMAT',
  'B2B_VAL_RECOVERY_NEW_PASSWORD_REQUIRED',
  'B2B_VAL_RECOVERY_NEW_PASSWORD_POLICY',
  'B2B_VAL_RECOVERY_CONFIRM_PASSWORD_REQUIRED',
  'B2B_VAL_RECOVERY_CONFIRM_PASSWORD_MATCH',
  'B2B_VAL_MFA_EMAIL_OTP_CODE_REQUIRED'
)
and v.error_id in (
  select e.error_id from lf_ops.errores_catalogo e where e.error_code in ('LF-B2B-VAL-008','LF-B2B-VAL-009')
);

-- Complete recovery OTP field feedback using existing canonical wording/policy error.
update lf_ops.campos_validaciones
set mensaje_error='Ingresa el código de verificación.',
    updated_at=now()
where codigo='B2B_VAL_RECOVERY_EMAIL_OTP_REQUIRED';

update lf_ops.campos_validaciones v
set mensaje_error=e.user_message_template,
    error_id=e.error_id,
    error_code=e.error_code,
    updated_at=now()
from lf_ops.errores_catalogo e
where v.codigo='B2B_VAL_RECOVERY_EMAIL_OTP_POLICY'
  and e.error_code='LF-B2B-AUTH-006';