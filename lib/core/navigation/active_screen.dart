import 'package:flutter_riverpod/flutter_riverpod.dart';

sealed class ActiveScreen {
  const ActiveScreen();
}

class ActiveCalendar extends ActiveScreen {
  final DateTime? focusDay;
  const ActiveCalendar({this.focusDay});
}

class ActiveOther extends ActiveScreen {
  const ActiveOther();
}

class ActiveScreenNotifier extends Notifier<ActiveScreen> {
  @override
  ActiveScreen build() => const ActiveOther();

  void setCalendar(DateTime? day) => state = ActiveCalendar(focusDay: day);
  void setOther() => state = const ActiveOther();
}

final activeScreenProvider = NotifierProvider<ActiveScreenNotifier, ActiveScreen>(
  () => ActiveScreenNotifier(),
);
