# SECURITY S1-C01 — paquete para juicio Claude

Fuente legada 22 `REG_SEG_004`, OTP hash en producción. No duplicar M4-C01 (DNI logs), M4-C02 (sesión URL) ni M4-C03 (OTP API). Hechos tipados booleanos sin binding runtime. Condición: intento AND producción AND falta hash.

| Caso | Intento | Producción | Sin hash | Bloquear |
|---|---:|---:|---:|---:|
| Prod, intenta persistir OTP sin hash | true | true | true | true |
| Prod, OTP hash presente | true | true | false | false |
| Sandbox, OTP sin hash | true | false | true | false |
| Prod, no hay intento | false | true | true | false |
| Prod, intento OTP sin hash repetido | true | true | true | true |
| Sandbox, sin intento | false | false | true | false |
| Prod, sin violación | true | true | false | false |
| Sandbox, OTP hasheado | true | false | false | false |

No se promueve: requiere juicio independiente sobre hash canónico del paquete.
