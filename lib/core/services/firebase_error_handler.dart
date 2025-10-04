import 'package:flutter/material.dart';

/// Clase para manejar errores relacionados con Firebase de forma centralizada
class FirebaseErrorHandler {
  /// Maneja errores de operaciones de Firebase y los traduce a mensajes amigables
  static String handleError(dynamic error) {
    debugPrint('Firebase error: $error');
    
    // Mensajes específicos basados en códigos de error comunes
    if (error.toString().contains('permission-denied') || 
        error.toString().contains('PERMISSION_DENIED')) {
      return 'No tienes permiso para realizar esta acción. Verifica tu inicio de sesión.';
    }
    
    if (error.toString().contains('App Check')) {
      return 'Error de verificación de la aplicación. Los administradores deben habilitar la API de App Check.';
    }
    
    if (error.toString().contains('not-found') || 
        error.toString().contains('NOT_FOUND')) {
      return 'El documento o recurso solicitado no existe.';
    }
    
    if (error.toString().contains('network')) {
      return 'Error de conexión. Verifica tu conexión a internet.';
    }
    
    // Mensaje genérico para otros errores
    return 'Se produjo un error en la operación. Por favor, inténtalo de nuevo.';
  }

  /// Verifica si el error está relacionado con App Check no habilitado
  static bool isAppCheckApiDisabledError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('app check api') && 
           errorString.contains('disabled');
  }
  
  /// Verifica si el error es un problema de permisos
  static bool isPermissionError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('permission') || 
           errorString.contains('unauthorized');
  }
}