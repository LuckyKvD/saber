import 'package:material_ui/material_ui.dart';

/// Merkt sich, wo im Blatt die nächste Zeile des Schreibfelds landet,
/// damit die Seite dieses Feld einzeichnen kann.
class WritingPadGuide {
  const WritingPadGuide._();

  /// Gehört zur Notiz (EditorCoreInfo), in der das Schreibfeld offen ist.
  /// So erscheint der Rahmen weder in Vorschaubildern noch in Exporten.
  static Object? owner;
  static int pageIndex = -1;
  static Rect rect = Rect.zero;

  static Rect? rectFor(Object coreInfo, int index) {
    if (owner == null || !identical(owner, coreInfo)) return null;
    if (index != pageIndex || rect.isEmpty) return null;
    return rect;
  }

  static void clear() {
    owner = null;
    pageIndex = -1;
    rect = Rect.zero;
  }
}

/// Verbindung zwischen Editor und Schreibfeld für "Ort wählen":
/// Nach [arm] setzt der nächste Tipp in die Notiz den Startpunkt.
class WritingPadController extends ChangeNotifier {
  bool armed = false;
  int? targetPage;
  Offset? target;

  void arm() {
    armed = true;
    notifyListeners();
  }

  void disarm() {
    if (!armed) return;
    armed = false;
    notifyListeners();
  }

  void place(int page, Offset position) {
    armed = false;
    targetPage = page;
    target = position;
    notifyListeners();
  }
}
