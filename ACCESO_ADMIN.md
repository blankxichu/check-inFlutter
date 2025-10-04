# Cómo Acceder al Panel de Administrador

## Pasos para obtener acceso de admin

### 1. Ejecutar la app
```bash
cd /Volumes/mcOS/checkin_flutter/guardias_escolares
flutter run -d 2A271FDH300EQ1
```

### 2. En la app, hacer clic en "Hacerme admin (debug)"
- Este botón aparece solo en modo debug
- Te pedirá confirmar o simplemente hará el cambio automáticamente

### 3. Si hay error, verificar que:
- El usuario esté autenticado (debe aparecer tu email en la pantalla)
- La función Cloud esté desplegada (✅ Ya está)
- El secreto bootstrap esté configurado (✅ Ya está: `GE-BOOTSTRAP-123`)

### 4. Refrescar los claims del usuario
Después de que aparezca "Rol admin asignado":
- **Cerrar sesión** (botón logout en la app)
- **Volver a iniciar sesión**

### 5. Verificar acceso
Después de iniciar sesión nuevamente:
- Debe aparecer el botón **"Admin Dashboard"** en la pantalla principal
- Hacer clic para acceder al panel de administrador

## Si sigue sin funcionar

Verificar en la consola de Flutter si hay errores durante la llamada a `setUserRole`.

El panel de admin mostrará:
- Estadísticas de la app
- Formulario para asignar roles a otros usuarios
- Métricas de usage

## Función Bootstrap
- **Secreto**: `GE-BOOTSTRAP-123`
- **Región**: `us-central1`
- **Nombre**: `setUserRole`
- **Status**: ✅ Desplegada y activa