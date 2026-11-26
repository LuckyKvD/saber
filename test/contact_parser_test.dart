import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/tasks/contact_parser.dart';

void main() {
  test('Name, Telefon und E-Mail', () {
    final g = ContactParser.parse('Max Mustermann 0171 1234567 max@beispiel.de');
    expect(g.firstName, 'Max');
    expect(g.lastName, 'Mustermann');
    expect(g.phone, '0171 1234567');
    expect(g.email, 'max@beispiel.de');
  });
  test('Beschriftung und Vorwahl mit Plus', () {
    final g = ContactParser.parse('Tel.: +49 6701 123456 Erika Muster');
    expect(g.firstName, 'Erika');
    expect(g.lastName, 'Muster');
    expect(g.phone, '+49 6701 123456');
  });
  test('Nur ein Name', () {
    final g = ContactParser.parse('Mustermann');
    expect(g.firstName, '');
    expect(g.lastName, 'Mustermann');
  });
  test('Nur Telefonnummer', () {
    final g = ContactParser.parse('06701/98765');
    expect(g.phone, '06701/98765');
    expect(g.lastName, '');
  });
}
