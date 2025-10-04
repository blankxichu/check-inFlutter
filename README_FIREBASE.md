# Despliegue de reglas y seed de Firestore

Proyecto: `checkin-flutter-cc702`

## Requisitos
- Node.js 18+
- Firebase CLI (`npm i -g firebase-tools`)
- Credenciales de servicio (opción A) o login con `firebase login` (opción B)

## 1) Deploy de reglas Firestore y Storage

```bash
# Desde la carpeta guardias_escolares
firebase use checkin-flutter-cc702
firebase deploy --only firestore:rules
firebase deploy --only storage
```

Esto publica `firestore.rules` en tu proyecto.

## 2) Semillas mínimas (schools/default y _ping/x)

Opción A (recomendada en CI): usar cuenta de servicio
```bash
export GOOGLE_APPLICATION_CREDENTIALS=/ruta/serviceAccount.json
node tooling/seed_firestore.js checkin-flutter-cc702
```

Opción B: usando Firebase Emulador o Admin con login local (necesita permisos adecuados). Preferir A para producción.

## Campos creados
- `schools/default` con `lat`, `lon`, `radius`
- `_ping/x` doc para ver conectividad desde la app

## 3) (Opcional) Datos de prueba en shifts
Crea manualmente en consola docs `shifts/{yyyy-MM-dd}` con `date` (timestamp UTC), `users` (string[]), `capacity` (number).

## 4) App Check (opcional pero recomendado)
Verás avisos como "No AppCheckProvider installed" en logs. Se ha integrado App Check en la app usando Play Integrity (Android) y DeviceCheck (iOS).

Pasos:
- En Firebase Console > App Check, habilita tu app Android y iOS.
- Android: selecciona "Play Integrity". iOS: "DeviceCheck" (o App Attest si tienes certificados y iOS suficiente).
- Activa "enforcement" cuando valides que los tokens se generan y las llamadas pasan.

Notas:
- Para web no aplica en este proyecto.
- En desarrollo, si necesitas desactivar enforcement temporalmente, hazlo desde la consola.
