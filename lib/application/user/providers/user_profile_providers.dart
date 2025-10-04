import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:guardias_escolares/infrastructure/user/firestore_user_profile_repository.dart';
import 'package:guardias_escolares/infrastructure/user/firebase_avatar_repository.dart';
import 'package:guardias_escolares/domain/user/repositories/user_profile_repository.dart';
import 'package:guardias_escolares/application/user/usecases/get_user_profile.dart';
import 'package:guardias_escolares/application/user/usecases/update_user_display_name.dart';
import 'package:guardias_escolares/application/user/usecases/upload_user_avatar.dart';
import 'package:guardias_escolares/application/user/usecases/refresh_user_stats.dart';
import 'package:guardias_escolares/application/checkin/usecases/build_sessions.dart';
import 'package:guardias_escolares/presentation/viewmodels/check_in_view_model.dart';
import 'package:guardias_escolares/application/user/usecases/ensure_profile_doc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return FirestoreUserProfileRepository(db: FirebaseFirestore.instance);
});

final avatarRepositoryProvider = Provider<AvatarRepository>((ref) {
  return FirebaseAvatarRepository(storage: FirebaseStorage.instance);
});

final getUserProfileProvider = Provider<GetUserProfile>((ref) => GetUserProfile(ref.watch(userProfileRepositoryProvider)));
final updateDisplayNameProvider = Provider<UpdateUserDisplayName>((ref) => UpdateUserDisplayName(ref.watch(userProfileRepositoryProvider)));
final uploadUserAvatarProvider = Provider<UploadUserAvatar>((ref) => UploadUserAvatar(
  avatars: ref.watch(avatarRepositoryProvider),
  profiles: ref.watch(userProfileRepositoryProvider),
));

final buildSessionsProvider = Provider<BuildSessions>((_) => BuildSessions());
final refreshUserStatsProvider = Provider<RefreshUserStats>((ref) => RefreshUserStats(
  profiles: ref.watch(userProfileRepositoryProvider),
  checkIns: ref.watch(checkInRepositoryProvider),
  buildSessions: ref.watch(buildSessionsProvider),
  ensure: ref.watch(ensureProfileDocProvider),
));

final ensureProfileDocProvider = Provider<EnsureProfileDoc>((_) => EnsureProfileDoc(firestore: FirebaseFirestore.instance));

