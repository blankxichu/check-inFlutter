Calendar Module (Asignación por Admin)

Domain
- Shift: id, date (UTC day), userId, capacity.
- ShiftRepository: watchMonth, getRange. (reserve/cancel quedan para compatibilidad, pero la app no los usa)
- Use cases: GetShifts.

Data
- FirestoreShiftRepository: collection 'shifts', doc id 'yyyy-MM-dd'.
  Fields: date (Timestamp UTC), users (array of uid), capacity (int). Transactions for reserve/cancel.

Presentation
- CalendarViewModel (Riverpod Notifier) calcula ocupación por día y marca los días asignados al usuario actual.
- CalendarPage (TableCalendar) muestra los días asignados al usuario (resaltados) y la ocupación; no permite reservar.

Notes
- Fallback in-memory repo enables local runs without Firebase.
- Capacidad default=2; puede ajustarse en documento del día (campo capacity).

Administración
- Nueva Cloud Function callable: assignShift { email|uid, day: 'yyyy-MM-dd', action: 'assign'|'unassign' }
- Panel de Admin incluye un formulario para asignar o quitar guardias por email y fecha (admite múltiples fechas separadas por coma).
