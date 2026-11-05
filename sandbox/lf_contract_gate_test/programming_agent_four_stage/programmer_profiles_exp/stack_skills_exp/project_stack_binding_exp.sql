-- LOCAL POSTGRESQL ONLY. Execute solely after selector_exp_test_* localhost guard.
-- The binding chooses the skill by (project_ref,area), NOT by profile name or AI output.
CREATE TABLE public.project_stack_binding_exp (
 project_ref text NOT NULL,
 area text NOT NULL CHECK (area IN ('BACKEND','FRONTEND','DATA')),
 skill_code text NOT NULL,
 skill_sha256 text NOT NULL CHECK (skill_sha256 ~ '^[0-9a-f]{64}$'),
 PRIMARY KEY (project_ref,area)
);
-- Seed rows are added by seed_local_project_stack_bindings() from exact SKILL.md content
-- and then read back from this TABLE by the PG-07 bridge (not by a mapping in the role).
