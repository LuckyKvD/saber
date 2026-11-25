import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';

/// Merkt sich, wo im Blatt der Rahmen des Schreibfelds liegt,
/// damit die Seite diesen Rahmen einzeichnen kann.
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

/// Zustand des Schreibfelds (Lupe): Wo liegt der Rahmen auf dem Blatt,
/// wie groß ist er, und wie wandert er beim Schreiben weiter.
///
/// Das Schreibfeld ist eine Lupe auf das echte Blatt: Der Rahmen [rect]
/// (in Seitenkoordinaten) wird im Feld vergrößert gezeigt. Geschrieben wird
/// direkt ins Blatt, deshalb gibt es keine Umrechnung und keine Lücken.
class WritingPadController extends ChangeNotifier {
  /// Abstand zum Seitenrand in Seitenpunkten.
  static const margin = 40.0;

  List<EditorPage> _pages = const [];
  void Function(int pageIndex) _ensurePage = _noEnsure;
  Object? _owner;

  static void _noEnsure(int pageIndex) {}

  /// Kästchengröße (Zeilenhöhe) der Notiz in Seitenpunkten.
  double cell = 40;

  int pageIndex = 0;

  /// Linke obere Ecke des Rahmens in Seitenpunkten.
  double left = margin;
  double top = margin;

  /// Breite des Rahmens in Seitenpunkten (bestimmt die Vergrößerung).
  double width = 400;

  /// Höhe geteilt durch Breite; wird vom Feld vorgegeben, weil der Rahmen
  /// genau dem sichtbaren Ausschnitt des Felds entsprechen muss.
  double aspect = 0.25;

  /// Hier beginnt jede neue Zeile (nach "Enter").
  double lineStartX = margin;

  bool _sized = false;

  /// Verbindet den Controller mit der aktuellen Notiz.
  void attach({
    required List<EditorPage> pages,
    required void Function(int pageIndex) ensurePage,
    required double cell,
    required Object owner,
  }) {
    _pages = pages;
    _ensurePage = ensurePage;
    _owner = owner;
    this.cell = math.max(10, cell);
  }

  double get height => width * aspect;
  Rect get rect => Rect.fromLTWH(left, top, width, height);

  /// Zeilenvorschub: Rahmenhöhe, aufgerundet auf ganze Kästchen.
  double get lineAdvance => math.max(1, (height / cell).ceil()) * cell;

  Size get _pageSize => _pages.isEmpty
      ? EditorPage.defaultSize
      : _pages[pageIndex.clamp(0, _pages.length - 1)].size;

  double _snapY(double y, {bool up = false}) {
    final n = y / cell;
    return (up ? n.ceil() : n.round()) * cell;
  }

  double _firstFreeY(int index) {
    if (_pages.isEmpty) return _snapY(margin);
    final page = _pages[index];
    if (page.strokes.isEmpty) return _snapY(margin);
    var maxY = 0.0;
    for (final stroke in page.strokes) {
      maxY = math.max(maxY, stroke.maxY);
    }
    return _snapY(maxY + cell * 0.5, up: true);
  }

  /// Hält Rahmen und Größe innerhalb der Seite.
  void _normalize() {
    if (_pages.isEmpty) return;
    pageIndex = pageIndex.clamp(0, _pages.length - 1);
    final size = _pageSize;
    width = width
        .clamp(math.min(120.0, size.width), size.width * 0.95)
        .toDouble();
    left = left.clamp(0, math.max(0, size.width - width)).toDouble();
    top = top.clamp(0, math.max(0, size.height - height)).toDouble();
  }

  void _publish() {
    final owner = _owner;
    if (owner == null) return;
    WritingPadGuide.owner = owner;
    WritingPadGuide.pageIndex = pageIndex;
    WritingPadGuide.rect = rect;
  }

  void _changed() {
    _normalize();
    _publish();
    notifyListeners();
  }

  /// Öffnet das Schreibfeld auf der ersten freien Zeile der Seite.
  void openAt(int startPage) {
    if (_pages.isEmpty) return;
    pageIndex = startPage.clamp(0, _pages.length - 1);
    left = margin;
    lineStartX = margin;
    top = _firstFreeY(pageIndex);
    if (top + height > _pageSize.height - margin &&
        pageIndex + 1 < _pages.length) {
      pageIndex++;
      top = _snapY(margin);
    }
    _changed();
  }

  /// Wird vom Feld aufgerufen, sobald seine Größe bekannt ist.
  void setAspect(double newAspect) {
    if (newAspect <= 0 || newAspect.isNaN || newAspect.isInfinite) return;
    if (_sized && (newAspect - aspect).abs() < 1e-6) return;
    aspect = newAspect;
    if (!_sized) {
      _sized = true;
      final saved = stows.easyWritingWidth.value;
      // Standard: der Rahmen ist zwei Kästchen hoch.
      width = saved > 0 ? saved.toDouble() : 2 * cell / newAspect;
    }
    _changed();
  }

  /// Rahmen breiter oder schmaler ziehen (Seitenverhältnis bleibt).
  void setWidth(double newWidth) {
    width = newWidth;
    _changed();
  }

  void endResize() {
    stows.easyWritingWidth.value = width.round();
  }

  /// Verschiebt den Rahmen (Ziehen mit dem Finger), waagerecht und senkrecht.
  void moveBy(Offset delta) {
    left += delta.dx;
    top += delta.dy;
    _changed();
  }

  /// Finger losgelassen: Zeile rastet auf das Kästchenraster ein
  /// und merkt sich den neuen Zeilenanfang.
  void endMove() {
    top = _snapY(top);
    lineStartX = left;
    _changed();
  }

  /// Springt in die nächste Zeile (Enter).
  void newLine() {
    left = lineStartX;
    top += lineAdvance;
    if (top + height > _pageSize.height - margin) {
      pageIndex++;
      _ensurePage(pageIndex);
      top = _snapY(margin);
    }
    _changed();
  }

  /// Schiebt den Rahmen ein Stück nach links (-1) oder rechts (+1).
  void shift(int direction) {
    left += direction * width * 0.6;
    _changed();
  }

  /// Nach jedem Strich: Reicht die Schrift über die Marke hinaus,
  /// rückt der Rahmen weiter. Am Seitenende folgt ein Zeilenumbruch.
  void afterStroke({
    required double lastX,
    required double markerFraction,
  }) {
    if (lastX <= left + markerFraction * width) return;
    final maxLeft = math.max(0.0, _pageSize.width - width);
    if (left >= maxLeft - 1) {
      newLine();
    } else {
      left = math.min(lastX - width * 0.15, maxLeft);
      _changed();
    }
  }

  /// Schreibfeld schließen: Rahmen sofort vom Blatt nehmen.
  void close() {
    WritingPadGuide.clear();
    _owner = null;
    _sized = false;
    notifyListeners();
  }
}
