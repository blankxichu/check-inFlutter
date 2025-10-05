import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/application/user/providers/user_profile_providers.dart';

/// Provider que cachea URLs de avatares para evitar descargas repetidas
final avatarUrlProvider = FutureProvider.family<String?, String>((ref, avatarPath) async {
  if (avatarPath.isEmpty) return null;

  try {
    final avatarRepo = ref.watch(avatarRepositoryProvider);
    final uri = await avatarRepo
        .getDownloadUri(avatarPath)
        .timeout(const Duration(seconds: 8));
    return uri.toString();
  } on TimeoutException {
    debugPrint('Timeout getting avatar URL, fallback to direct path (no cache bust).');
    return null; // allow UI to show placeholder instead of spinner
  } catch (e) {
    debugPrint('Error caching avatar URL: $e');
    return null; // placeholder
  }
});

/// Provider simple para invalidar cache de avatares
final avatarCacheVersionProvider = Provider<int>((ref) => 0);