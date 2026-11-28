import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart' show TickerCanceled;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:keybinder/keybinder.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/book_flip_painter.dart';
import 'package:saber/components/canvas/page_curl_painter.dart';
import 'package:saber/components/canvas/hud/canvas_hud.dart';
import 'package:saber/components/canvas/interactive_canvas.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/change_notifier_extensions.dart';
import 'package:saber/data/extensions/matrix4_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/pressure_curve.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

class CanvasGestureDetector extends StatefulWidget {
  new({
    super.key,
    required this.filePath,
    required this.isDrawGesture,
    this.onInteractionEnd,
    required this.onDrawStart,
    required this.onDrawUpdate,
    required this.onDrawEnd,
    required this.updatePointerData,
    required this.onHovering,
    required this.onHoveringEnd,
    required this.onStylusButtonChanged,
    required this.undo,
    required this.redo,
    required this.pages,
    required this.initialPageIndex,
    required this.pageBuilder,
    required this.placeholderPageBuilder,
    required this.isTextEditing,
    this.horizontal = false,
    TransformationController? transformationController,
  }) : _transformationController =
           transformationController ?? TransformationController();

  final String filePath;

  final bool Function(ScaleStartDetails scaleDetails) isDrawGesture;
  final ValueChanged<ScaleEndDetails>? onInteractionEnd;
  final ValueChanged<ScaleStartDetails> onDrawStart;
  final ValueChanged<ScaleUpdateDetails> onDrawUpdate;
  final ValueChanged<ScaleEndDetails> onDrawEnd;

  /// Called when the pressure of the stylus changes.
  /// The [pressure] value is normalized into a range of 0 to 1.
  final void Function(PointerDeviceKind kind, double? pressure)
  updatePointerData;
  final VoidCallback onHovering;
  final VoidCallback onHoveringEnd;
  final ValueChanged<bool> onStylusButtonChanged;

  final VoidCallback undo;
  final VoidCallback redo;

  final List<EditorPage> pages;
  final int? initialPageIndex;
  final Widget Function(BuildContext context, int pageIndex) pageBuilder;
  final Widget Function(BuildContext context, int pageIndex)
  placeholderPageBuilder;

  final bool Function() isTextEditing;

  /// Feder: Seiten nebeneinander statt untereinander (Blättern wie im Buch).
  final bool horizontal;

  late final TransformationController _transformationController;

  @override
  State<CanvasGestureDetector> createState() => CanvasGestureDetectorState();

  static const kMinScale = 0.3;
  static const kMaxScale = 10.0;

  static double getTopOfPage({
    required int pageIndex,
    required List<EditorPage> pages,
    required double screenWidth,
    bool twoUp = false,
  }) {
    if (pageIndex <= 0) return 0;

    double top = 0;

    double heightOf(int i) {
      final pageSize = pages[i].size;

      /// Since we use a FittedBox, the actual width of the page
      /// is the minimum of the page width and the screen width.
      final pageWidthFitted = min(pageSize.width, screenWidth);
      return pageSize.height * (pageWidthFitted / pageSize.width);
    }

    if (twoUp) {
      // Feder: Zwei Seiten pro Zeile; eine Zeile ist so hoch wie die höhere Seite.
      final rowOfPage = pageIndex ~/ 2;
      for (int row = 0; row < rowOfPage; row++) {
        final a = row * 2;
        if (a >= pages.length) break;
        var h = heightOf(a);
        if (a + 1 < pages.length) h = max(h, heightOf(a + 1));
        top += 16 + h;
      }
      return top;
    }

    for (int i = 0; i < pageIndex && i < pages.length; i++) {
      top += 16;
      top += heightOf(i);
    }

    return top;
  }

  /// Feder: Breite des Inhalts (breiteste Zeile) im Zwei-Seiten-Layout.
  static double twoUpContentWidth(List<EditorPage> pages, double screenWidth) {
    var w = 0.0;
    for (var i = 0; i < pages.length; i += 2) {
      var row = min(pages[i].size.width, screenWidth);
      if (i + 1 < pages.length) {
        row += 16 + min(pages[i + 1].size.width, screenWidth);
      }
      w = max(w, row);
    }
    return w;
  }

  static void scrollToPage({
    required int pageIndex,
    required List<EditorPage> pages,
    required double screenWidth,
    required TransformationController transformationController,
  }) {
    final topOfPage = -CanvasGestureDetector.getTopOfPage(
      pageIndex: pageIndex,
      pages: pages,
      screenWidth: screenWidth,
    );
    transformationController.value = Matrix4.translationValues(
      0,
      // Slight upwards offset so that the page is not flush with the top of the screen
      topOfPage + 50,
      0,
    );
  }

  /// Feder: Buch-Doppelblatt (Querformat beim seitlichen Blättern).
  static bool isSpread(double containerWidth, double containerHeight) =>
      containerHeight.isFinite && containerWidth > containerHeight;

  /// Fach (Blatt) der Seite. Doppelblatt: Seite 1 steht allein (rechts),
  /// dann 2/3, 4/5 … wie in einem echten Buch.
  static int slotOfPage(int page, bool spread) =>
      spread ? (page + 1) ~/ 2 : page;

  static int firstPageOfSlot(int slot, bool spread) =>
      spread ? (slot <= 0 ? 0 : 2 * slot - 1) : slot;

  static int slotCount(int pageCount, bool spread) =>
      spread ? pageCount ~/ 2 + 1 : pageCount;

  /// Erste Seite des Fachs, das [delta] Fächer entfernt liegt.
  static int adjacentPage(
    int page,
    int delta,
    int pageCount,
    bool spread,
  ) {
    final slots = slotCount(pageCount, spread);
    final slot = (slotOfPage(page, spread) + delta).clamp(0, slots - 1).toInt();
    return min(firstPageOfSlot(slot, spread), max(0, pageCount - 1));
  }

  /// Horizontal: die Seite passt komplett ins Bild (Breite und Höhe).
  static double _fittedWidth(
    EditorPage page,
    double containerWidth, [
    double containerHeight = double.infinity,
  ]) {
    // Doppelblatt: jede Seite bekommt die halbe Breite und passt in die Höhe.
    if (isSpread(containerWidth, containerHeight)) {
      return min(
        min(page.size.width, (containerWidth - Editor.gapBetweenPages) / 2),
        (containerHeight - Editor.gapBetweenPages * 2) *
            page.size.width /
            page.size.height,
      );
    }
    final byWidth = min(page.size.width, containerWidth);
    return min(
      byWidth,
      (containerHeight - Editor.gapBetweenPages * 2) *
          page.size.width /
          page.size.height,
    );
  }

  /// Horizontal: jede Seite liegt in einem eigenen, bildbreiten Fach.
  /// So ist bei Zoom 1.0 nie mehr als eine Seite zu sehen.
  static double getLeftOfPage({
    required int pageIndex,
    required List<EditorPage> pages,
    required double containerWidth,
    double containerHeight = double.infinity,
  }) {
    if (pages.isEmpty) return 0;
    final index = pageIndex.clamp(0, pages.length - 1).toInt();
    final width = _fittedWidth(pages[index], containerWidth, containerHeight);
    final spread = isSpread(containerWidth, containerHeight);
    return slotOfPage(index, spread) * containerWidth +
        (containerWidth - width) / 2;
  }

  /// Verschiebung, bei der das Fach der Seite im Bild steht (Zoom 1.0).
  static double getTranslationXOfPage({
    required int pageIndex,
    required List<EditorPage> pages,
    required double containerWidth,
    double containerHeight = double.infinity,
  }) {
    if (pages.isEmpty) return 0;
    final index = pageIndex.clamp(0, pages.length - 1).toInt();
    final spread = isSpread(containerWidth, containerHeight);
    return -slotOfPage(index, spread) * containerWidth;
  }

