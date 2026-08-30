#!/usr/bin/env python3
from __future__ import annotations

import run_c3_core_cases_v3 as c3v3
import run_c3_family_cases as family

family.c3v2 = c3v3
family.core = c3v3.core
family.base = c3v3.base

if __name__ == '__main__':
    raise SystemExit(family.main())
