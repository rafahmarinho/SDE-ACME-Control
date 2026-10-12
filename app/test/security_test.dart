import 'package:acme_control/core/security.dart';
import 'package:acme_control/models/maintenance_order.dart';
import 'package:acme_control/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validatePassword', () {
    test('accepts a strong password', () {
      expect(validatePassword('Correct-Horse-7Battery'), isNull);
      expect(validatePassword('xK9#mP2\$vL5@qR8w'), isNull);
    });

    test('rejects empty, short and overlong passwords', () {
      expect(validatePassword(null), isNotNull);
      expect(validatePassword(''), isNotNull);
      expect(validatePassword('Short1!'), contains('12'));
      expect(validatePassword('Aa1!${'x' * 125}'), contains('128'));
    });

    test('requires three of four character classes', () {
      expect(validatePassword('alllowercaseletters'), isNotNull);
      expect(validatePassword('lowerUPPERonlyletters'), isNotNull);
      expect(validatePassword('lowerUPPER12345'), isNull);
      expect(validatePassword('lower12345!!!!'), isNull);
      expect(validatePassword('UPPER12345!!!!'), isNull);
    });

    test('rejects deny-listed passwords, also when embedded', () {
      expect(validatePassword('Password2026!!'), contains('common'));
      expect(validatePassword('AcmeControl#99'), contains('common'));
      expect(validatePassword('Qwerty!Qwerty!1'), contains('common'));
      expect(validatePassword('LetMeIn-2026-A'), contains('common'));
    });

    test('rejects passwords containing the e-mail local part', () {
      expect(validatePassword('Supervisor#2026', email: 'supervisor@acme.demo'), contains('e-mail'));
      expect(validatePassword('Operator-Night-9', email: 'OPERATOR@acme.demo'), contains('e-mail'));
      expect(validatePassword('Operator-Night-9', email: 'engineer@acme.demo'), isNull);
      // Very short local parts are not matched to avoid rejecting every password containing "ab".
      expect(validatePassword('Table-Lamp-Shade9', email: 'ab@acme.demo'), isNull);
    });
  });

  group('sanitizeText', () {
    test('trims and strips control characters but keeps newline and tab', () {
      expect(sanitizeText('  hello\u0000 world\u0007 '), 'hello world');
      expect(sanitizeText('line1\n\tindented\u001b[31m'), 'line1\n\tindented[31m');
      expect(sanitizeText('\u007fdel'), 'del');
    });

    test('normalises CRLF and collapses more than two newlines', () {
      expect(sanitizeText('a\r\nb\rc'), 'a\nb\nc');
      expect(sanitizeText('a\n\n\n\n\nb'), 'a\n\nb');
      expect(sanitizeText('a\n\nb'), 'a\n\nb');
    });

    test('phone validation', () {
      expect(validatePhone(''), isNull);
      expect(validatePhone('+55 11 99999-0000'), isNull);
      expect(validatePhone('call me'), isNotNull);
      expect(validatePhone('1' * (kMaxPhoneLength + 1)), isNotNull);
    });

    test('text length validators use the shared limits', () {
      expect(validateRequiredText('', label: 'a title', max: kMaxShortText), isNotNull);
      expect(validateRequiredText('ok', label: 'a title', max: kMaxShortText), isNull);
      expect(validateRequiredText('x' * (kMaxShortText + 1), label: 'a title', max: kMaxShortText), isNotNull);
      expect(validateOptionalText(null, max: kMaxLongText), isNull);
      expect(validateOptionalText('x' * (kMaxLongText + 1), max: kMaxLongText), isNotNull);
    });
  });

  group('private storage paths', () {
    test('attachment keeps the path and derives it from legacy public URLs', () {
      final fresh = Attachment.fromJson({'name': 'a.jpg', 'path': 'maintenance/p1/1_a.jpg', 'content_type': 'image/jpeg'});
      expect(fresh.storagePath, 'maintenance/p1/1_a.jpg');
      expect(fresh.toJson().containsKey('url'), isFalse);

      final legacy = Attachment.fromJson({
        'name': 'b.png',
        'url': 'https://ref.supabase.co/storage/v1/object/public/attachments/maintenance/p1/2_b.png?v=1',
        'content_type': 'image/png',
      });
      expect(legacy.path, isNull);
      expect(legacy.storagePath, 'maintenance/p1/2_b.png');

      final unknown = Attachment.fromJson({'name': 'c', 'url': 'https://example.com/c.png'});
      expect(unknown.storagePath, isNull);
    });

    test('storage service normalises paths and legacy URLs', () {
      expect(StorageService.normalize('avatars/uid.jpg'), 'avatars/uid.jpg');
      expect(StorageService.normalize('https://ref.supabase.co/storage/v1/object/public/attachments/avatars/uid.jpg?v=2'), 'avatars/uid.jpg');
      expect(StorageService.normalize('https://example.com/x.jpg'), isNull);
      expect(StorageService.normalize(''), isNull);
      expect(StorageService.normalize(null), isNull);
    });
  });
}
