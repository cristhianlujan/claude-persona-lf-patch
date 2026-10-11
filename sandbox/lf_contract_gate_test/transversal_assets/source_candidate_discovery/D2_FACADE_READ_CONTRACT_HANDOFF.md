# LF D2 facade handoff

This branch contains candidate metadata-only facade request and evidence-receipt readers. No enterprise reads, activation, grants or RLS changes. The proposal remains unmerged until negative tests and a full security review pass. No authenticated actor or company bindings exist in sandbox. The ledger SELECT is denied to service_role; retain fail-closed behavior without privilege escalation.
