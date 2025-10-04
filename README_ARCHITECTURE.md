Guardias Escolares - Architecture Notes

Layers
- core: app bootstrapping, themes, routers.
- domain: business entities and repository contracts (pure Dart, platform-agnostic).
- data: concrete implementations (Firebase, APIs), mappers.
- presentation: MVVM (Riverpod Notifier as ViewModel) + UI widgets/screens.

State Management
- Riverpod 3 (Notifier & Provider) to keep ViewModel testable and decoupled.

Phase 1 Scope
- Firebase init (default options via Firebase.initializeApp()).
- Auth domain & data (email/password).
- Login/Signup + Logout minimal flow.

Next Phases
- Calendar module (domain use-cases, repos, Firestore models).
- Geolocation check-in with geofencing.
- Notifications (FCM) and admin panel.
