## Lote D — estadísticas de recordatorios (ejercicio 6, modo nativo)

Solo se **agregan** tres archivos nuevos en `apps/time-service/src/main/java/lf/sandbox/time/reminder/`. No se modifica ningún archivo existente.

REM-D1 `public record ReminderStats(int total, java.time.LocalTime earliest, java.time.LocalTime latest, Reminder next, boolean nextIsTomorrow)`.

REM-D2 `@Service public class ReminderStatsService`, con constructor público sin argumentos y `public ReminderStats compute(List<Reminder> reminders, LocalTime now)`:
- `reminders` o `now` null → `IllegalArgumentException`. No modifica la lista recibida (puede ser no modificable).
- Lista vacía → `total=0`, `earliest=null`, `latest=null`, `next=null`, `nextIsTomorrow=false`.
- `now` se trunca a segundos. `earliest`/`latest` = menor/mayor `at`.
- `next` = el recordatorio con el menor `at` que sea **mayor o igual** que `now`; en empate de `at`, el de **menor id**. `nextIsTomorrow=false`.
- Si ninguno es mayor o igual que `now`, `next` = el de menor `at` (empate: menor id) y `nextIsTomorrow=true`.

REM-D3 `@RestController ReminderStatsController` con `GET /api/reminders/stats`:
- Recibe **por constructor** `ReminderRepository`, `ReminderStatsService` y `java.time.Clock` (sin `@Autowired`, sin `new`).
- Usa `repository.findAll()` y `LocalTime.now(clock)` (prohibido `LocalTime.now()` sin reloj u otro reloj del sistema).
- Responde 200 con exactamente estas claves: `{"total":N,"earliest":"HH:mm:ss"|null,"latest":"HH:mm:ss"|null,"next":{"id":N,"text":"...","at":"HH:mm:ss"}|null,"nextIsTomorrow":bool}`. Las horas siempre con el formato exacto `HH:mm:ss`, también cuando los segundos son cero.
- Las rutas existentes (`/api/reminders`, `/api/reminders/{id}`, `/api/time`) siguen igual; otros métodos sobre `/api/reminders/stats` → 405.

REM-D4 La prueba visible está en `apps/time-service/visible-tests/ex6/` (fuera de `src/test` a propósito, para no romper el CI de `main` antes de que exista el código). Formato del código: norma AOSP de este documento.
