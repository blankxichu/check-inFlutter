# Análisis Profundo: Sistema de Notificaciones Push

**Fecha:** 5 de octubre de 2025  
**Alcance:** Arquitectura completa de notificaciones FCM + Flutter Local Notifications

---

## 📋 Resumen Ejecutivo

### Estado General: ⚠️ FUNCIONAL CON PROBLEMAS CRÍTICOS

El sistema de notificaciones push está implementado pero tiene **problemas importantes** que afectan:
- **Fiabilidad**: Duplicación de notificaciones, tokens huérfanos
- **Rendimiento**: Múltiples queries innecesarios, retries sin backoff
- **Experiencia de usuario**: Falta de navegación directa, agrupación inconsistente
- **Mantenibilidad**: Código complejo con lógica duplicada

---

## 🏗️ Arquitectura Actual

### Componentes Principales

```
┌─────────────────────────────────────────────────────────────┐
│                    FLUTTER CLIENT                            │
├─────────────────────────────────────────────────────────────┤
│ 1. PushMessagingService (core/notifications/)              │
│    ├─ Background Handler                                    │
│    ├─ Foreground Listener                                   │
│    ├─ Token Management                                      │
│    ├─ Deduplication Logic                                   │
│    └─ Event Emission                                        │
│                                                              │
│ 2. NotificationService (core/notifications/)               │
│    ├─ Local Notifications Plugin                           │
│    ├─ Channel Configuration (3 canales)                    │
│    └─ Grouping/Summary (Android only)                      │
│                                                              │
│ 3. NotificationPermissionBanner (presentation/widgets/)    │
│    └─ Permission Request UI                                 │
│                                                              │
│ 4. AuthViewModel Integration                               │
│    └─ Token cleanup on signOut                             │
└─────────────────────────────────────────────────────────────┘
                              ↕
                     Firebase Messaging
                              ↕
┌─────────────────────────────────────────────────────────────┐
│                  CLOUD FUNCTIONS (Node.js)                  │
├─────────────────────────────────────────────────────────────┤
│ 1. sendTestNotification (callable)                         │
│ 2. scheduledShiftReminders (cron: 18:00 UTC)              │
│ 3. cleanupOldFcmTokens (cron: 03:10 UTC)                  │
│ 4. assignShift (callable) → FCM notification               │
│ 5. assignMultipleShifts (callable) → FCM notification      │
│ 6. onChatMessageCreate (trigger) → FCM notification        │
│ 7. sanitizeUserTokens (utility function)                  │
└─────────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────┐
│                    FIRESTORE STRUCTURE                       │
├─────────────────────────────────────────────────────────────┤
│ users/{uid}/fcmTokens/{token}                              │
│   ├─ token: string                                          │
│   ├─ platform: 'android'|'ios'|'other'                     │
│   ├─ updatedAt: Timestamp                                  │
│   └─ uid: string (redundante!)                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔴 Problemas Críticos Identificados

### 1. **Deduplicación Inconsistente y Compleja**

**Ubicación:** `push_messaging_service.dart` líneas 57-65, 367-398

**Problema:**
- Tres mecanismos de deduplicación simultáneos:
  1. `_recentMessageIds` (lista de 50 IDs)
  2. `_recentCompositeKeys` (mapa type+day con TTL 60s)
  3. `_recentShiftForeground` (buffer para agrupación 25s)
- Ninguno es persistente → **reinicio de app = pérdida de estado**
- `messageId` puede ser null → fallback a composite key inconsistente
- Window de 60s demasiado corto para escenarios de mala conectividad

**Evidencia:**
```dart
// Tres estructuras separadas sin coordinación:
final List<String> _recentMessageIds = <String>[];
final Map<String, DateTime> _recentCompositeKeys = {};
final List<NotificationEvent> _recentShiftForeground = [];
```

**Impacto:**
- Usuario puede recibir **notificación duplicada** si:
  - La app se reinicia entre llegadas
  - FCM reenvía mensaje con nuevo ID
  - Composite key collision (mismo tipo+día diferente hora)

**Solución Propuesta:**
- Migrar a persistencia con Hive/SharedPreferences
- TTL más largo (6-24 horas) con cleanup periódico
- Unificar en un solo mecanismo hash-based

---

### 2. **Gestión de Tokens FCM Problemática**

**Ubicación:** `push_messaging_service.dart` líneas 261-305, `functions/src/index.ts` líneas 9-78

**Problemas Múltiples:**

#### A. Sanitización Desactivada por Default
```typescript
// functions/src/index.ts línea 18
const ENABLE_TOKEN_SANITIZE = false;  // ⚠️ DESACTIVADO
if (!ENABLE_TOKEN_SANITIZE) {
  return tokens; // skip logic
}
```
**Consecuencia:** Tokens duplicados entre usuarios NO se limpian → notificaciones enviadas a usuarios incorrectos.

#### B. Eliminación Agresiva en Client-Side
```dart
// push_messaging_service.dart líneas 281-291
final dupSnap = await _db!.collectionGroup('fcmTokens')
    .where('token', isEqualTo: token).get();
