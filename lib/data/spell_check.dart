import 'package:flutter/services.dart';

/// Ein vom Systemprüfer gemeldeter Fehler.
class SpellIssue {
  const SpellIssue(this.start, this.length, this.suggestions);
  final int start, length;
  final List<String> suggestions;
}

class SpellResult {
  const SpellResult({required this.available, this.reason, this.issues = const []});
  final bool available;
  final String? reason;
  final List<SpellIssue> issues;
}

/// Rechtschreibprüfung über den Android-Systemprüfer (Test).
abstract final class SpellCheck {
  static const _channel = MethodChannel('de.luckykvd.feder/spell');

  static Future<SpellResult> check(String text, {String lang = 'de-DE'}) async {
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('check', {
        'text': text,
        'lang': lang,
      });
      if (r == null || r['available'] != true) {
        return SpellResult(available: false, reason: r?['reason'] as String?);
      }
      final issues = <SpellIssue>[
        for (final m in (r['issues'] as List))
          SpellIssue(
            (m['start'] as num).toInt(),
            (m['length'] as num).toInt(),
            [for (final s in (m['suggestions'] as List)) s as String],
          ),
      ];
      return SpellResult(available: true, issues: issues);
    } catch (e) {
      return SpellResult(available: false, reason: '$e');
    }
  }
}