  static void scrollToPageHorizontal({
    required int pageIndex,
    required List<EditorPage> pages,
    required double containerWidth,
    double containerHeight = double.infinity,
    required TransformationController transformationController,
  }) {
    transformationController.value = Matrix4.translationValues(
      getTranslationXOfPage(
        pageIndex: pageIndex,
        pages: pages,
        containerWidth: containerWidth,
        containerHeight: containerHeight,
      ),
      0,
      0,
    );
  }

  /// Index der Seite, die an der Inhalts-Position [contentX] liegt.
  static int getPageIndexAtX({
    required double contentX,
    required List<EditorPage> pages,
    required double containerWidth,
    double containerHeight = double.infinity,
  }) {
    if (pages.isEmpty || containerWidth <= 0) return 0;
    final spread = isSpread(containerWidth, containerHeight);
    final slot = (contentX / containerWidth)
        .floor()
        .clamp(0, slotCount(pages.length, spread) - 1)
        .toInt();
    return min(firstPageOfSlot(slot, spread), pages.length - 1);
  }

  static int getPageIndex({
    required double scrollY,
    required List<EditorPage> pages,
    required double screenWidth,
  }) {
    if (scrollY <= 0) return 0;

    double top = 0;

    for (int i = 0; i < pages.length; i++) {
      final pageSize = pages[i].size;

      /// Since we use a FittedBox, the actual width of the page
      /// is the minimum of the page width and the screen width.
      final pageWidthFitted = min(pageSize.width, screenWidth);

      top += 16;
      top += pageSize.height * (pageWidthFitted / pageSize.width);

      if (top > scrollY) return i;
    }

    return pages.length - 1;
  }
}