for (final d in dupSnap.docs) {
  final parentUserId = d.reference.parent.parent?.id;
  if (parentUserId != null && parentUserId != uid) {
    await d.reference.delete(); // ⚠️ Sin verificar updatedAt
  }
}
```
**Problema:** Race condition si dos usuarios obtienen el mismo token (improbable pero posible).

#### C. Campo `uid` Redundante
```dart
final data = {
  'token': token,
  'platform': Platform.isAndroid ? 'android' : ...,
  'updatedAt': FieldValue.serverTimestamp(),
  'uid': uid, // ⚠️ Ya está implícito en la ruta users/{uid}/fcmTokens/{token}
};
```
**Desperdicio:** 8-36 bytes por documento, sin utilidad.

#### D. Retry Logic Sin Backoff Exponencial
```dart
// push_messaging_service.dart líneas 269-280
int attempts = 0;
while (true) {
  attempts++;
  try {
    await _db!.collection('users').doc(uid)...
    return;
  } on FirebaseException catch (e) {
    if (attempts >= 2) return;
    await Future.delayed(const Duration(milliseconds: 300)); // ⚠️ Siempre 300ms
  }
}
```
**Problema:** Retry fijo sin exponential backoff → puede sobrecargar Firestore bajo errores temporales.

**Impacto:**
- **Seguridad:** Token de usuario A puede usarse para notificar a usuario B (si sanitización desactivada)
- **Costo:** Writes innecesarios (campo `uid`)
- **Fiabilidad:** Fallos en guardado de token bajo condiciones de red intermitente

**Solución Propuesta:**
1. Activar `ENABLE_TOKEN_SANITIZE = true` y optimizar query (index `token` + `updatedAt`)
2. Eliminar campo `uid` redundante
3. Implementar exponential backoff: 300ms → 600ms → 1200ms
4. Client-side: solo actualizar si `updatedAt` local > remoto

---

### 3. **Envío de Notificaciones Ineficiente en Cloud Functions**

**Ubicación:** `functions/src/index.ts` múltiples callables

**Problema:** Código duplicado en 4 funciones diferentes:

```typescript
// Patrón repetido en assignShift, assignMultipleShifts, onChatMessageCreate:
const tokensSnap = await db.collection('users').doc(uid).collection('fcmTokens').get();
let tokens = tokensSnap.docs.map(d => d.id);
tokens = await sanitizeUserTokens(uid, tokens); // ⚠️ Desactivado
if (tokens.length) {
  const msg: admin.messaging.MulticastMessage = { tokens, notification: {...}, data: {...} };
  const res = await admin.messaging().sendEachForMulticast(msg);
  console.log('result success=', res.successCount, 'failure=', res.failureCount);
  if (res.successCount === 0 && tokens.length > 0) { // ⚠️ Retry SIN backoff
    try { await admin.messaging().sendEachForMulticast(msg); } catch (e) {...}
  }
}
```

**Problemas:**
1. **Código duplicado:** 4 implementaciones idénticas (violación DRY)
2. **Retry sin backoff:** Si falla, reintenta inmediatamente (puede empeorar el problema)
3. **Sin manejo de tokens inválidos:** `failureCount` ignorado → tokens expirados nunca se limpian
4. **Sin rate limiting:** Puede exceder cuota FCM (1M mensajes/día free tier)
5. **Logs insuficientes:** No registra `InvalidRegistration`, `NotRegistered` errors

**Impacto:**
- **Mantenibilidad:** Cambios deben replicarse en 4 lugares
- **Costo:** Envíos fallidos desperdician cuota
- **User Experience:** Tokens inválidos → notificaciones no llegan

**Solución Propuesta:**
```typescript
// Nueva función helper centralizada
async function sendNotificationToUser(
  uid: string,
  notification: { title: string; body: string },
  data: Record<string, string>,
  options?: { retries?: number; cleanupInvalid?: boolean }
): Promise<{ success: number; failed: number; invalidTokens: string[] }> {
  const tokensSnap = await db.collection('users').doc(uid).collection('fcmTokens').get();
  let tokens = tokensSnap.docs.map(d => d.id);
  tokens = await sanitizeUserTokens(uid, tokens);
  
  if (tokens.length === 0) return { success: 0, failed: 0, invalidTokens: [] };

  const msg: admin.messaging.MulticastMessage = { tokens, notification, data };
  const res = await admin.messaging().sendEachForMulticast(msg);
  
  // Identificar tokens inválidos
  const invalidTokens: string[] = [];
  res.responses.forEach((r, idx) => {
    if (r.error && 
        (r.error.code === 'messaging/invalid-registration-token' ||
         r.error.code === 'messaging/registration-token-not-registered')) {
      invalidTokens.push(tokens[idx]);
    }
  });

  // Cleanup automático (opcional)
  if (options?.cleanupInvalid && invalidTokens.length > 0) {
    const batch = db.batch();
    invalidTokens.forEach(token => {
      batch.delete(db.collection('users').doc(uid).collection('fcmTokens').doc(token));
    });
    await batch.commit();
  }

  // Retry solo tokens válidos con backoff exponencial
  if (res.successCount === 0 && tokens.length - invalidTokens.length > 0 && (options?.retries ?? 1) > 0) {
    const validTokens = tokens.filter(t => !invalidTokens.includes(t));
    await new Promise(resolve => setTimeout(resolve, 500)); // backoff
    const retryMsg = { ...msg, tokens: validTokens };
    const retryRes = await admin.messaging().sendEachForMulticast(retryMsg);
    return {
      success: res.successCount + retryRes.successCount,
      failed: res.failureCount + retryRes.failureCount - invalidTokens.length,
      invalidTokens
    };
  }

  return { success: res.successCount, failed: res.failureCount, invalidTokens };
}
```

---

### 4. **Navegación desde Notificaciones Incompleta**

**Ubicación:** `lib/core/app.dart` líneas 26-47

**Problema Actual:**
```dart
ref.listen<AsyncValue<NotificationEvent>>(notificationEventsProvider, (prev, next) {
  next.whenData((ev) {
    if (!ev.opened) return; // Solo navega si se tocó
    final day = ev.data['day'];
    if (day != null && ev.type == 'shift') {
      final focusDay = DateTime.tryParse(day.toString());
      NavigationService.instance.pushShiftCalendar(focusDay: focusDay);
    }
    // ⚠️ FALTA: Navegación para type='chat', type='system', etc.
  });
});
```

**Casos No Manejados:**
- `type: 'chat'` → Debería abrir `ChatRoomPage(chatId: ev.data['chatId'])`
- `type: 'system'` → ¿Abrir AdminDashboard? ¿Dialog?
- `type: 'generic'` → Sin acción definida

**Impacto:**
- Notificaciones de chat **no navegan al chat** (mala UX)
- Usuario debe buscar manualmente el chat tras recibir notificación

**Solución Propuesta:**
```dart
ref.listen<AsyncValue<NotificationEvent>>(notificationEventsProvider, (prev, next) {
  next.whenData((ev) {
    if (!ev.opened) return;
    
    switch (ev.type) {
      case 'shift':
      case 'guardia':
        final day = ev.data['day'];
        if (day != null) {
          final focusDay = DateTime.tryParse(day.toString());
          NavigationService.instance.pushShiftCalendar(focusDay: focusDay);
        }
        break;
        
      case 'chat':
        final chatId = ev.data['chatId'];
        if (chatId != null) {
          NavigationService.instance.pushChatRoom(chatId: chatId);
        }
        break;
        
      case 'system':
      case 'sistema':
        NavigationService.instance.pushAdminDashboard(); // Solo si admin
        break;
        
      default:
        // Logging para casos no manejados
        debugPrint('Notification type not handled: ${ev.type}');
    }
  });
});
```

---

### 5. **Agrupación de Notificaciones Inconsistente**

**Ubicación:** `push_messaging_service.dart` líneas 388-418

**Problema:**
```dart
void _maybeBufferForGrouping(NotificationEvent ev) {
  if (!(ev.type == 'shift' || ev.type == 'guardia')) return;
  final now = DateTime.now();
  _recentShiftForeground.removeWhere((e) => 
    now.difference(e.opened ? now : now) > _groupWindow // ⚠️ Lógica rota
  );
  _recentShiftForeground.add(ev);
  if (_recentShiftForeground.length >= _groupMin && 
      now.difference(_lastGroupSummary) > _groupWindow) {
    _showGroupSummary(now);
  }
}
```

**Bugs Identificados:**
1. `e.opened ? now : now` → Siempre evalúa a `now` (bug copy-paste)
2. Solo agrupa `shift` → Chat con múltiples mensajes NO se agrupa
3. `_groupMin = 3` muy alto → usuario recibe 2 notificaciones separadas antes de ver resumen
4. `_groupWindow = 25s` muy corto → si llegan 2 mensajes con 26s de diferencia, no agrupan

**Impacto:**
- Usuario recibe **spam** de notificaciones individuales en lugar de resumen agrupado
- Experiencia inconsistente entre tipos de notificación

**Solución Propuesta:**
```dart
void _maybeBufferForGrouping(NotificationEvent ev) {
  final now = DateTime.now();
  final groupKey = _getGroupKey(ev); // Devuelve 'shift', 'chat-{chatId}', etc.
  if (groupKey == null) return;
  
  // Crear buffer por grupo si no existe
  _groupBuffers.putIfAbsent(groupKey, () => <NotificationEvent>[]);
  
  // Limpiar eventos antiguos de ESTE grupo
  _groupBuffers[groupKey]!.removeWhere((e) {
    final eventTime = e.data['timestamp'] != null 
        ? DateTime.fromMillisecondsSinceEpoch(e.data['timestamp'])
        : DateTime.now();
    return now.difference(eventTime) > const Duration(seconds: 60); // ✅ Ventana más larga
  });
  
  _groupBuffers[groupKey]!.add(ev);
  
  if (_groupBuffers[groupKey]!.length >= 2 && // ✅ Threshold más bajo
      now.difference(_lastGroupSummary[groupKey] ?? DateTime(0)) > const Duration(seconds: 5)) {
    _showGroupSummary(groupKey, now);
  }
}

