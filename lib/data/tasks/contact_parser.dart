/// Feder: Zerlegt erkannten Text in Kontaktfelder ("Max Mustermann
/// 0171 1234567 max@beispiel.de"). Das ist nur eine Vorbelegung zum Korrigieren.
class ContactGuess {
  const ContactGuess({
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.email = '',
  });

  final String firstName;
  final String lastName;
  final String phone;
  final String email;
}

abstract class ContactParser {
  static ContactGuess parse(String input) {
    var text = input;

    var email = '';
    final emailMatch = RegExp(
      r'[\w.+\-]+\s?@\s?[\w\-]+(?:\.[\w\-]+)+',
    ).firstMatch(text);
    if (emailMatch != null) {
      email = emailMatch.group(0)!.replaceAll(' ', '');
      text = text.replaceRange(emailMatch.start, emailMatch.end, ' ');
    }

    var phone = '';
    final phoneMatch = RegExp(
      r'\+?\d[\d\s/\-()]{5,}\d',
    ).firstMatch(text);
    if (phoneMatch != null) {
      phone = phoneMatch.group(0)!.replaceAll(RegExp(r'\s+'), ' ').trim();
      text = text.replaceRange(phoneMatch.start, phoneMatch.end, ' ');
    }

    // Beschriftungen wie "Tel.", "Handy", "Mobil", "Mail" entfernen.
    text = text.replaceAll(
      RegExp(
        r'\b(tel(efon)?|handy|mobil|fax|e-?mail|mail)\b\.?:?',
        caseSensitive: false,
      ),
      ' ',
    );

    final tokens = text
        .split(RegExp(r'[\s,;]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    var first = '';
    var last = '';
    if (tokens.length == 1) {
      last = tokens.first;
    } else if (tokens.length > 1) {
      last = tokens.last;
      first = tokens.sublist(0, tokens.length - 1).join(' ');
    }
    return ContactGuess(
      firstName: first,
      lastName: last,
      phone: phone,
      email: email,
    );
  }
}
