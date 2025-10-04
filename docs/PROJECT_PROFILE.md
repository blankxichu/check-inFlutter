# Project Profile (Estado Actual y Lineamientos)

> Fecha: 2025-10-03

## 1. Visión General
Aplicación Flutter para gestión de guardias escolares: asignación de turnos (shifts), registro de asistencia (check-ins IN/OUT) y administración de usuarios. Back-end principal: Firebase (Auth, Firestore, Functions, Messaging, Crashlytics, Storage). 

Capas previstas originalmente:
- Presentation (UI widgets/screens) – mínima lógica, sólo orquestar.
- Application / Use Cases – reglas de negocio, flujos (e.g. construir sesiones IN→OUT, validaciones, exportaciones).
- Domain – entidades puras y contratos (repositorios, value objects).
- Infrastructure – implementación concreta (Firestore, Functions, local cache Hive, geolocalización, etc.).

## 2. Estado Actual (Resumen Breve)
| Área | Situación Actual | Observaciones |
|------|------------------|---------------|
| Check-ins (usuario) | Pantallas separadas (`check_in_page`, `check_in_export_page`) | Lógica ligera de sesiones en export; validación IN→OUT en ViewModel. |
| Admin Dashboard | Archivo grande `admin_dashboard_new.dart` con UI + queries + agregación + export + borrado | Mezcla varias responsabilidades. |
| Repositorios | `FirestoreCheckInRepository`, `FirestoreGeofenceRepository`, repos shift (impl implícita) | Correcto pero falta segmentar queries especializadas. |
| Domain Entities | `CheckIn`, `Shift`, etc. | Simples; falta value objects (TimeRange, Session). |
| Use Cases | `DoCheckIn`, `DoCheckOut` | Otros flujos (aggregate/export/delete) aún embebidos en UI. |
| Export PDF | Implementado en admin y usuario (duplicación parcial) | Reutilizable vía servicio. |
| Seguridad Firestore | Reglas ajustadas para permitir delete a admins | Falta auditoría/soft delete. |
| Caching | Hive para labels de usuario (uso parcial) | Mejor centralizar en servicio `UserLabelCacheService`. |

## 3. Principales Smells Detectados
1. God Widget: `admin_dashboard_new.dart` excede >2k líneas.
2. Duplicación de lógica sesión (admin vs export personal).
3. Queries Firestore repetidas con lógica condicional (retries por índices) incrustada.
4. Formateo de fechas/horas disperso (múltiples funciones privadas).
5. Mezcla de preocupaciones: PDF, borrado, agregación, UI en un mismo scope.
6. Ausencia de tipos semánticos para `Session`, `DurationReport`, `UserLabel`.
7. Falta de capa clara para políticas de negocio (e.g. OUT huérfano). 

## 4. Objetivo de Modularización (Meta)
Mover la lógica de negocio a casos de uso y servicios reutilizables para:
- Facilitar pruebas unitarias sin Flutter.
- Reutilizar export / agregación entre admin y usuario.
- Minimizar regresiones al extender reglas (multi-escuela, roles). 

## 5. Entidades / Value Objects Propuestos
| Nombre | Rol | Campos sugeridos |
|--------|-----|------------------|
| `CheckIn` | Evento atómico | id, userId, timestampUtc, lat, lon, type(IN/OUT) |
| `Session` | Agrega par(es) IN→OUT | dayId, userId?, inTs?, outTs?, inEvents[], outEvents[] |
| `TimeRange` | Genérico para turnos | startUtc, endUtc |
| `ShiftSlot` | Turno asignado | userId, range:TimeRange |
| `DurationReport` | Totales de un rango | totalSessions, totalDuration, openSessions, anomalies |
| `UserLabel` | Etiqueta renderizable | userId, display, emailCacheAt |

## 6. Casos de Uso (Backlog Prioritario)
| Prioridad | Caso de Uso | Descripción | Entrada | Salida |
|-----------|------------|-------------|---------|--------|
| Alta | BuildSessionsFromEvents | Transforma lista de `CheckIn` en sesiones | List<CheckIn> | List<Session> |
| Alta | ComputeDurationReport | Totales (horas, sesiones abiertas, anomalías) | List<Session> | DurationReport |
| Alta | DeleteSession | Elimina eventos de una sesión (valida rol y consistencia) | Session | Result / error |
| Media | ExportSessionsPdf | Genera bytes PDF desde sesiones+reporte | Sessions + Report | Uint8List |
| Media | LookupUserLabel | Obtiene nombre/email con cache y fallback | userId | UserLabel |
| Media | FetchCheckInsRange | Obtiene eventos para rango definido | userId, from, to, limit | List<CheckIn> |
| Baja | DetectAnomalies | Marca out/in huérfanos, duplicados | Sessions | List<Anomaly> |
| Baja | SoftDeleteSession | Mover eventos a subcolección archivada | Session | bool |

