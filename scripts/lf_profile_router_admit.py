#!/usr/bin/env python3
"""Retired: Router ACT-0001 is derivation-only and cannot invoke a profile.

No fallback or intermediate bridge is permitted. Profile execution belongs
to the existing EJECUCION_PERFIL_LF governed operation, not this Router tool.
"""
import sys


def main():
    print("::error title=ROUTER_PROFILE_DIRECT_CALL_RETIRED::"
          "ROUTER_ONLY_DERIVATION_NO_PROFILE_EXECUTION")
    return 1


if __name__ == "__main__":
    sys.exit(main())
