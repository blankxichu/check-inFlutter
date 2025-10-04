import 'package:flutter/material.dart';

class NavigationService {
  NavigationService._();
  static final NavigationService instance = NavigationService._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  NavigatorState? get _nav => navigatorKey.currentState;

  bool pushShiftCalendar({DateTime? focusDay}) {
    if (_nav == null) return false;
    // TODO: Ajustar a la ruta real del calendario (placeholder)
    // Por simplicidad, usamos pushNamed si estuviera configurado.
    try {
      _nav!.pushNamed('/calendar', arguments: focusDay);
      return true;
    } catch (_) {
      return false;
    }
  }
}