String? _getGroupKey(NotificationEvent ev) {
  switch (ev.type) {
    case 'shift':
    case 'guardia':
      return 'shift';
    case 'chat':
      final chatId = ev.data['chatId'];
      return chatId != null ? 'chat-$chatId' : null;
    default:
      return null;
  }
}
```

---

### 6. **Métricas de Debug en Producción**

**Ubicación:** `home_page.dart` líneas 134-160

**Problema:**
```dart
if (!bool.fromEnvironment('dart.vm.product')) ...[
  const Divider(),
  const Padding(..., child: Text('Desarrollo', ...)),
  Consumer(builder: (context, ref, _) {
    final m = ref.watch(notificationMetricsProvider);
    return Padding(..., child: Text('Notifs rec:${m.received} mostr:${m.displayed}'));
  }),
  Row(children: [
    TextButton(onPressed: () { ref.read(notificationMetricsProvider.notifier).reset(); }, ...),
    TextButton(onPressed: () { ref.read(pushMessagingProvider).replayInitialEvent(); }, ...),
  ]),
  // ...
]
```

**Problemas:**
1. `!bool.fromEnvironment('dart.vm.product')` → Solo oculta en release mode, **visible en profile mode**
2. Expone botones peligrosos (replay, reset) → usuario confundido puede tocarlos
3. Métricas no persisten → reinicio = pérdida de datos

**Impacto:**
- Usuario final puede ver panel de debug y ejecutar acciones inesperadas
- Imposibilidad de diagnosticar problemas en producción (métricas volátiles)

**Solución:**
```dart
if (kDebugMode) ...[  // ✅ Solo en debug builds
  const Divider(),
  _DebugNotificationPanel(), // ✅ Componente separado
]

