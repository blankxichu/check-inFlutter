# Chat & Búsqueda: Pasos de Deploy y Migración

Esta guía resume los pasos para desplegar las últimas funciones (chat, presencia, búsqueda normalizada) y ejecutar la migración del campo `normalizedSearch` en `users`.

## 1. Requisitos previos
- Tener Firebase CLI logueado (`firebase login`).
- Estar en el directorio raíz del proyecto (`guardias_escolares`).
- Haber instalado dependencias de Functions si cambiaste algo: dentro de `functions/` ejecutar `npm install` (ya deberían existir).

## 2. Desplegar reglas actualizadas (lectura de users ampliada temporalmente)
```bash
firebase deploy --only firestore:rules
```

## 3. Desplegar índices (ya ejecutado si ves SUCCESS, repetir si dudas)
```bash
firebase deploy --only firestore:indexes
```

## 4. Compilar y desplegar Cloud Functions
```bash
cd functions
npm run build
firebase deploy --only functions
cd ..
```

Funciones nuevas/relevantes:
- `normalizeUserSearch` (trigger onWrite users/*)
- `migrateNormalizedSearchUsers` (callable)
- `onChatMessageCreate` (ya existente si lo habías desplegado antes)

## 5. Ejecutar migración de `normalizedSearch`
Usa un script rápido (Node shell, consola web, o desde app admin) para invocar la callable:

Ejemplo usando Firebase JS SDK (en consola del navegador autenticado como admin):
```js
firebase.functions().httpsCallable('migrateNormalizedSearchUsers')().then(r => console.log(r.data));
```

o con `curl` (requiere token ID de un admin):
1. Obtén un ID token (p.ej. desde app) y exporta:
```bash
ID_TOKEN="<ID_TOKEN_ADMIN>"
```
2. Invoca endpoint (ajusta REGION si no es default):
```bash
curl -X POST \
  -H "Authorization: Bearer $ID_TOKEN" \
  -H "Content-Type: application/json" \
  https://us-central1-<PROJECT_ID>.cloudfunctions.net/migrateNormalizedSearchUsers \
  -d '{}'
```

La respuesta debería incluir `{ ok: true, examined, updated }`.

## 6. Probar búsqueda server-side
En la app, en selector de usuarios, escribe >=2 caracteres. Debes ver resultados sin errores PERMISSION_DENIED.

## 7. Verificar presencia
- Abrir la app con un usuario A y otro dispositivo con usuario B.
- Usuario A debería ver "En línea" para B mientras la app está en foreground + heartbeat.

## 8. (Opcional) Revertir política de lectura amplia de usuarios
Si deseas restringir nuevamente:
1. Crear colección `publicProfiles` con subset de campos (displayName, email, photoUrl, online, lastActiveAt, normalizedSearch).
2. Ajustar el selector para leer de `publicProfiles`.
3. Cambiar regla `allow read: if canAdmin() || isSignedIn();` por la versión restringida original.

## 9. App Check (warning "No AppCheckProvider installed")
Actualmente desactivado (`enforceAppCheck: false`). Para habilitar:
- Configurar App Check en consola (Play Integrity / DeviceCheck / reCAPTCHA v3).
- Inicializar en Flutter con `FirebaseAppCheck.instance.activate(...)`.
- Quitar `enforceAppCheck: false` de las callables gradualmente.

## 10. Checklist Rápido
- [ ] Reglas desplegadas
- [ ] Índices desplegados
- [ ] Functions desplegadas sin errores
- [ ] Migración ejecutada (updated > 0 la primera vez)
- [ ] Búsqueda funciona sin PERMISSION_DENIED
- [ ] Notificaciones de mensajes siguen llegando

---
Si algo falla, revisar logs en Firebase Console > Functions > Logs. Para Firestore, verifica que los campos `normalizedSearch` aparezcan en varios documentos.