class CanvasGestureDetectorState extends State<CanvasGestureDetector>
    with TickerProviderStateMixin {
  /// Blätter-Protokoll (Einstellungen → Protokoll), zur Fehlersuche beim Tippen.
  static final _log = Logger('Blaettern');
  void _trace(String what) {
    if (!widget.horizontal) return;
    final tx = widget._transformationController.value.getTranslation().x;
    _log.info(
      '$what | tx=${tx.toStringAsFixed(0)} turning=$_turning busy=$_flipBusy '
      'pend=$_pendingTurns last=$_lastTurnTarget',
    );
  }

  late var containerBounds = const BoxConstraints();

  /// Feder: Im Querformat und weit ausgezoomt stehen zwei Seiten nebeneinander.
  bool twoUp = false;

  Timer? _pageSnapTimer;
  late final AnimationController _snapAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..addListener(_onSnapTick)
   ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _endGesture();
    });
  double _snapFrom = 0;
  double _snapTo = 0;
  double _snapScaleFrom = 1;

  /// Blättern: Seite, auf der die aktuelle Geste begonnen hat. Pro Geste
  /// kann nur eine Seite vor oder zurück geblättert werden.
  // Umblätter-Effekt: Bild der ausgehenden Seite klappt am Falz weg.
  final Map<int, GlobalKey> _pageKeys = {};
  GlobalKey _pageKeyFor(int index) =>
      _pageKeys.putIfAbsent(index, () => GlobalKey());
  late final AnimationController _flipAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  ui.Image? _flipImage;
  var _flipForward = true;
  var _flipRect = Rect.zero;
  var _flipLeftBlank = 0.0;

  // Doppelblatt: umklappendes Blatt (Vorder-, Rückseite, Seite darunter).
  ui.Image? _bookFront;
  ui.Image? _bookBack;
  ui.Image? _bookBase;
  var _bookBaseOnRight = true;
  bool get _flipBusy => _flipImage != null || _bookFront != null;

  /// Ein Umblättern läuft (auch schon während die Bilder aufgenommen werden).
  /// Verhindert, dass schnelle Tipps zwei Blätter gleichzeitig starten.
  bool _turning = false;
  double _bookTargetX = 0;

  void _disposeBook() {
    _bookFront?.dispose();
    _bookBack?.dispose();
    _bookBase?.dispose();
    _bookFront = _bookBack = _bookBase = null;
  }

  // Nachbarblätter werden erst nach kurzer Ruhe vorgerendert (schneller
  // Seitenaufbau; danach steht das Umblättern ohne Wartezeit bereit).
  int? _prefetchSlot;
  Timer? _prefetchTimer;

  void _armPrefetch() {
    _prefetchTimer?.cancel();
    if (!_spread) return;
    final slot = CanvasGestureDetector.slotOfPage(horizontalPageIndex, true);
    if (_prefetchSlot != null && _prefetchSlot != slot) {
      _prefetchSlot = null;
    }
    _prefetchTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || !_spread) return;
      final now = CanvasGestureDetector.slotOfPage(horizontalPageIndex, true);
      if (_prefetchSlot == now) return;
      setState(() => _prefetchSlot = now);
    });
  }

  Future<ui.Image?> _capturePage(int index, {double maxRatio = 2.0}) async {
    final object = _pageKeys[index]?.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    try {
      return await object.toImage(
        pixelRatio: min(MediaQuery.devicePixelRatioOf(context), maxRatio),
      );
    } catch (_) {
      return null;
    }
  }

  void _cancelFlip() {
    if (!_flipBusy) return;
    _trace('cancelFlip');
    _flipAnim.stop();
    // Doppelblatt: Blättern sofort abschließen (Ziel-Blatt zeigen).
    if (_bookFront != null) {
      final c = widget._transformationController;
      final m = c.value.clone();
      m.setTranslationRaw(_bookTargetX, m.getTranslation().y, 0);
      c.value = m;
    }
    _flipImage?.dispose();
    _flipImage = null;
    _disposeBook();
    if (mounted) setState(() {});
    _endGesture();
  }

  static const _soundChannel = MethodChannel('de.luckykvd.feder/sound');
  void _playFlipSound() {
    try {
      _soundChannel.invokeMethod<void>('pageFlip').catchError((_) {});
    } catch (_) {}
  }

  /// Blättert per Tipp um [delta] Seiten (1 = vor, -1 = zurück).
  void turnBy(int delta) {
    if (!widget.horizontal || widget.pages.isEmpty) return;
    _trace('turnBy($delta)');
    if (_flipBusy || _turning) {
      // Schnelles Tippen: nicht verschlucken, sondern (max. 3) vormerken.
      if ((_pendingTurns + delta).abs() <= 3) _pendingTurns += delta;
      return;
    }
    var start = horizontalPageIndex;
    // Steht die Ansicht noch genau dort, wo das letzte Blättern endete,
    // gilt dessen Zielseite (verhindert Rückwärts-Sprünge durch Rundung).
    final tx = widget._transformationController.value.getTranslation().x;
    if (_lastTurnTarget != null && (tx - _lastTurnX).abs() < 1.5) {
      start = _lastTurnTarget!;
    }
    final page = CanvasGestureDetector.adjacentPage(
      start,
      delta,
      widget.pages.length,
      _spread,
    );
    _trace('turnBy start=$start page=$page');
    if (page == start) return;
    _turnPage(
      start,
      page,
      CanvasGestureDetector.getTranslationXOfPage(
        pageIndex: page,
        pages: widget.pages,
        containerWidth: containerBounds.maxWidth,
        containerHeight: containerBounds.maxHeight,
      ),
    );
  }

  int _pendingTurns = 0;
  int? _lastTurnTarget;
  double _lastTurnX = 0;

  Future<void> _turnPage(int from, int to, double targetX) async {
    _trace('turnPage $from->$to');
    _lastTurnTarget = to;
    _lastTurnX = targetX;
    _pageSnapTimer?.cancel();
    _snapAnim.stop();
    _turning = true;
    try {
      await _turnPageInner(from, to, targetX);
    } finally {
      _turning = false;
    }
    if (mounted && _pendingTurns != 0) {
      final d = _pendingTurns > 0 ? 1 : -1;
      _pendingTurns -= d;
      turnBy(d);
    }
  }

  Future<void> _turnPageInner(int from, int to, double targetX) async {
    final forward = to > from;
    _playFlipSound();
    final spread = _spread;
    if (spread) {
      if (await _turnSpread(from, to, targetX)) return;
      _slideTo(targetX);
      return;
    }
    final int? imagePage = forward ? from : to;
    final image = imagePage == null ? null : await _capturePage(imagePage);
    if (!mounted) {
      image?.dispose();
      return;
    }
    final controller = widget._transformationController;
    if (image == null) {
      _slideTo(targetX);
      return;
    }
    final matrix = controller.value.clone();
    matrix.setTranslationRaw(targetX, matrix.getTranslation().y, 0);
    controller.value = matrix;

    final ratio = min(MediaQuery.devicePixelRatioOf(context), 2.0);
    final pageW = image.width / ratio;
    final h = image.height / ratio;
    // Doppelblatt: Fläche beider Seiten (+2 px Falz), Bild nur rechts.
    final w = spread ? pageW * 2 + 2 : pageW;
    _flipAnim.value = 0;
    setState(() {
      _flipImage = image;
      _flipForward = forward;
      _flipLeftBlank = spread ? pageW + 2 : 0;
      _flipRect = Rect.fromLTWH(
        (containerBounds.maxWidth - w) / 2,
        matrix.getTranslation().y + Editor.gapBetweenPages,
        w,
        h,
      );
    });
    try {
      await _flipAnim.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || _flipImage != image) return;
    _flipImage?.dispose();
    setState(() => _flipImage = null);
    _endGesture();
  }

  /// Einfaches seitliches Umschalten (Ersatz, wenn kein Bild möglich ist).
  void _slideTo(double targetX) {
    final controller = widget._transformationController;
    _snapFrom = controller.value.getTranslation().x;
    _snapTo = targetX;
    _snapScaleFrom = 1;
    _snapAnim
      ..reset()
      ..forward();
  }

  /// Echtes Buch-Umblättern. Gibt false zurück, wenn es nicht möglich ist
  /// (Seiten noch nicht gerendert): dann wird seitlich gewechselt.
  Future<bool> _turnSpread(int from, int to, double targetX) async {
    final n = widget.pages.length;
    final forward = to > from;
    final slotFrom = CanvasGestureDetector.slotOfPage(from, true);
    final slotTo = CanvasGestureDetector.slotOfPage(to, true);
    final low = min(slotFrom, slotTo);
    final high = max(slotFrom, slotTo);
    int? rightOf(int slot) {
      final i = slot == 0 ? 0 : 2 * slot;
      return i < n ? i : null;
    }

    int? leftOf(int slot) => slot == 0 ? null : 2 * slot - 1;

    final frontPage = rightOf(low); // alte rechte Seite (Blatt vorne)
    final backPage = leftOf(high); // neue linke Seite (Blatt hinten)
    final basePage = forward ? rightOf(high) : leftOf(low);
    bool ready(int? i) => i != null && widget.pages[i].isRendered;
    if (!ready(frontPage) || !ready(backPage) || !ready(basePage)) {
      return false;
    }
    final images = await Future.wait([
      _capturePage(frontPage!, maxRatio: 1.25),
      _capturePage(backPage!, maxRatio: 1.25),
      _capturePage(basePage!, maxRatio: 1.25),
    ]);
    final front = images[0];
    final back = images[1];
    final base = images[2];
    if (!mounted || front == null || back == null || base == null) {
      front?.dispose();
      back?.dispose();
      base?.dispose();
      return mounted ? false : true;
    }
    final controller = widget._transformationController;
    // Ansicht auf den Ausgangsfach setzen, damit das Blatt passgenau liegt.
    final startX = CanvasGestureDetector.getTranslationXOfPage(
      pageIndex: from,
      pages: widget.pages,
      containerWidth: containerBounds.maxWidth,
      containerHeight: containerBounds.maxHeight,
    );
    final matrix = controller.value.clone();
    matrix.setTranslationRaw(startX, matrix.getTranslation().y, 0);
    controller.value = matrix;

    final ratio = min(MediaQuery.devicePixelRatioOf(context), 1.25);
    final pageW = front.width / ratio;
    final h = front.height / ratio;
    _flipAnim.value = 0;
    setState(() {
      _bookFront = front;
      _bookBack = back;
      _bookBase = base;
      _bookBaseOnRight = forward;
      _flipForward = forward;
      _flipRect = Rect.fromLTWH(
        (containerBounds.maxWidth - (pageW * 2 + 2)) / 2,
        matrix.getTranslation().y + Editor.gapBetweenPages,
        pageW * 2 + 2,
        h,
      );
    });
    _bookTargetX = targetX;
    try {
      await _flipAnim.forward(from: 0).orCancel;
    } on TickerCanceled {
      return true; // Abgebrochen: _cancelFlip hat das Blatt schon gesetzt.
    }
    if (!mounted || _bookFront != front) return true;
    final end = controller.value.clone();
    end.setTranslationRaw(targetX, end.getTranslation().y, 0);
    controller.value = end;
    _disposeBook();
    setState(() {});
    _endGesture();
    _armPrefetch();
    return true;
  }

  bool _gestureActive = false;
  int _pointersDown = 0;
  int? _startPage;
  int? _pendingPage;

  void _endGesture() {
    _gestureActive = false;
    _startPage = null;
    _armPrefetch();
  }

  /// Index der Seite in der Bildmitte (nur horizontales Blättern).
  int get horizontalPageIndex {
    final transformation = widget._transformationController.value;
    final scale = transformation.approxScale;
    final width = containerBounds.maxWidth;
    if (!width.isFinite || width <= 0) return 0;
    return CanvasGestureDetector.getPageIndexAtX(
      contentX: (-transformation.getTranslation().x + width / 2) / scale,
      pages: widget.pages,
      containerWidth: width,
      containerHeight: containerBounds.maxHeight,
    );
  }

  void _scheduleSnap() {
    if (!widget.horizontal) return;
    _pageSnapTimer?.cancel();
    _pageSnapTimer = Timer(const Duration(milliseconds: 140), _snapToPage);
  }

  void _stopSnap() {
    _pendingTurns = 0;
    _cancelFlip();
    _pageSnapTimer?.cancel();
    _snapAnim.stop();
  }

  void _snapToPage() {
    if (!mounted || !widget.horizontal || widget.pages.isEmpty) {
      _endGesture();
      return;
    }
    if (_pointersDown > 0) return;
    _trace('snap');
    // Läuft schon ein Blättern (oder wird es vorbereitet), darf der Einrast-
    // Timer der Tipp-Geste nicht dagegenarbeiten (sonst springt die Ansicht
    // zurück oder hin und her).
    if (_flipBusy || _turning) return;
    final controller = widget._transformationController;
    final scaleNow = controller.value.approxScale;
    // Bewusst hineingezoomt: Zoom bleibt, bis der Nutzer auf "1.0x" tippt.
    if (scaleNow > 1.06) {
      _endGesture();
      return;
    }
    // Nach einem Zoom (auch leicht darunter/darüber) wieder auf Seitengröße
    // und genau mittig zurückholen.
    if ((scaleNow - 1).abs() > 0.002) {
      _fitCurrentPage(animated: true);
      return;
    }
    final width = containerBounds.maxWidth;
    final start = _startPage ?? horizontalPageIndex;
    final startX = CanvasGestureDetector.getTranslationXOfPage(
      pageIndex: start,
      pages: widget.pages,
      containerWidth: width,
      containerHeight: containerBounds.maxHeight,
    );
    // Umblättern, wenn mehr als ein Siebtel der Breite gezogen wurde.
    final moved = controller.value.getTranslation().x - startX;
    var page = start;
    if (moved < -width / 7) {
      page = CanvasGestureDetector.adjacentPage(
        start,
        1,
        widget.pages.length,
        _spread,
      );
    }
    if (moved > width / 7) {
      page = CanvasGestureDetector.adjacentPage(
        start,
        -1,
        widget.pages.length,
        _spread,
      );
    }
    page = page.clamp(0, widget.pages.length - 1).toInt();
    final target = CanvasGestureDetector.getTranslationXOfPage(
      pageIndex: page,
      pages: widget.pages,
      containerWidth: containerBounds.maxWidth,
      containerHeight: containerBounds.maxHeight,
    );
    _snapFrom = controller.value.getTranslation().x;
    _snapScaleFrom = 1;
    _snapTo = target
        .clamp(min(0.0, containerBounds.maxWidth - _contentWidth), 0.0)
        .toDouble();
    if ((_snapTo - _snapFrom).abs() < 1) {
      _endGesture();
      return;
    }
    if (page != start && !_flipBusy && !_turning) {
      _turnPage(start, page, _snapTo);
      return;
    }
    _snapAnim
      ..reset()
      ..forward();
  }

  bool get _spread =>
      widget.horizontal &&
      CanvasGestureDetector.isSpread(
        containerBounds.maxWidth,
        containerBounds.maxHeight,
      );

  /// Quermodus aktiv (Bild breiter als hoch, horizontales Blättern).
  bool get _landscapeFill =>
      widget.horizontal &&
      containerBounds.maxWidth > containerBounds.maxHeight;

  /// Mindest-Verschiebung y, damit das Seitenende erreichbar bleibt.
  double _minYOfCurrentPage(double scale) {
    if (widget.pages.isEmpty) return 0;
    final first = horizontalPageIndex;
    var h = 0.0;
    for (final i in [first, if (_spread && first > 0) first + 1]) {
      if (i >= widget.pages.length) continue;
      final page = widget.pages[i];
      final w = CanvasGestureDetector._fittedWidth(
        page,
        containerBounds.maxWidth,
        containerBounds.maxHeight,
      );
      h = max(h, w / page.size.width * page.size.height);
    }
    final content = (h + Editor.gapBetweenPages * 2) * scale;
    return min(0.0, containerBounds.maxHeight - content);
  }

  double get _contentWidth =>
      containerBounds.maxWidth *
      CanvasGestureDetector.slotCount(widget.pages.length, _spread);

  /// Setzt Zoom auf 1.0x und zentriert die Seite in der Bildmitte
  /// (nur horizontales Blättern).
  void _fitCurrentPage({required bool animated}) {
    final controller = widget._transformationController;
    final page = horizontalPageIndex;
    final target = CanvasGestureDetector.getTranslationXOfPage(
      pageIndex: page,
      pages: widget.pages,
      containerWidth: containerBounds.maxWidth,
      containerHeight: containerBounds.maxHeight,
    ).clamp(min(0.0, containerBounds.maxWidth - _contentWidth), 0.0).toDouble();
    _snapFrom = controller.value.getTranslation().x;
    _snapTo = target;
    _snapScaleFrom = controller.value.approxScale;
    if (!animated) {
      controller.value = Matrix4.identity()
        ..setTranslationRaw(target, 0, 0);
      _endGesture();
      return;
    }
    _snapAnim
      ..reset()
      ..forward();
  }

  void _onSnapTick() {
    final controller = widget._transformationController;
    final t = Curves.easeOutCubic.transform(_snapAnim.value);
    final x = _snapFrom + (_snapTo - _snapFrom) * t;
    final scale = _snapScaleFrom + (1 - _snapScaleFrom) * t;
    if ((_snapScaleFrom - 1).abs() > 0.002) {
      // Zoom und Position gemeinsam zurückführen, y immer auf 0.
      controller.value = Matrix4.identity()
        ..setTranslationRaw(x, 0, 0)
        ..scaleByDouble(scale, scale, scale, 1);
      return;
    }
    final matrix = controller.value.clone();
    // Quermodus: beim Seitenwechsel sanft nach oben zurück.
    final y = _landscapeFill && (_snapTo - _snapFrom).abs() > 1
        ? matrix.getTranslation().y * (1 - t)
        : matrix.getTranslation().y;
    matrix.setTranslationRaw(x, y, 0);
    controller.value = matrix;
  }

  /// If zooming is locked, this is the zoom level.
  /// Otherwise, this is null.
  late double? zoomLockedValue = stows.lastZoomLock.value
      ? widget._transformationController.value.approxScale
      : null;

  /// Whether single-finger panning is locked.
  /// Two-finger panning is always enabled.
  late bool singleFingerPanLock = stows.lastSingleFingerPanLock.value;

  /// Whether panning is locked to being horizontal or vertical.
  /// Otherwise, panning can be done in any (i.e. diagonal) direction.
  late bool axisAlignedPanLock = stows.lastAxisAlignedPanLock.value;

  void zoomIn() => widget._transformationController.value =
      setZoom(
        scaleDelta: 0.1,
        transformation: widget._transformationController.value,
        containerBounds: containerBounds,
      ) ??
      widget._transformationController.value;
  void zoomOut() => widget._transformationController.value =
      setZoom(
        scaleDelta: -0.1,
        transformation: widget._transformationController.value,
        containerBounds: containerBounds,
      ) ??
      widget._transformationController.value;
  @visibleForTesting
  static Matrix4? setZoom({
    required double scaleDelta,
    required Matrix4 transformation,
    required BoxConstraints containerBounds,
  }) {
    final oldScale = transformation.approxScale;
    final newScale = oldScale + scaleDelta;

    if (newScale < CanvasGestureDetector.kMinScale) return null;
    if (newScale > CanvasGestureDetector.kMaxScale) return null;

    final center = Vector3(
      containerBounds.maxWidth / 2,
      containerBounds.maxHeight / 2,
      0,
    );
    final translation =
        (transformation.getTranslation() - center) * (newScale / oldScale) +
        center;

    return Matrix4.translation(translation)
      ..scaleByDouble(newScale, newScale, newScale, 1);
  }

  final Map<AxisDirection, Timer> _arrowKeyPanTimers = {};
  void arrowKeyPan(AxisDirection direction, bool pressed) {
    _arrowKeyPanTimers.remove(direction)?.cancel();
    if (!pressed) return;

    // arrow keys are used to navigate around text
    if (widget.isTextEditing()) return;

    _arrowKeyPanNow(direction);

    // Wait for 200ms, then pan every 100ms
    const ms100 = Duration(milliseconds: 100);
    const ms200 = Duration(milliseconds: 200);
    _arrowKeyPanTimers[direction] = Timer(ms200, () {
      _arrowKeyPanTimers[direction] = Timer.periodic(ms100, (_) {
        _arrowKeyPanNow(direction);
      });
    });
  }

  void _arrowKeyPanNow(AxisDirection direction) {
    final transformation = widget._transformationController.value;
    const panAmount = 50.0;

    transformation.leftTranslateByDouble(
      switch (direction) {
        .left => panAmount,
        .right => -panAmount,
        .up => 0.0,
        .down => 0.0,
      },
      switch (direction) {
        .left => 0.0,
        .right => 0.0,
        .up => panAmount,
        .down => -panAmount,
      },
      0,
      1,
    );
    widget._transformationController.notifyListenersPlease();
  }

  var _setupKeybindings = false;
  late Keybinding _ctrlPlus, _ctrlEquals, _ctrlMinus;
  late Keybinding _leftKey, _rightKey, _upKey, _downKey;
  void _assignKeybindings() {
    _ctrlPlus = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.add),
    ], inclusive: true);
    _ctrlEquals = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.equal),
    ], inclusive: true);
    _ctrlMinus = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.minus),
    ], inclusive: true);
    Keybinder.bind(_ctrlPlus, zoomIn);
    Keybinder.bind(_ctrlEquals, zoomIn);
    Keybinder.bind(_ctrlMinus, zoomOut);

    _leftKey = Keybinding([
      KeyCode.from(LogicalKeyboardKey.arrowLeft),
    ], inclusive: true);
    _rightKey = Keybinding([
      KeyCode.from(LogicalKeyboardKey.arrowRight),
    ], inclusive: true);
    _upKey = Keybinding([
      KeyCode.from(LogicalKeyboardKey.arrowUp),
    ], inclusive: true);
    _downKey = Keybinding([
      KeyCode.from(LogicalKeyboardKey.arrowDown),
    ], inclusive: true);
    Keybinder.bind(_leftKey, (bool pressed) => arrowKeyPan(.left, pressed));
    Keybinder.bind(_rightKey, (bool pressed) => arrowKeyPan(.right, pressed));
    Keybinder.bind(_upKey, (bool pressed) => arrowKeyPan(.up, pressed));
    Keybinder.bind(_downKey, (bool pressed) => arrowKeyPan(.down, pressed));

    _setupKeybindings = true;
  }

  void _removeKeybindings() {
    if (!_setupKeybindings) return;
    _setupKeybindings = false;

    Keybinder.remove(_ctrlPlus);
    Keybinder.remove(_ctrlEquals);
    Keybinder.remove(_ctrlMinus);

    Keybinder.remove(_leftKey);
    Keybinder.remove(_rightKey);
    Keybinder.remove(_upKey);
    Keybinder.remove(_downKey);
    _arrowKeyPanTimers.forEach((_, timer) => timer.cancel());
  }

  @override
  void initState() {
    setInitialTransform();
    widget._transformationController.addListener(onTransformChanged);
    _assignKeybindings();
    super.initState();
  }

  /// When the widget is created, we still have an empty coreInfo.
  /// Wait for note to be loaded before setting the initial transform.
  @override
  void didUpdateWidget(CanvasGestureDetector oldWidget) {
    if (oldWidget.initialPageIndex != widget.initialPageIndex ||
        oldWidget.filePath != widget.filePath) {
      setInitialTransform();
    }
    super.didUpdateWidget(oldWidget);
  }

  /// Sets the initial transform so that we're scrolled to the correct page.
  /// Has no effect if note hasn't yet loaded or if the user has already scrolled.
  void setInitialTransform() {
    // wait for note to be loaded
    if (widget.filePath.isEmpty) return;

    // don't override user's scroll
    if (!widget._transformationController.value.isIdentity()) return;

    final transformCacheItem = CanvasTransformCache.get(widget.filePath);

    if (transformCacheItem != null) {
      // if we're opening the same note, restore the last transform
      widget._transformationController.value = transformCacheItem.transform;
      if (zoomLockedValue != null) {
        zoomLockedValue = transformCacheItem.transform.approxScale;
      }
    } else if (widget.initialPageIndex != null && widget.horizontal) {
      // Echte Maße der Fläche verwenden (sonst sitzt die Ansicht schief).
      // Gibt es sie noch nicht, wird nach dem ersten Layout positioniert.
      final known =
          containerBounds.maxWidth.isFinite && containerBounds.maxHeight.isFinite;
      if (known) {
        CanvasGestureDetector.scrollToPageHorizontal(
          pageIndex: widget.initialPageIndex!,
          pages: widget.pages,
          containerWidth: containerBounds.maxWidth,
          containerHeight: containerBounds.maxHeight,
          transformationController: widget._transformationController,
        );
      } else {
        _pendingPage = widget.initialPageIndex;
        CanvasGestureDetector.scrollToPageHorizontal(
          pageIndex: widget.initialPageIndex!,
          pages: widget.pages,
          containerWidth: MediaQuery.sizeOf(context).width,
          containerHeight: MediaQuery.sizeOf(context).height * 0.85,
          transformationController: widget._transformationController,
        );
      }
    } else if (widget.initialPageIndex != null) {
      // if we're opening a different note, scroll to the last recorded page
      CanvasGestureDetector.scrollToPage(
        pageIndex: widget.initialPageIndex!,
        pages: widget.pages,
        screenWidth: MediaQuery.sizeOf(context).width,
        transformationController: widget._transformationController,
      );
    }
  }

  Timer? _snapZoomTimer;

  /// Corrects the transform if it's out of bounds.
  /// If the scale is less than 1, centers the pages horizontally.
  /// Otherwise, prevents the user from scrolling past the edges.
  void onTransformChanged() {
    final scale = widget._transformationController.value.approxScale;
    final translation = widget._transformationController.value.getTranslation();

    double adjustmentX = 0;
    double adjustmentY = 0;

    if (widget.horizontal) {
      // Während der Rückführ-Animation nicht eingreifen.
      if (_snapAnim.isAnimating) return;
      if (!_flipBusy) _scheduleSnap();
      final contentWidth = _contentWidth * scale;
      final minX = min(0.0, containerBounds.maxWidth - contentWidth);
      if (translation.x > 0) {
        adjustmentX = -translation.x;
      } else if (translation.x < minX) {
        adjustmentX = minX - translation.x;
      }
      // Eine Seite füllt das Bild: senkrecht festhalten, solange nicht gezoomt.
      if (_landscapeFill) {
        final minY = _minYOfCurrentPage(scale);
        if (translation.y > 0) {
          adjustmentY = -translation.y;
        } else if (translation.y < minY) {
          adjustmentY = minY - translation.y;
        }
      } else if ((scale - 1).abs() < 0.06) {
        adjustmentY = -translation.y;
      } else if (translation.y > 0) {
        adjustmentY = -translation.y;
      }

      // Blättern: während einer Geste höchstens eine Seite weit ziehen.
      if (_gestureActive &&
          widget.pages.isNotEmpty &&
          (scale - 1).abs() < 0.06) {
        final start = _startPage ??= horizontalPageIndex;
        final lo = CanvasGestureDetector.getTranslationXOfPage(
          pageIndex: CanvasGestureDetector.adjacentPage(
            start,
            1,
            widget.pages.length,
            _spread,
          ),
          pages: widget.pages,
          containerWidth: containerBounds.maxWidth,
      containerHeight: containerBounds.maxHeight,
        );
        final hi = CanvasGestureDetector.getTranslationXOfPage(
          pageIndex: CanvasGestureDetector.adjacentPage(
            start,
            -1,
            widget.pages.length,
            _spread,
          ),
          pages: widget.pages,
          containerWidth: containerBounds.maxWidth,
      containerHeight: containerBounds.maxHeight,
        );
        final x = translation.x + adjustmentX;
        if (x < lo) {
          adjustmentX += lo - x;
        } else if (x > hi) {
          adjustmentX += hi - x;
        }
      }
      if (adjustmentX.abs() > 0.1 || adjustmentY.abs() > 0.1) {
        widget._transformationController.value.leftTranslateByDouble(
          adjustmentX,
          adjustmentY,
          0,
          1,
        );
      }
      return;
    }

    // Feder: zwischen einer und zwei Seiten pro Zeile umschalten.
    final wantTwoUp = _wantTwoUp(scale);
    if (wantTwoUp != twoUp) {
      final yTop = -translation.y / scale;
      final cw = containerBounds.maxWidth;
      int anchor = 0;
      for (int i = 0; i < widget.pages.length; i++) {
        final top =
            CanvasGestureDetector.getTopOfPage(
              pageIndex: i,
              pages: widget.pages,
              screenWidth: cw,
              twoUp: twoUp,
            ) +
            Editor.gapBetweenPages * 2;
        if (top <= yTop) anchor = i;
      }
      double topOf(bool up) =>
          CanvasGestureDetector.getTopOfPage(
            pageIndex: anchor,
            pages: widget.pages,
            screenWidth: cw,
            twoUp: up,
          ) +
          Editor.gapBetweenPages * 2;
      final newY = max(0.0, topOf(wantTwoUp) + (yTop - topOf(twoUp)));
      adjustmentY = -newY * scale - translation.y;
      twoUp = wantTwoUp;
      if (mounted) setState(() {});
    }

    // snap to 1.0x zoom
    _snapZoomTimer?.cancel();
    final diffFrom1 = (scale - 1).abs();
    // allow 0.001 leeway for floating point error
    if (diffFrom1 < 0.05 && diffFrom1 > 0.001)
      _snapZoomTimer = Timer(const Duration(milliseconds: 200), resetZoom);

    final contentWidth = twoUp
        ? CanvasGestureDetector.twoUpContentWidth(
            widget.pages,
            containerBounds.maxWidth,
          )
        : containerBounds.maxWidth;
    if (contentWidth * scale <= containerBounds.maxWidth) {
      // horizontally center pages if zoomed out
      final center = (containerBounds.maxWidth - contentWidth * scale) / 2;
      adjustmentX = center - translation.x;
    } else {
      // if zoomed in, don't allow scrolling past the edges
      final minX = containerBounds.maxWidth - contentWidth * scale;
      if (translation.x > 0) {
        adjustmentX = -translation.x;
      } else if (translation.x < minX) {
        adjustmentX = minX - translation.x;
      }
    }
    if (scale >= 1 && translation.y > 0) {
      adjustmentY = -translation.y;
    }

    if (adjustmentX.abs() > 0.1 || adjustmentY.abs() > 0.1) {
      widget._transformationController.value.leftTranslateByDouble(
        adjustmentX,
        adjustmentY,
        0,
        1,
      );
    }
  }

  /// Zurück zu einer Seite pro Zeile, ohne die Ansicht umzurechnen
  /// (vor einem Sprung zu einer Seite).
  void forceSingleColumn() {
    if (!twoUp) return;
    twoUp = false;
    if (mounted) setState(() {});
  }

  /// Zwei Seiten nebeneinander, sobald sie bei diesem Zoom beide ins Bild
  /// passen (Querformat). Der Rückweg liegt etwas höher, damit es nicht flackert.
  bool _wantTwoUp(double scale) {
    final cw = containerBounds.maxWidth;
    final ch = containerBounds.maxHeight;
    if (widget.horizontal ||
        widget.pages.length < 2 ||
        !cw.isFinite ||
        !ch.isFinite ||
        cw <= ch) {
      return false;
    }
    final needed =
        CanvasGestureDetector.twoUpContentWidth(widget.pages, cw) + 24;
    final enter = min(cw / needed, 0.95);
    final exit = min(enter * 1.35, 1.05);
    return twoUp ? scale < exit : scale <= enter;
  }

  /// Resets the zoom level to 1.0x
  void resetZoom() {
    final transformation = widget._transformationController.value;
    final scale = transformation.approxScale;
    if (widget.horizontal && widget.pages.isNotEmpty) {
      _stopSnap();
      _fitCurrentPage(animated: true);
      return;
    }
    if (scale == 1) return;

    widget._transformationController.value =
        setZoom(
          scaleDelta: 1 - scale,
          transformation: transformation,
          containerBounds: containerBounds,
        ) ??
        transformation;
  }

  void _listenerPointerEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _tapMove(event);
    final isStylus =
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    if (event is PointerDownEvent) {
      _trace('down ${event.kind.name}');
      _pointersDown++;
      _tapDown(event);
      _stopSnap();
      if (widget.horizontal) {
        _gestureActive = true;
        _startPage = null;
      }
    }
    if (isStylus && event is PointerDownEvent) {
      _detectStylusButton(event);
    }

    final double? pressure;
    if (isStylus) {
      if (event.pressureMin != event.pressureMax) {
        pressure = applyPressureCurve(
          _inverseLerp(
            event.pressure,
            min: event.pressureMin,
            max: event.pressureMax,
          ),
        );
      } else {
        // Detected as stylus, but no pressure values
        pressure = null;
      }
    } else {
      pressure = null;
    }
    widget.updatePointerData(event.kind, pressure);

    if (isStylus &&
        stows.autoDisableFingerDrawingWhenStylusDetected.value &&
        // Don't change if the user has a fixed value for finger drawing
        !stows.hideFingerDrawingToggle.value) {
      stows.editorFingerDrawing.value = false;
    }
  }

  var stylusButtonWasPressed = false;

  // Tipp mit dem Finger an den Seitenrand = umblättern (nur horizontal).
  int? _tapPointer;
  Offset _tapStart = Offset.zero;
  DateTime _tapTime = DateTime.now();

  void _tapDown(PointerDownEvent event) {
    if (!widget.horizontal ||
        event.kind != PointerDeviceKind.touch ||
        stows.editorFingerDrawing.value ||
        _tapPointer != null) {
      _tapPointer = null;
      return;
    }
    _tapPointer = event.pointer;
    _tapStart = event.position;
    _tapTime = DateTime.now();
  }

  void _tapMove(PointerMoveEvent event) {
    if (event.pointer == _tapPointer &&
        (event.position - _tapStart).distance > 14) {
      _tapPointer = null;
    }
  }

  void _tapUp(PointerUpEvent event) {
    if (event.pointer != _tapPointer) return;
    _tapPointer = null;
    if (DateTime.now().difference(_tapTime).inMilliseconds > 300) return;
    if ((widget._transformationController.value.approxScale - 1).abs() > 0.06) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final x = box.globalToLocal(event.position).dx;
    final width = box.size.width;
    _trace('tapUp x=${x.toStringAsFixed(0)}/${width.toStringAsFixed(0)}');
    // Doppelblatt: Tippen auf die rechte/linke Buchseite blättert.
    final zone = _spread ? 0.35 : 0.18;
    if (x > width * (1 - zone)) {
      turnBy(1);
    } else if (x < width * zone) {
      turnBy(-1);
    }
  }

  void _listenerPointerHoverEvent(PointerEvent event) {
    if (event.kind != .stylus && event.kind != .invertedStylus) return;

    // Apparently flutter synthesizes a hover event on pointer down,
    // so these are used to detect when hovering ends
    if (event.synthesized) {
      widget.onHoveringEnd();
    } else {
      widget.onHovering();
    }

    _detectStylusButton(event);
  }

  void _detectStylusButton(PointerEvent event) {
    final pressed =
        event.buttons == kSecondaryButton || event.kind == .invertedStylus;
    if (stylusButtonWasPressed != pressed) {
      stylusButtonWasPressed = pressed;
      widget.onStylusButtonChanged(pressed);
    }
  }

  void _listenerPointerUpEvent(PointerEvent event) {
    _pointersDown = max(0, _pointersDown - 1);
    if (event is PointerUpEvent) _tapUp(event);
    _scheduleSnap();
    widget.updatePointerData(event.kind, null);
    if (stylusButtonWasPressed) {
      stylusButtonWasPressed = false;
      widget.onStylusButtonChanged(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    return Stack(
      children: [
        Listener(
          onPointerDown: _listenerPointerEvent,
          onPointerMove: _listenerPointerEvent,
          onPointerUp: _listenerPointerUpEvent,
          onPointerCancel: _listenerPointerUpEvent,
          onPointerHover: _listenerPointerHoverEvent,
          child: GestureDetector(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints containerBounds) {
                // Ändert sich die Fläche (Drehen, erstes Layout), bleibt die
                // Ansicht auf demselben Blatt und sitzt passgenau.
                final old = this.containerBounds;
                final changed =
                    old.maxWidth != containerBounds.maxWidth ||
                    old.maxHeight != containerBounds.maxHeight;
                int? keepPage;
                if (changed &&
                    widget.horizontal &&
                    old.maxWidth.isFinite &&
                    old.maxHeight.isFinite &&
                    old.maxWidth > 0) {
                  keepPage = horizontalPageIndex;
                }
                this.containerBounds = containerBounds;
                if (changed &&
                    widget.horizontal &&
                    containerBounds.maxWidth.isFinite &&
                    containerBounds.maxHeight.isFinite) {
                  final page = keepPage ?? _pendingPage;
                  _pendingPage = null;
                  final bounds = containerBounds;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || widget.pages.isEmpty) return;
                    if (page != null) {
                      CanvasGestureDetector.scrollToPageHorizontal(
                        pageIndex: page,
                        pages: widget.pages,
                        containerWidth: bounds.maxWidth,
                        containerHeight: bounds.maxHeight,
                        transformationController:
                            widget._transformationController,
                      );
                    } else {
                      _scheduleSnap();
                    }
                    _armPrefetch();
                  });
                }

                return InteractiveCanvasViewer.builder(
                  minScale: zoomLockedValue ?? CanvasGestureDetector.kMinScale,
                  maxScale: zoomLockedValue ?? CanvasGestureDetector.kMaxScale,
                  panEnabled: !singleFingerPanLock,
                  panAxis: axisAlignedPanLock ? .aligned : .free,

                  // Smoother scrolling fling gesture than the default
                  interactionEndFrictionCoefficient: 0.1,

                  // we need a non-zero boundary margin so we can zoom out
                  // past the size of the page (for minScale < 1)
                  boundaryMargin: .symmetric(
                    vertical: 0,
                    horizontal: screenSize.width * 2,
                  ),

                  transformationController: widget._transformationController,

                  isDrawGesture: widget.isDrawGesture,
                  unboundedWidth: widget.horizontal || twoUp,
                  onInteractionEnd: (details) {
                    widget.onInteractionEnd?.call(details);
                    _scheduleSnap();
                  },
                  onDrawStart: widget.onDrawStart,
                  onDrawUpdate: widget.onDrawUpdate,
                  onDrawEnd: widget.onDrawEnd,

                  builder: (BuildContext context, Quad viewport) {
                    return _PagesBuilder(
                      pages: widget.pages,
                      pageBuilder: widget.pageBuilder,
                      placeholderPageBuilder: widget.placeholderPageBuilder,
                      boundingBox: _axisAlignedBoundingBox(viewport),
                      containerWidth: containerBounds.maxWidth,
                      containerHeight: containerBounds.maxHeight,
                      horizontal: widget.horizontal,
                      twoUp: twoUp,
                      prefetchSlot: _prefetchSlot,
                      pageKeyFor: _pageKeyFor,
                    );
                  },
                );
              },
            ),
          ),
        ),
        if (_bookFront != null)
          Positioned.fromRect(
            rect: _flipRect,
            child: IgnorePointer(
              child: CustomPaint(
                painter: BookFlipPainter(
                  front: _bookFront!,
                  back: _bookBack!,
                  base: _bookBase!,
                  baseOnRight: _bookBaseOnRight,
                  animation: _flipAnim,
                  forward: _flipForward,
                ),
              ),
            ),
          ),
        if (_flipImage != null)
          Positioned.fromRect(
            rect: _flipRect,
            child: IgnorePointer(
              child: CustomPaint(
                painter: PageCurlPainter(
                  image: _flipImage!,
                  animation: _flipAnim,
                  forward: _flipForward,
                  leftBlank: _flipLeftBlank,
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: CanvasHud(
            transformationController: widget._transformationController,
            zoomLock: zoomLockedValue != null,
            setZoomLock: (bool zoomLock) => setState(() {
              zoomLockedValue = zoomLock
                  ? widget._transformationController.value.approxScale
                  : null;
              stows.lastZoomLock.value = zoomLock;
            }),
            resetZoom: zoomLockedValue != null ? null : resetZoom,
            singleFingerPanLock: singleFingerPanLock,
            setSingleFingerPanLock: (bool singleFingerPanLock) => setState(() {
              this.singleFingerPanLock = singleFingerPanLock;
              stows.lastSingleFingerPanLock.value = singleFingerPanLock;
            }),
            axisAlignedPanLock: axisAlignedPanLock,
            setAxisAlignedPanLock: (bool axisAlignedPanLock) => setState(() {
              this.axisAlignedPanLock = axisAlignedPanLock;
              stows.lastAxisAlignedPanLock.value = axisAlignedPanLock;
            }),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    CanvasTransformCache.add(
      widget.filePath,
      widget._transformationController.value,
    );
    _pageSnapTimer?.cancel();
    _flipImage?.dispose();
    _disposeBook();
    _prefetchTimer?.cancel();
    _flipAnim.dispose();
    _snapAnim.dispose();
    widget._transformationController.removeListener(onTransformChanged);
    widget._transformationController.dispose();
    _removeKeybindings();
    super.dispose();
  }

  /// Returns the axis aligned bounding box for the given Quad,
  /// which might not be axis aligned.
  /// From https://api.flutter.dev/flutter/widgets/InteractiveViewer/builder.html
  static Rect _axisAlignedBoundingBox(Quad quad) {
    final List<Vector3> points = [
      quad.point0,
      quad.point1,
      quad.point2,
      quad.point3,
    ];

    final left = points.map((point) => point.x).reduce(min);
    final right = points.map((point) => point.x).reduce(max);
    final top = points.map((point) => point.y).reduce(min);
    final bottom = points.map((point) => point.y).reduce(max);

    return .fromLTRB(left, top, right, bottom);
  }
}

class _PagesBuilder extends StatelessWidget {
  const new({
    required this.pages,
    required this.pageBuilder,
    required this.placeholderPageBuilder,
    required this.boundingBox,
    required this.containerWidth,
    this.containerHeight = double.infinity,
    this.horizontal = false,
    this.twoUp = false,
    this.prefetchSlot,
    this.pageKeyFor,
  });

  final GlobalKey Function(int index)? pageKeyFor;
  final List<EditorPage> pages;
  final Widget Function(BuildContext context, int pageIndex) pageBuilder;
  final Widget Function(BuildContext context, int pageIndex)
  placeholderPageBuilder;
  final Rect boundingBox;
  final double containerWidth;
  final double containerHeight;
  final bool horizontal;
  final bool twoUp;

  /// Doppelblatt: Fach, dessen Nachbarn vorgerendert werden dürfen.
  final int? prefetchSlot;

  Widget _buildTwoUp(BuildContext context) {
    final rows = <Widget>[
      const SizedBox.square(dimension: Editor.gapBetweenPages),
      const SizedBox.square(dimension: Editor.gapBetweenPages),
    ];
    double topOfRow = Editor.gapBetweenPages * 2;
    for (var first = 0; first < pages.length; first += 2) {
      final indices = [first, if (first + 1 < pages.length) first + 1];
      var rowHeight = 0.0;
      final cells = <Widget>[];
      final sizes = <(double, double)>[];
      for (final i in indices) {
        final w = min(pages[i].size.width, containerWidth);
        final h = w / pages[i].size.width * pages[i].size.height;
        sizes.add((w, h));
        rowHeight = max(rowHeight, h);
      }
      final bottomOfRow = topOfRow + rowHeight;
      for (var k = 0; k < indices.length; k++) {
        final i = indices[k];
        final page = pages[i];
        final isInViewport =
            boundingBox.bottom >= topOfRow && boundingBox.top <= bottomOfRow;
        final shouldRender = page.hasTextFocus || isInViewport;
        page.isRendered = shouldRender;
        if (k > 0) cells.add(const SizedBox(width: Editor.gapBetweenPages));
        cells.add(
          SizedBox(
            width: sizes[k].$1,
            height: sizes[k].$2,
            child: shouldRender
                ? pageBuilder(context, i)
                : placeholderPageBuilder(context, i),
          ),
        );
      }
      rows.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: cells,
        ),
      );
      rows.add(const SizedBox.square(dimension: Editor.gapBetweenPages));
      topOfRow = bottomOfRow + Editor.gapBetweenPages;
    }
    rows.add(const SizedBox.square(dimension: Editor.gapBetweenPages));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: rows,
    );
  }

  /// Feder: Buch-Doppelblatt. Seite 1 steht allein rechts, dann 2/3, 4/5 …
  Widget _buildSpread(BuildContext context) {
    final slots = CanvasGestureDetector.slotCount(pages.length, true);
    final children = <Widget>[];
    for (var slot = 0; slot < slots; slot++) {
      final first = CanvasGestureDetector.firstPageOfSlot(slot, true);
      // Index der Seiten links und rechts (null = leer).
      final int? leftPage = slot == 0 ? null : first;
      int? rightPage = slot == 0 ? 0 : first + 1;
      if (rightPage != null && rightPage >= pages.length) rightPage = null;
      final leftOfSlot = slot * containerWidth;
      // Nur das sichtbare Fach rendern (schneller Aufbau); die Nachbarn erst,
      // wenn Ruhe herrscht (prefetchSlot) oder wenn gewischt wird.
      final near = prefetchSlot != null && (slot - prefetchSlot!).abs() <= 1;
      final isInViewport =
          near ||
          (boundingBox.right >= leftOfSlot + 4 &&
              boundingBox.left <= leftOfSlot + containerWidth - 4);

      Widget cell(int? index, int sizeFrom) {
        final ref = pages[min(sizeFrom, pages.length - 1)];
        final w = CanvasGestureDetector._fittedWidth(
          ref,
          containerWidth,
          containerHeight,
        );
        final h = w / ref.size.width * ref.size.height;
        if (index == null) return SizedBox(width: w, height: h);
        final page = pages[index];
        final shouldRender = page.hasTextFocus || isInViewport;
        page.isRendered = shouldRender;
        return SizedBox(
          width: w,
          height: h,
          child: RepaintBoundary(
            key: pageKeyFor?.call(index),
            child: shouldRender
                ? pageBuilder(context, index)
                : placeholderPageBuilder(context, index),
          ),
        );
      }

      final sizeFrom = leftPage ?? rightPage ?? 0;
      children.add(
        SizedBox(
          width: containerWidth,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cell(leftPage, sizeFrom),
                const SizedBox(width: 2),
                cell(rightPage, rightPage ?? sizeFrom),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: Editor.gapBetweenPages),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildHorizontal(BuildContext context) {
    final children = <Widget>[];
    for (int pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final page = pages[pageIndex];
      final pageWidth = CanvasGestureDetector._fittedWidth(
        page,
        containerWidth,
        containerHeight,
      );
      final pageHeight = pageWidth / page.size.width * page.size.height;
      final leftOfSlot = pageIndex * containerWidth;

      final isFocused = page.hasTextFocus;
      final isInViewport =
          boundingBox.right >= leftOfSlot - containerWidth * 0.2 &&
          boundingBox.left <= leftOfSlot + containerWidth * 1.2;
      final shouldRender = isFocused || isInViewport;

      page.isRendered = shouldRender;
      children.add(
        SizedBox(
          width: containerWidth,
          child: Center(
            child: SizedBox(
              width: pageWidth,
              height: pageHeight,
              child: RepaintBoundary(
                key: pageKeyFor?.call(pageIndex),
                child: shouldRender
                    ? pageBuilder(context, pageIndex)
                    : placeholderPageBuilder(context, pageIndex),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const .only(top: Editor.gapBetweenPages),
      child: Row(crossAxisAlignment: .start, children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (horizontal &&
        CanvasGestureDetector.isSpread(containerWidth, containerHeight)) {
      return _buildSpread(context);
    }
    if (horizontal) return _buildHorizontal(context);
    if (twoUp) return _buildTwoUp(context);
    final List<Widget> children = [
      const SizedBox.square(dimension: Editor.gapBetweenPages),
      const SizedBox.square(dimension: Editor.gapBetweenPages),
    ];

    double topOfPage = Editor.gapBetweenPages * 2;
    for (int pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final page = pages[pageIndex];
      final pageWidth = min(
        page.size.width,
        containerWidth,
      ); // because of FittedBox
      final pageHeight = pageWidth / page.size.width * page.size.height;
      final bottomOfPage = topOfPage + pageHeight;

      final isFocused = page.hasTextFocus;
      final isInViewport =
          boundingBox.bottom >= topOfPage && boundingBox.top <= bottomOfPage;
      final shouldRender = isFocused || isInViewport;

      page.isRendered = shouldRender;
      children.add(
        shouldRender
            ? pageBuilder(context, pageIndex)
            : placeholderPageBuilder(context, pageIndex),
      );

      children.add(const SizedBox.square(dimension: Editor.gapBetweenPages));

      topOfPage = bottomOfPage + Editor.gapBetweenPages;
    }

    children.add(const SizedBox.square(dimension: Editor.gapBetweenPages));
    return Column(children: children);
  }
}

@visibleForTesting
class CanvasTransformCache {
  static const _maxCacheSize = 5;
  static final _cache = LinkedList<CanvasTransformCacheItem>();

  new _();

  static void add(String filePath, Matrix4 transform) {
    for (final entry in _cache) {
      if (entry.filePath != filePath) continue;
      entry.unlink();
      break;
    }
    _cache.add(CanvasTransformCacheItem(filePath, transform));

    if (_cache.length > _maxCacheSize) {
      _cache.first.unlink();
    }
  }

  static CanvasTransformCacheItem? get(String filePath) {
    try {
      return _cache.firstWhere((item) => item.filePath == filePath);
    } on StateError {
      return null;
    }
  }

  @visibleForTesting
  static void clear() {
    _cache.clear();
  }
}

@visibleForTesting
base class CanvasTransformCacheItem
    extends LinkedListEntry<CanvasTransformCacheItem> {
  final String filePath;
  final Matrix4 transform;

  new(this.filePath, this.transform);
}

double _inverseLerp(num value, {required num min, required num max}) {
  assert(max >= min, 'Max ($max) must be >= min ($min)');
  assert(
    value >= min && value <= max,
    'Value ($value) must be between $min and $max',
  );
  return (value - min) / (max - min);
}
