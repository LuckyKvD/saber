import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:keybinder/keybinder.dart';
import 'package:material_ui/material_ui.dart';
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
  }) {
    if (pageIndex <= 0) return 0;

    double top = 0;

    for (int i = 0; i < pageIndex && i < pages.length; i++) {
      final pageSize = pages[i].size;

      /// Since we use a FittedBox, the actual width of the page
      /// is the minimum of the page width and the screen width.
      final pageWidthFitted = min(pageSize.width, screenWidth);

      top += 16;
      top += pageSize.height * (pageWidthFitted / pageSize.width);
    }

    return top;
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

  /// Horizontal: die Seite passt komplett ins Bild (Breite und Höhe).
  static double _fittedWidth(
    EditorPage page,
    double containerWidth, [
    double containerHeight = double.infinity,
  ]) => min(
    min(page.size.width, containerWidth),
    (containerHeight - Editor.gapBetweenPages * 2) *
        page.size.width /
        page.size.height,
  );

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
    return index * containerWidth + (containerWidth - width) / 2;
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
    return -index * containerWidth;
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
    return (contentX / containerWidth)
        .floor()
        .clamp(0, pages.length - 1)
        .toInt();
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
  late var containerBounds = const BoxConstraints();

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
    duration: const Duration(milliseconds: 420),
  );
  ui.Image? _flipImage;
  var _flipForward = true;
  var _flipRect = Rect.zero;

  Future<ui.Image?> _capturePage(int index) async {
    final object = _pageKeys[index]?.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    try {
      return await object.toImage(
        pixelRatio: min(MediaQuery.devicePixelRatioOf(context), 2.0),
      );
    } catch (_) {
      return null;
    }
  }

  void _cancelFlip() {
    if (_flipImage == null) return;
    _flipAnim.stop();
    _flipImage?.dispose();
    _flipImage = null;
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
    if (!widget.horizontal || widget.pages.isEmpty || _flipImage != null) {
      return;
    }
    final start = horizontalPageIndex;
    final page = (start + delta).clamp(0, widget.pages.length - 1).toInt();
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

  Future<void> _turnPage(int from, int to, double targetX) async {
    final forward = to > from;
    _playFlipSound();
    final image = await _capturePage(forward ? from : to);
    if (!mounted) {
      image?.dispose();
      return;
    }
    final controller = widget._transformationController;
    if (image == null) {
      // Ersatz: einfaches seitliches Umschalten.
      _snapFrom = controller.value.getTranslation().x;
      _snapTo = targetX;
      _snapScaleFrom = 1;
      _snapAnim
        ..reset()
        ..forward();
      return;
    }
    final matrix = controller.value.clone();
    matrix.setTranslationRaw(targetX, matrix.getTranslation().y, 0);
    controller.value = matrix;

    final ratio = min(MediaQuery.devicePixelRatioOf(context), 2.0);
    final w = image.width / ratio;
    final h = image.height / ratio;
    setState(() {
      _flipImage = image;
      _flipForward = forward;
      _flipRect = Rect.fromLTWH(
        (containerBounds.maxWidth - w) / 2,
        matrix.getTranslation().y + Editor.gapBetweenPages,
        w,
        h,
      );
    });
    await _flipAnim.forward(from: 0);
    if (!mounted || _flipImage != image) return;
    _flipImage?.dispose();
    setState(() => _flipImage = null);
    _endGesture();
  }

  bool _gestureActive = false;
  int _pointersDown = 0;
  int? _startPage;

  void _endGesture() {
    _gestureActive = false;
    _startPage = null;
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
    if (moved < -width / 7) page = start + 1;
    if (moved > width / 7) page = start - 1;
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
    if (page != start && _flipImage == null) {
      _turnPage(start, page, _snapTo);
      return;
    }
    _snapAnim
      ..reset()
      ..forward();
  }

  double get _contentWidth => containerBounds.maxWidth * widget.pages.length;

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
    matrix.setTranslationRaw(x, matrix.getTranslation().y, 0);
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
      CanvasGestureDetector.scrollToPageHorizontal(
        pageIndex: widget.initialPageIndex!,
        pages: widget.pages,
        containerWidth: MediaQuery.sizeOf(context).width,
        containerHeight: MediaQuery.sizeOf(context).height * 0.85,
        transformationController: widget._transformationController,
      );
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
      if (_flipImage == null) _scheduleSnap();
      final contentWidth = _contentWidth * scale;
      final minX = min(0.0, containerBounds.maxWidth - contentWidth);
      if (translation.x > 0) {
        adjustmentX = -translation.x;
      } else if (translation.x < minX) {
        adjustmentX = minX - translation.x;
      }
      // Eine Seite füllt das Bild: senkrecht festhalten, solange nicht gezoomt.
      if ((scale - 1).abs() < 0.06) {
        adjustmentY = -translation.y;
      } else if (translation.y > 0) {
        adjustmentY = -translation.y;
      }

      // Blättern: während einer Geste höchstens eine Seite weit ziehen.
      if (_gestureActive &&
          widget.pages.isNotEmpty &&
          (scale - 1).abs() < 0.06) {
        final start = _startPage ??= horizontalPageIndex;
        final last = widget.pages.length - 1;
        final lo = CanvasGestureDetector.getTranslationXOfPage(
          pageIndex: min(start + 1, last),
          pages: widget.pages,
          containerWidth: containerBounds.maxWidth,
      containerHeight: containerBounds.maxHeight,
        );
        final hi = CanvasGestureDetector.getTranslationXOfPage(
          pageIndex: max(start - 1, 0),
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

    // snap to 1.0x zoom
    _snapZoomTimer?.cancel();
    final diffFrom1 = (scale - 1).abs();
    // allow 0.001 leeway for floating point error
    if (diffFrom1 < 0.05 && diffFrom1 > 0.001)
      _snapZoomTimer = Timer(const Duration(milliseconds: 200), resetZoom);

    if (scale < 1) {
      // horizontally center pages if zoomed out
      final center = containerBounds.maxWidth * (1 - scale) / 2;
      adjustmentX = center - translation.x;
    } else {
      // if zoomed in, don't allow scrolling past the edges
      late final minX = containerBounds.maxWidth * (1 - scale);
      if (translation.x > 0) {
        adjustmentX = -translation.x;
      } else if (translation.x < minX) {
        adjustmentX = minX - translation.x;
      }

      if (translation.y > 0) {
        adjustmentY = -translation.y;
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
    if (x > width * 0.82) {
      turnBy(1);
    } else if (x < width * 0.18) {
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
                this.containerBounds = containerBounds;

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
                  unboundedWidth: widget.horizontal,
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
                      pageKeyFor: _pageKeyFor,
                    );
                  },
                );
              },
            ),
          ),
        ),
        if (_flipImage != null)
          Positioned.fromRect(
            rect: _flipRect,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _flipAnim,
                builder: (context, _) {
                  final t = Curves.easeInOut.transform(_flipAnim.value);
                  final theta = (_flipForward ? t : 1 - t) * pi / 2;
                  return Transform(
                    alignment: Alignment.centerLeft,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateY(theta),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RawImage(image: _flipImage, fit: BoxFit.fill),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(
                              alpha: 0.35 * theta / (pi / 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
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

      final isFocused = page.quill.focusNode.hasFocus;
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
    if (horizontal) return _buildHorizontal(context);
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

      final isFocused = page.quill.focusNode.hasFocus;
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
