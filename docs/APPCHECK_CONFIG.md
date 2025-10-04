# Firebase App Check - Instrucciones para configuración

## Problema detectado
La API de Firebase App Check no está habilitada en este proyecto, lo que causa errores de permiso al intentar acceder a servicios como Firestore o Storage.

Error específico:
```
Firebase App Check API has not been used in project 1008870122153 before or it is disabled.
Enable it by visiting https://console.developers.google.com/apis/api/firebaseappcheck.googleapis.com/overview?project=1008870122153
```

## Pasos para habilitar App Check

### 1. Habilitar la API de Firebase App Check
Visita el siguiente enlace para habilitar la API:
[Habilitar Firebase App Check API](https://console.developers.google.com/apis/api/firebaseappcheck.googleapis.com/overview?project=1008870122153)

### 2. Configurar App Check en la consola de Firebase
1. Ve a la [Consola de Firebase](https://console.firebase.google.com)
2. Selecciona tu proyecto
3. En el menú lateral, ve a "App Check"
4. Configura los proveedores de verificación:
   - Para iOS: DeviceCheck (producción) / Debug Provider (desarrollo)
   - Para Android: Play Integrity (producción) / Debug Provider (desarrollo)

### 3. Durante el desarrollo
- Para pruebas locales, puedes deshabilitar temporalmente la aplicación forzosa (enforcement) de App Check
- Esto permitirá que tu app funcione mientras terminas la implementación

### 4. Verificar configuración
Después de habilitar la API y configurar App Check, reinicia la aplicación y verifica que el error desaparezca. El mensaje "Firebase App Check activado correctamente" debe aparecer en la consola de depuración.

## Recursos adicionales
- [Documentación de Firebase App Check](https://firebase.google.com/docs/app-check)
- [Flutter firebase_app_check package](https://pub.dev/packages/firebase_app_check)