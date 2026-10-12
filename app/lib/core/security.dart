/// Client-side security policy: password rules, input limits and text sanitising.
library;

const kMaxNameLength = 80;
const kMaxPhoneLength = 30;
const kMaxShortText = 200;
const kMaxLongText = 2000;
const kMaxJustification = 1000;

const kMinPasswordLength = 12;
const kMaxPasswordLength = 128;

/// Shown under password fields.
const passwordPolicyHint = 'At least 12 characters with three of: lowercase, uppercase, digits, symbols';

const _deniedPasswords = {
  'password',
  '12345678',
  'qwerty',
  'acme1234',
  'acmecontrol',
  'letmein',
  'welcome',
};

/// Validates a new password. Returns an English error message or null when the
/// password is acceptable.
String? validatePassword(String? value, {String? email}) {
  if (value == null || value.isEmpty) return 'Enter a password';
  if (value.length < kMinPasswordLength) return 'Use at least $kMinPasswordLength characters';
  if (value.length > kMaxPasswordLength) return 'Use at most $kMaxPasswordLength characters';

  var classes = 0;
  if (value.contains(RegExp(r'[a-z]'))) classes++;
  if (value.contains(RegExp(r'[A-Z]'))) classes++;
  if (value.contains(RegExp(r'[0-9]'))) classes++;
  if (value.contains(RegExp(r'[^A-Za-z0-9]'))) classes++;
  if (classes < 3) return 'Use at least three of: lowercase, uppercase, digits, symbols';

  // Reject well-known passwords, also when they are merely embedded in a longer one.
  final lower = value.toLowerCase();
  for (final denied in _deniedPasswords) {
    if (lower.contains(denied)) return 'This password is too common';
  }

  if (email != null && email.contains('@')) {
    final local = email.split('@').first.trim().toLowerCase();
    if (local.length >= 3 && lower.contains(local)) return 'The password must not contain your e-mail address';
  }
  return null;
}

final _controlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');
final _manyNewlines = RegExp(r'\n{3,}');

/// Trims, strips control characters (newline and tab are kept) and collapses
/// runs of more than two consecutive newlines.
String sanitizeText(String input) {
  final cleaned = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll(_controlChars, '');
  return cleaned.replaceAll(_manyNewlines, '\n\n').trim();
}

/// Phone numbers: digits, '+', spaces and dashes only.
final phonePattern = RegExp(r'^[0-9+\s-]*$');

String? validatePhone(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  if (value.length > kMaxPhoneLength) return 'Use at most $kMaxPhoneLength characters';
  if (!phonePattern.hasMatch(value)) return 'Use digits, spaces, + and - only';
  return null;
}

String? validateRequiredText(String? value, {required String label, required int max, int min = 1}) {
  final text = value?.trim() ?? '';
  if (text.length < min) return min <= 1 ? 'Enter $label' : 'Enter $label (at least $min characters)';
  if (text.length > max) return 'Use at most $max characters';
  return null;
}

String? validateOptionalText(String? value, {required int max}) {
  if (value == null) return null;
  if (value.trim().length > max) return 'Use at most $max characters';
  return null;
}
