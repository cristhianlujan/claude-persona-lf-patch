-- B2B_APP_SHELL S06: additive corporate scope, physical candidate only.
-- Reuses canonical empresas, empresa_usuarios, perfiles and permisos; no parallel RBAC.
-- No grants, fixtures, selector activation, runtime connection or multi-company authorization.
CREATE TABLE lf_ops.b2b_corporate_groups (
 group_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 group_code text NOT NULL UNIQUE CHECK(length(btrim(group_code))>0),
 group_name text NOT NULL CHECK(length(btrim(group_name))>0),
 status text NOT NULL DEFAULT 'CANDIDATO' CHECK(status IN ('CANDIDATO','EN_REVISION','VIGENTE','INACTIVO','ARCHIVADO')),
 source_decision_id text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
-- One legal entity has at most one corporate parent.
CREATE TABLE lf_ops.b2b_corporate_group_companies (
 company_id uuid PRIMARY KEY REFERENCES lf_ops.empresas(company_id),
 group_id uuid NOT NULL REFERENCES lf_ops.b2b_corporate_groups(group_id),
 status text NOT NULL DEFAULT 'CANDIDATO' CHECK(status IN ('CANDIDATO','EN_REVISION','VIGENTE','INACTIVO','ARCHIVADO')),
 source_decision_id text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX b2b_group_companies_group_idx
 ON lf_ops.b2b_corporate_group_companies(group_id,status);
-- User identity remains lf_ops.empresa_usuarios.user_id, not a duplicate user system.
-- Legacy empresa_usuarios.company_id must never imply permission for other companies.
CREATE TABLE lf_ops.b2b_user_company_assignments (
 user_id uuid NOT NULL REFERENCES lf_ops.empresa_usuarios(user_id) ON DELETE CASCADE,
 company_id uuid NOT NULL REFERENCES lf_ops.empresas(company_id),
 status text NOT NULL DEFAULT 'CANDIDATO' CHECK(status IN ('CANDIDATO','EN_REVISION','VIGENTE','INACTIVO','ARCHIVADO')),
 source_decision_id text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,company_id)
);
CREATE INDEX b2b_user_company_assignments_company_idx
 ON lf_ops.b2b_user_company_assignments(company_id,status);
-- Company-bound profiles reuse lf_ops.perfiles.
CREATE TABLE lf_ops.b2b_user_company_profiles (
 user_id uuid NOT NULL,
 company_id uuid NOT NULL,
 profile_id bigint NOT NULL REFERENCES lf_ops.perfiles(profile_id),
 status text NOT NULL DEFAULT 'CANDIDATO' CHECK(status IN ('CANDIDATO','EN_REVISION','VIGENTE','INACTIVO','ARCHIVADO')),
 source_decision_id text,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,company_id,profile_id),
 FOREIGN KEY(user_id,company_id)
  REFERENCES lf_ops.b2b_user_company_assignments(user_id,company_id) ON DELETE CASCADE
);
-- Company-bound overrides reuse lf_ops.permisos; explicit user DENY takes precedence.
CREATE TABLE lf_ops.b2b_user_company_permissions (
 user_id uuid NOT NULL,
 company_id uuid NOT NULL,
 permission_id bigint NOT NULL REFERENCES lf_ops.permisos(permission_id),
 access_effect text NOT NULL CHECK(access_effect IN ('ALLOW','DENY')),
 status text NOT NULL DEFAULT 'CANDIDATO' CHECK(status IN ('CANDIDATO','EN_REVISION','VIGENTE','INACTIVO','ARCHIVADO')),
 source_decision_id text,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,company_id,permission_id),
 FOREIGN KEY(user_id,company_id)
  REFERENCES lf_ops.b2b_user_company_assignments(user_id,company_id) ON DELETE CASCADE
);
-- Server-only authority. No direct browser access or operational RLS policy yet.
REVOKE ALL ON
 lf_ops.b2b_corporate_groups,
 lf_ops.b2b_corporate_group_companies,
 lf_ops.b2b_user_company_assignments,
 lf_ops.b2b_user_company_profiles,
 lf_ops.b2b_user_company_permissions
FROM PUBLIC, anon, authenticated;
ALTER TABLE lf_ops.b2b_corporate_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.b2b_corporate_groups FORCE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.b2b_corporate_group_companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.b2b_corporate_group_companies FORCE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.b2b_user_company_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.b2b_user_company_assignments FORCE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.b2b_user_company_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.b2b_user_company_profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.b2b_user_company_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.b2b_user_company_permissions FORCE ROW LEVEL SECURITY;
COMMENT ON TABLE lf_ops.b2b_user_company_assignments IS 'S06 candidate membership only; never grants operating company access without authorized server-side active scope and effective permissions.';