## 7. Arquitectura Propuesta (Directorios)
```
lib/
  domain/
    checkin/
      entities/ (CheckIn, Session, DurationReport, etc.)
      repositories/ (check_in_repository.dart)
      value_objects/ (time_range.dart, ...)
    user/
      entities/user_label.dart
  application/
    checkin/
      usecases/
        build_sessions.dart
        compute_duration_report.dart
        delete_session.dart
        export_sessions_pdf.dart
        fetch_checkins_range.dart
    user/
      usecases/lookup_user_label.dart
  infrastructure/
    checkin/
      firestore_check_in_repository.dart
      pdf/
        pdf_export_service.dart
    user/
      user_label_cache_service.dart (Hive + memoria)
  presentation/
    screens/
      admin/
        admin_dashboard_page.dart (delegado)
        widgets/
          sessions_list.dart
          session_actions_bar.dart
      checkin/
        check_in_page.dart
        check_in_export_page.dart (rebajado a orquestador)
```

## 8. Plan de Refactor en Iteraciones
1. Extraer `Session` + `build_sessions.dart` (copiar lógica existente, pruebas unitarias simples).
2. Crear `compute_duration_report.dart` para total horas + sesiones abiertas.
3. Mover export PDF a `pdf_export_service.dart` + caso de uso `export_sessions_pdf.dart`.
4. Abstraer borrado en `delete_session.dart`; UI pasa Session.idList.
5. Reemplazar lógica dentro de admin GUI por providers Riverpod para cada caso de uso.
6. Dividir `admin_dashboard_new.dart` en componentes (lista, filtros, resumen).
7. Introducir `LookupUserLabel` con cache centralizada.
8. Limpieza final: remover funciones duplicadas / helpers locales.

## 9. Criterios de Hecho (Definition of Done)
- Ninguna consulta a Firestore desde widgets: sólo a través de repos/usecases.
- Lógica de sesiones no duplicada en export personal ni admin.
- Archivo admin principal < 400 líneas (solo composición de widgets).
- Pruebas de unidad: BuildSessions (≥4 casos), DurationReport (≥2), DeleteSession (≥2). 
- PDF service probado con conjunto ficticio de sesiones.

## 10. Riesgos y Mitigaciones
| Riesgo | Mitigación |
|--------|-----------|
| Duplicación transitoria durante refactor | Desarrollar caso de uso y redirigir UI antes de borrar vieja lógica |
| Cambios en Firestore indices (orden by + where) | Centralizar queries en repos y documentar índices requeridos |
| Errores de sesión abierta inconclusa | Añadir pruebas para IN consecutivos y OUT huérfanos |
| Crecimiento de PDF (muchas sesiones) | Paginar PDF o dividir por mes si > N filas |

## 11. Métricas a Monitorear (Post Refactor)
- Tiempo de carga de vista admin (ms). 
- Número de líneas en archivos UI clave. 
- Cobertura de pruebas en application/checkin (>70%). 
- Incidencias de “permission-denied” tras deletes (esperado 0). 

## 12. Próximos Extras (Opcionales)
- CSV export service.
- Soft delete con retención (30 días) y restauración.
- Auditoría (Cloud Function onDelete -> escribir en `audit_log`).
- Multi-school: aislar schoolId en providers/inyección.

## 13. Glosario Rápido
| Término | Definición |
|---------|-----------|
| Session | Secuencia IN→OUT (o parcial) en un mismo día local. |
| Out huérfano | Evento OUT sin IN previo en la secuencia. |
| Sesión abierta | IN sin OUT posterior. |
| DurationReport | Agregado de métricas calculadas para un rango. |

## 14. Checklist de Inicio de Refactor
- [ ] Crear entidades `Session`, `DurationReport`.
- [ ] Extraer función BuildSessions a caso de uso.
- [ ] Sustituir en export personal.
- [ ] Sustituir en admin (lista de sesiones).
- [ ] Agregar cálculo de totales centralizado.
- [ ] PDF service reutilizado en ambos contextos.
- [ ] Mover delete a caso de uso.
- [ ] Dividir admin dashboard en sub-widgets.

---
**Nota:** Este perfil sirve como contrato de arquitectura para próximas iteraciones. Ajustar si cambian requisitos (ej. roles adicionales, multi-centro escolar).