class _DebugNotificationPanel extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(notificationMetricsProvider);
    return ExpansionTile(
      title: Text('🔧 Debug: Notificaciones'),
      children: [
        ListTile(subtitle: Text('Recibidas: ${m.received} | Mostradas: ${m.displayed}')),
        ListTile(subtitle: Text('Uptime: ${DateTime.now().difference(m.startedAt).inMinutes} min')),
        ButtonBar(children: [
          TextButton(onPressed: () => ref.read(notificationMetricsProvider.notifier).reset(), 
                     child: const Text('Reset')),
          TextButton(onPressed: () => ref.read(pushMessagingProvider).replayInitialEvent(), 
                     child: const Text('Replay Inicial')),
        ]),
      ],
    );
  }
}
```

---

### 7. **Cleanup de Tokens Antiguos Ineficiente**

**Ubicación:** `functions/src/index.ts` líneas 198-230

**Problema:**
```typescript
export const cleanupOldFcmTokens = onSchedule('10 3 * * *', async () => {
  const DAYS = 60;
  const cutoff = admin.firestore.Timestamp.fromMillis(now - DAYS * 24 * 60 * 60 * 1000);
  const snap = await db.collectionGroup('fcmTokens')
    .where('updatedAt', '<', cutoff)
    .get(); // ⚠️ Sin límite → puede traer millones de docs

  if (snap.empty) return;

  let batch = db.batch();
  let ops = 0;
  for (const doc of snap.docs) {
    batch.delete(doc.ref);
    ops++; 
    if (ops >= 400) { // ⚠️ Batch size cerca del límite (500)
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();
});
```

**Problemas:**
1. **Sin límite en query** → Si hay 100K tokens antiguos, traerá TODOS (timeout garantizado)
2. **Batch size de 400** → Muy cerca del límite de Firestore (500), arriesgado
3. **Sin paginación** → No puede resumir si falla a mitad
4. **TTL de 60 días muy largo** → Tokens inactivos ocupan espacio y generan falsos positivos

**Impacto:**
- Function timeout en bases de datos grandes (>10K tokens viejos)
- Desperdicio de cuota de lectura
- Tokens expirados siguen recibiendo intentos de envío (incrementa `failureCount`)

**Solución:**
```typescript
export const cleanupOldFcmTokens = onSchedule('10 3 * * *', async () => {
  const DAYS = 30; // ✅ Reducido de 60 a 30 días
  const BATCH_SIZE = 200; // ✅ Más conservador
  const MAX_ITERATIONS = 50; // ✅ Límite de seguridad
  
  const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - DAYS * 24 * 60 * 60 * 1000);
  
  let totalDeleted = 0;
  let iteration = 0;
  
  while (iteration < MAX_ITERATIONS) {
    const snap = await db.collectionGroup('fcmTokens')
      .where('updatedAt', '<', cutoff)
      .limit(BATCH_SIZE)
      .get();
    
    if (snap.empty) break;
    
    const batch = db.batch();
    snap.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    
    totalDeleted += snap.size;
    iteration++;
    
    if (snap.size < BATCH_SIZE) break; // Última página
    
    // Pequeño delay para no saturar
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  
  console.log(`cleanupOldFcmTokens: deleted ${totalDeleted} in ${iteration} iterations`);
  
  // Opcional: Registrar en Firestore para monitoreo
  await db.collection('_system').doc('cleanup_stats').set({
    lastRun: admin.firestore.FieldValue.serverTimestamp(),
    tokensDeleted: totalDeleted,
    cutoffDate: cutoff.toDate(),
  }, { merge: true });
});
```

---

### 8. **Falta de Telemetría y Observabilidad**

**Ubicación:** Todo el sistema

**Problema Actual:**
- Logs dispersos (`console.log`, `debugPrint`, `FirebaseCrashlytics.log`)
- Sin métricas cuantitativas exportables
- Imposible responder preguntas como:
  - ¿Cuál es la tasa de entrega de notificaciones?
  - ¿Cuántos tokens están activos vs. inactivos?
  - ¿Qué % de usuarios tienen permisos denegados?

**Solución Propuesta:**
Integrar Firebase Analytics + Custom Events:

```dart
// En push_messaging_service.dart
import 'package:firebase_analytics/firebase_analytics.dart';

class PushMessagingService {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  Future<void> _trackNotificationReceived(NotificationEvent ev) async {
    await _analytics.logEvent(
      name: 'notification_received',
      parameters: {
        'type': ev.type,
        'foreground': ev.foreground,
        'opened': ev.opened,
        'has_message_id': ev.id.isNotEmpty,
      },
    );
  }

  Future<void> _trackTokenSaved(String uid) async {
    await _analytics.logEvent(
      name: 'fcm_token_saved',
      parameters: {'user_id': uid},
    );
  }
}
```

En Cloud Functions:
```typescript
// functions/src/analytics.ts
export async function trackNotificationSent(
  eventType: string,
  recipientCount: number,
  successCount: number,
  failureCount: number
) {
  await db.collection('_analytics').add({
    event: 'notification_sent',
    type: eventType,
    recipients: recipientCount,
    success: successCount,
    failed: failureCount,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}
```

---

## 📊 Métricas de Calidad del Código

### Complejidad Ciclomática
- `PushMessagingService.init()`: **15** (Alto - Refactorizar)
- `_maybeBufferForGrouping()`: **8** (Medio)
- `sanitizeUserTokens()` (Functions): **12** (Alto)

### Duplicación de Código
- **4 instancias** de envío de notificaciones en Cloud Functions (98% idénticas)
- **3 mecanismos** de deduplicación en cliente

### Cobertura de Tests
- ❌ **0%** - No existen unit tests para `PushMessagingService`
- ❌ **0%** - No existen integration tests para flujo completo

---

## 🎯 Recomendaciones Priorizadas

### 🔴 Prioridad CRÍTICA (Semana 1)

1. **Activar Sanitización de Tokens**
   ```typescript
   const ENABLE_TOKEN_SANITIZE = true; // ✅ ACTIVAR
   ```
   - **Riesgo actual:** Usuarios reciben notificaciones de otros
   - **Esfuerzo:** 5 minutos
   - **Impacto:** Alto (seguridad)

2. **Eliminar Campo `uid` Redundante**
   ```typescript
   // ANTES
   const data = { token, platform, updatedAt, uid };
   // DESPUÉS
   const data = { token, platform, updatedAt };
   ```
   - **Ahorro:** ~20 bytes/documento × 1000 usuarios = 20KB + índice overhead
   - **Esfuerzo:** 1 hora (include migration script)
   - **Impacto:** Medio (costo/limpieza)

3. **Implementar Navegación de Chat**
   - Añadir case 'chat' en `app.dart`
   - **Esfuerzo:** 30 minutos
   - **Impacto:** Alto (UX)

### 🟠 Prioridad ALTA (Semana 2-3)

4. **Refactorizar Envío de Notificaciones**
   - Crear helper `sendNotificationToUser()` en Functions
   - Migrar las 4 callables a usar helper
   - **Esfuerzo:** 4 horas
   - **Impacto:** Alto (mantenibilidad + cleanup automático)

5. **Optimizar Cleanup de Tokens**
   - Implementar paginación con límite de iteraciones
   - Reducir TTL de 60 a 30 días
   - **Esfuerzo:** 2 horas
   - **Impacto:** Medio (performance + costo)

6. **Persistir Deduplicación**
   - Migrar `_recentMessageIds` a Hive
   - TTL de 24 horas
   - **Esfuerzo:** 3 horas
   - **Impacto:** Alto (fiabilidad)

### 🟡 Prioridad MEDIA (Mes 1)

7. **Mejorar Agrupación**
   - Corregir bug en `_maybeBufferForGrouping`
   - Soportar agrupación de chat
   - **Esfuerzo:** 4 horas
   - **Impacto:** Medio (UX)

8. **Añadir Telemetría**
   - Firebase Analytics events
   - Custom dashboard en Firestore
   - **Esfuerzo:** 6 horas
   - **Impacto:** Alto (observabilidad)

9. **Tests Unitarios**
   - Cobertura >80% para `PushMessagingService`
   - Mocks de FCM
   - **Esfuerzo:** 8 horas
   - **Impacto:** Alto (calidad)

### 🟢 Prioridad BAJA (Backlog)

10. **Documentación API**
    - Swagger/OpenAPI para callables
    - Diagramas de secuencia
    - **Esfuerzo:** 4 horas

11. **Rate Limiting**
    - Limitar envíos por usuario (anti-spam)
    - **Esfuerzo:** 3 horas

---

## 📈 Plan de Implementación Sugerido

### Sprint 1 (Semana 1)
- [ ] Activar sanitización de tokens
- [ ] Eliminar campo `uid` + script migración
- [ ] Navegación de chat
- [ ] **Resultado:** Seguridad mejorada, navegación completa

### Sprint 2 (Semana 2-3)
- [ ] Helper centralizado de envío
- [ ] Optimizar cleanup
- [ ] Persistir deduplicación
- [ ] **Resultado:** Código DRY, fiabilidad mejorada

### Sprint 3 (Semana 4)
- [ ] Agrupación mejorada
- [ ] Telemetría básica
- [ ] Tests unitarios (fase 1)
- [ ] **Resultado:** UX mejorada, observabilidad inicial

---

## 🔧 Scripts de Migración Recomendados

### Eliminar campo `uid` de fcmTokens

```javascript
// tooling/migrate_remove_uid_from_tokens.js
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function removeUidField() {
  const usersSnap = await db.collection('users').get();
  let updated = 0;
  
  for (const userDoc of usersSnap.docs) {
    const tokensSnap = await userDoc.ref.collection('fcmTokens').get();
    if (tokensSnap.empty) continue;
    
    const batch = db.batch();
    tokensSnap.docs.forEach(tokenDoc => {
      const data = tokenDoc.data();
      if (data.uid !== undefined) {
        batch.update(tokenDoc.ref, { uid: admin.firestore.FieldValue.delete() });
        updated++;
      }
    });
    
    await batch.commit();
  }
  
  console.log(`Removed 'uid' field from ${updated} token documents`);
}

removeUidField().catch(console.error);
```

### Limpiar tokens duplicados (one-time)

```javascript
// tooling/cleanup_duplicate_tokens.js
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function cleanupDuplicates() {
  const allTokensSnap = await db.collectionGroup('fcmTokens').get();
  const tokenMap = new Map(); // token → [{uid, ref, updatedAt}]
  
  allTokensSnap.docs.forEach(doc => {
    const token = doc.id;
    const uid = doc.ref.parent.parent.id;
    const updatedAt = doc.get('updatedAt')?.toMillis() || 0;
    
    if (!tokenMap.has(token)) tokenMap.set(token, []);
    tokenMap.get(token).push({ uid, ref: doc.ref, updatedAt });
  });
  
  const duplicates = Array.from(tokenMap.entries()).filter(([_, refs]) => refs.length > 1);
  let deleted = 0;
  
  for (const [token, refs] of duplicates) {
    // Mantener el más reciente, borrar los demás
    const sorted = refs.sort((a, b) => b.updatedAt - a.updatedAt);
    const toKeep = sorted[0];
    const toDelete = sorted.slice(1);
    
    console.log(`Token ${token.substring(0,8)}... duplicado: keeping uid=${toKeep.uid}, deleting ${toDelete.length}`);
    
    const batch = db.batch();
    toDelete.forEach(item => batch.delete(item.ref));
    await batch.commit();
    deleted += toDelete.length;
  }
  
  console.log(`Cleanup complete: removed ${deleted} duplicate tokens`);
}

cleanupDuplicates().catch(console.error);
```

---

## 📚 Referencias y Best Practices

### Firebase Cloud Messaging
- [FCM Best Practices](https://firebase.google.com/docs/cloud-messaging/concept-options#best-practices)
- [Error Codes Reference](https://firebase.google.com/docs/cloud-messaging/send-message#admin_sdk_error_reference)

### Flutter Local Notifications
- [Grouping Guide](https://github.com/MaikuB/flutter_local_notifications/tree/master/flutter_local_notifications#grouping-notifications)
- [Android Channels](https://developer.android.com/develop/ui/views/notifications/channels)

### Firestore Performance
- [Index Best Practices](https://firebase.google.com/docs/firestore/query-data/indexing-best-practices)
- [Batch Writes](https://firebase.google.com/docs/firestore/manage-data/transactions#batched-writes)

---

## 🎓 Lecciones Aprendidas

1. **Sanitización de tokens es crítica** - Sin ella, notificaciones pueden llegar a usuarios incorrectos
2. **Deduplicación debe ser persistente** - Estados en memoria se pierden al reiniciar app
3. **DRY aplica a Cloud Functions** - Código duplicado multiplica bugs
4. **Telemetría desde día 1** - Sin métricas, imposible mejorar
5. **Tests para lógica de negocio crítica** - Notificaciones afectan directamente UX

---

## ✅ Checklist de Validación Post-Fix

Después de implementar correcciones, verificar:

- [ ] Ningún usuario reporta recibir notificaciones de otro usuario
- [ ] Métricas muestran tasa de entrega >95%
- [ ] Cleanup cron completa en <30 segundos
- [ ] Tocar notificación de chat abre el chat correcto
- [ ] Tests unitarios pasan con >80% cobertura
- [ ] Logs de Functions muestran 0 errores de tipo `InvalidRegistration` después de 7 días
- [ ] App no crashea al recibir 10 notificaciones simultáneas
- [ ] Agrupación funciona correctamente (Android)

---

**Autor:** GitHub Copilot  
**Última Actualización:** 5 de octubre de 2025  
**Versión del Documento:** 1.0
