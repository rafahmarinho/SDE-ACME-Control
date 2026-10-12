import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../models/profile.dart';

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  Session? get session => _client.auth.currentSession;
  User? get user => _client.auth.currentUser;
  bool get isSignedIn => session != null;
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  String? get accessToken => _client.auth.currentSession?.accessToken;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  String get _recoveryRedirect => kIsWeb ? '${Env.webAppUrl}/#/reset-password' : Env.mobileAuthCallback;

  Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim(), redirectTo: _recoveryRedirect);
  }

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Changes the password after re-authenticating with the current one.
  /// Throws [AuthException] with a user-friendly message when the current
  /// password is wrong.
  Future<void> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _client.auth.signInWithPassword(email: email.trim(), password: currentPassword);
    } on AuthApiException {
      throw const AuthException(wrongCurrentPasswordMessage);
    }
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  static const wrongCurrentPasswordMessage = 'Current password is incorrect';

  Future<Profile?> fetchProfile(String userId) async {
    final row = await _client.from('profiles').select().eq('id', userId).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<List<Profile>> fetchProfiles() async {
    final rows = await _client.from('profiles').select().order('full_name');
    return rows.map(Profile.fromJson).toList();
  }

  Future<Profile> updateProfile(
    String userId, {
    String? fullName,
    String? phone,
    String? avatarUrl,
    String? defaultPlantId,
    Map<String, dynamic>? settings,
  }) async {
    final patch = <String, dynamic>{};
    if (fullName != null) patch['full_name'] = fullName.trim();
    if (phone != null) patch['phone'] = phone.trim();
    if (avatarUrl != null) patch['avatar_url'] = avatarUrl;
    if (defaultPlantId != null) patch['default_plant_id'] = defaultPlantId;
    if (settings != null) patch['settings'] = settings;
    final row = await _client.from('profiles').update(patch).eq('id', userId).select().single();
    return Profile.fromJson(row);
  }

  /// Uploads the picture to `avatars/<uid>.<ext>` in the private bucket and
  /// returns that storage PATH (stored in `profiles.avatar_url`).
  Future<String> uploadAvatar(String userId, Uint8List bytes, String contentType) async {
    final ext = contentType.split('/').last;
    final path = 'avatars/$userId.${ext == 'jpeg' ? 'jpg' : ext}';
    await _client.storage.from('attachments').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return path;
  }
}
