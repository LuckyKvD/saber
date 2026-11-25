import 'dart:math';

import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/canvas_image_dialog.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/image/image_clip.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/data/extensions/change_notifier_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

class CanvasImage extends StatefulHookWidget {
  new({
    required this.filePath,
    required this.image,
    this.overrideBoxFit,
    required this.pageSize,
    required this.setAsBackground,
    this.isBackground = false,
    this.readOnly = false,
    this.selected = false,
    this.acceptStylus = true,
  }) : super(key: Key('CanvasImage$filePath/${image.id}'));

  /// The path to the note that this image is in.
  final String filePath;
  final EditorImage image;
  final BoxFit? overrideBoxFit;
  final Size pageSize;
  final void Function(EditorImage image)? setAsBackground;
  final bool isBackground;
  final bool readOnly;
  final bool selected;

  /// Reagiert das Foto auf den Stift? Nur mit dem Lasso-Werkzeug; sonst
  /// schreibt der Stift über das Foto.
  final bool acceptStylus;

  /// When notified, all [CanvasImages] will have their [active] property set to false.
  static var activeListener = ChangeNotifier();

  /// The minimum size of the interactive area for the image.
  static double minInteractiveSize = 50;

  /// The minimum size of the image itself, inside of the interactive area.
  static double minImageSize = 10;

  @override
  State<CanvasImage> createState() => _CanvasImageState();
}

class _CanvasImageState extends State<CanvasImage> {
  var _active = false;

  /// Whether this image can be dragged
  bool get active => _active;
  set active(bool value) {
    if (active == value) return;

    if (value) {
      CanvasImage.activeListener
          .notifyListenersPlease(); // de-activate all other images
    }

    _active = value;

    if (mounted) {
      try {
        setState(() {});
      } catch (e) {
        // setState throws error if widget is currently building
      }
    }
  }

  Brightness imageBrightness = .light;

  Rect panStartRect = .zero;
  Offset panStartPosition = .zero;

  // Beim Ziehen liegt das Foto in einer Ebene über allen Seiten,
  // damit es auch über die Seitengrenze hinweg sichtbar bleibt.
  OverlayEntry? _dragEntry;
  Offset _dragCenter = Offset.zero;
  Offset _dragGrab = Offset.zero;
  Size _dragSize = Size.zero;
  double _dragScale = 1;
  Widget? _dragContent;

  void _startDragOverlay(DragStartDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context);
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final unit = box.localToGlobal(const Offset(1, 0)) - origin;
    _dragScale = unit.dx;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    _dragCenter = center;
    _dragGrab = center - details.globalPosition;
    _dragSize = widget.image.dstRect.size;
    _dragEntry = OverlayEntry(
      builder: (context) {
        final w = _dragSize.width, h = _dragSize.height;
        return Positioned(
          left: _dragCenter.dx - w * _dragScale / 2,
          top: _dragCenter.dy - h * _dragScale / 2,
          width: w * _dragScale,
          height: h * _dragScale,
          child: IgnorePointer(
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(width: w, height: h, child: _dragContent),
            ),
          ),
        );
      },
    );
    overlay.insert(_dragEntry!);
  }

  void _updateDragOverlay(DragUpdateDetails details) {
    if (_dragEntry == null) return;
    _dragCenter = details.globalPosition + _dragGrab;
    _dragEntry!.markNeedsBuild();
  }

  void _endDragOverlay() {
    _dragEntry?.remove();
    _dragEntry?.dispose();
    _dragEntry = null;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    widget.image.loadIn();

    if (widget.image.newImage) {
      // if the image is new, make it [active]
      active = true;
      widget.image.newImage = false;
    }

    CanvasImage.activeListener.addListener(disableActive);

    super.initState();
  }

  void disableActive() {
    active = false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    useListenable(widget.image);
    if (widget.readOnly) active = false;

    final currentBrightness = widget.image.invertible
        ? Theme.brightnessOf(context)
        : Brightness.light;

    if (stows.editorAutoInvert.value && currentBrightness != imageBrightness) {
      imageBrightness = currentBrightness;
    }

    final Widget unpositioned = IgnorePointer(
      ignoring: widget.readOnly,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MouseRegion(
            cursor: active ? SystemMouseCursors.grab : MouseCursor.defer,
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: _gestures(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: active ? colorScheme.onSurface : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Center(child: _buildContent(context)),
              ),
            ),
          ),
          if (widget.selected) // tint image if selected
            ColoredBox(color: colorScheme.primary.withValues(alpha: 0.5)),
          if (!widget.readOnly)
            for (double x = -20; x <= 20; x += 20)
              for (double y = -20; y <= 20; y += 20)
                if (x != 0 || y != 0) // ignore (0,0)
                  _CanvasImageResizeHandle(
                    active: active,
                    position: Offset(x, y),
                    image: widget.image,
                    parent: this,
                    afterDrag: () => setState(() {}),
                  ),
          if (!widget.readOnly && !widget.isBackground)
            _CanvasImageRotateHandle(
              active: active,
              image: widget.image,
              parent: this,
            ),
        ],
      ),
    );

    if (widget.isBackground) {
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastLinearToSlowEaseIn,
        left: 0,
        top: 0,
        right: 0,
        bottom: 0,
        child: unpositioned,
      );
    }
    return AnimatedPositioned(
      // no animation if the image is being dragged or it's selected
      duration: (panStartRect != .zero || widget.selected)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.fastLinearToSlowEaseIn,

      left: widget.image.dstRect.left,
      top: widget.image.dstRect.top,
      width: max(widget.image.dstRect.width, CanvasImage.minInteractiveSize),
      height: max(widget.image.dstRect.height, CanvasImage.minInteractiveSize),

      child: widget.image.angle == 0
          ? unpositioned
          : Transform.rotate(angle: widget.image.angle, child: unpositioned),
    );
  }

  Map<Type, GestureRecognizerFactory> _gestures() {
    // Ohne Lasso-Werkzeug ignoriert das Foto den Stift: Der Stift schreibt
    // dann einfach darüber. Der Finger bedient das Foto immer.
    final devices = widget.acceptStylus
        ? null
        : <PointerDeviceKind>{
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          };
    return {
      TapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (instance) {
              instance
                ..supportedDevices = devices
                ..onTap = () {
                  active = !active;
                }
                ..onSecondaryTap = active ? showModal : null;
            },
          ),
      if (active)
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              LongPressGestureRecognizer.new,
              (instance) {
                instance
                  ..supportedDevices = devices
                  ..onLongPress = showModal;
              },
            ),
      if (active)
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              PanGestureRecognizer.new,
              (instance) {
                instance
                  ..supportedDevices = devices
                  ..onStart = _onPanStart
                  ..onUpdate = _onPanUpdate
                  ..onEnd = _onPanEnd
                  ..onCancel = _endDragOverlay;
              },
            ),
    };
  }

  void _onPanStart(DragStartDetails details) {
    panStartRect = widget.image.dstRect;
    _startDragOverlay(details);
    if (_dragEntry != null) setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Bei gedrehtem Foto liegt die Geste im gedrehten Koordinatensystem.
    final a = widget.image.angle;
    final delta = Offset(
      details.delta.dx * cos(a) - details.delta.dy * sin(a),
      details.delta.dx * sin(a) + details.delta.dy * cos(a),
    );
    setState(() {
      final fivePercent = min(
        widget.pageSize.width * 0.05,
        widget.pageSize.height * 0.05,
      );
      final r = widget.image.dstRect;
      // Auch über den Seitenrand hinaus ziehbar: beim Loslassen wechselt
      // das Foto auf die Nachbarseite.
      widget.image.dstRect = .fromLTWH(
        (r.left + delta.dx)
            .clamp(fivePercent - r.width, widget.pageSize.width - fivePercent)
            .toDouble(),
        (r.top + delta.dy)
            .clamp(-r.height - widget.pageSize.height, widget.pageSize.height * 2)
            .toDouble(),
        r.width,
        r.height,
      );
    });
    _updateDragOverlay(details);
  }

  void _onPanEnd(DragEndDetails details) {
    _endDragOverlay();
    if (panStartRect == widget.image.dstRect) return;
    if (EditorImage.dropHandler?.call(widget.image, panStartRect) ?? false) {
      panStartRect = .zero;
      return;
    }
    widget.image.onMoveImage?.call(
      widget.image,
      .fromLTRB(
        widget.image.dstRect.left - panStartRect.left,
        widget.image.dstRect.top - panStartRect.top,
        widget.image.dstRect.right - panStartRect.right,
        widget.image.dstRect.bottom - panStartRect.bottom,
      ),
    );
    panStartRect = .zero;
  }

  /// Foto samt Zuschnitt (Rahmen) und Lasso-Schnittebenen.
  Widget _buildContent(BuildContext context) {
    final image = widget.image;
    final frameW = widget.isBackground
        ? widget.pageSize.width
        : max(image.dstRect.width, CanvasImage.minImageSize);
    final frameH = widget.isBackground
        ? widget.pageSize.height
        : max(image.dstRect.height, CanvasImage.minImageSize);

    Widget inner(double w, double h) => SizedBox(
      width: w,
      height: h,
      child: SizedOverflowBox(
        size: image.srcRect.size,
        child: Transform.translate(
          offset: -image.srcRect.topLeft,
          child: image.buildImageWidget(
            context: context,
            overrideBoxFit: widget.overrideBoxFit,
            isBackground: widget.isBackground,
            invert: imageBrightness == .dark,
          ),
        ),
      ),
    );

    final crop = image.crop;
    final fullW = frameW / crop.width;
    final fullH = frameH / crop.height;
    Widget full = inner(fullW, fullH);
    if (image.clip.isNotEmpty) {
      full = ClipPath(
        clipper: ImageClipper(image.clip, image.clipCache),
        child: full,
      );
    }
    final Widget content;
    if (!image.isCropped) {
      content = full;
    } else {
      content = SizedBox(
        width: frameW,
        height: frameH,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: fullW,
            maxWidth: fullW,
            minHeight: fullH,
            maxHeight: fullH,
            child: Transform.translate(
              offset: Offset(-crop.left * fullW, -crop.top * fullH),
              child: full,
            ),
          ),
        ),
      );
    }
    _dragContent = image.angle == 0
        ? content
        : Transform.rotate(angle: image.angle, child: content);
    // Während des Ziehens zeigt die Überlagerung das Foto, nicht die Seite.
    return Opacity(opacity: _dragEntry != null ? 0 : 1, child: content);
  }

  @override
  void dispose() {
    _dragEntry?.remove();
    _dragEntry?.dispose();
    _dragEntry = null;
    widget.image.loadOut();
    CanvasImage.activeListener.removeListener(disableActive);
    super.dispose();
  }

  void showModal() {
    showDialog(
      context: context,
      builder: (context) {
        return AdaptiveAlertDialog(
          title: Text(t.editor.imageOptions.title),
          content: CanvasImageDialog(
            filePath: widget.filePath,
            image: widget.image,
            redrawImage: () => setState(() {}),
            isBackground: false,
            toggleAsBackground: () {
              widget.setAsBackground?.call(widget.image);
            },
            chooseTarget: () => EditorImage.targetHandler?.call(widget.image),
          ),
          actions: const [],
        );
      },
    );
  }
}

class _CanvasImageResizeHandle extends StatelessWidget {
  const new({
    required this.active,
    required this.position,
    required this.image,
    required this.parent,
    required this.afterDrag,
  });

  final bool active;
  final Offset position;
  final EditorImage image;
  final _CanvasImageState parent;
  final void Function() afterDrag;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Positioned(
      left: (position.dx.sign + 1) / 2 * image.dstRect.width - 20,
      top: (position.dy.sign + 1) / 2 * image.dstRect.height - 20,
      child: DeferPointer(
        paintOnTop: true,
        child: MouseRegion(
          cursor: () {
            if (!active) return MouseCursor.defer;

            if (position.dx == 0 && position.dy < 0)
              return SystemMouseCursors.resizeUp;
            if (position.dx == 0 && position.dy > 0)
              return SystemMouseCursors.resizeDown;
            if (position.dx < 0 && position.dy == 0)
              return SystemMouseCursors.resizeLeft;
            if (position.dx > 0 && position.dy == 0)
              return SystemMouseCursors.resizeRight;

            if (position.dx < 0 && position.dy < 0)
              return SystemMouseCursors.resizeUpLeft;
            if (position.dx < 0 && position.dy > 0)
              return SystemMouseCursors.resizeDownLeft;
            if (position.dx > 0 && position.dy < 0)
              return SystemMouseCursors.resizeUpRight;
            if (position.dx > 0 && position.dy > 0)
              return SystemMouseCursors.resizeDownRight;

            return MouseCursor.defer;
          }(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: active
                ? (details) {
                    parent.panStartRect = parent.widget.image.dstRect;
                    parent.panStartPosition = details.localPosition;
                  }
                : null,
            onPanUpdate: active
                ? (details) {
                    final Offset delta =
                        details.localPosition - parent.panStartPosition;

                    double newWidth;
                    if (position.dx < 0) {
                      newWidth = parent.panStartRect.width - delta.dx;
                    } else if (position.dx > 0) {
                      newWidth = parent.panStartRect.width + delta.dx;
                    } else {
                      newWidth = parent.panStartRect.width;
                    }

                    double newHeight;
                    if (position.dy < 0) {
                      newHeight = parent.panStartRect.height - delta.dy;
                    } else if (position.dy > 0) {
                      newHeight = parent.panStartRect.height + delta.dy;
                    } else {
                      newHeight = parent.panStartRect.height;
                    }

                    if (newWidth <= 0 || newHeight <= 0) return;

                    // preserve aspect ratio if diagonal
                    if (position.dx != 0 && position.dy != 0) {
                      // if diagonal
                      final aspectRatio =
                          image.dstRect.width / image.dstRect.height;
                      if (newWidth / newHeight > aspectRatio) {
                        newHeight = newWidth / aspectRatio;
                      } else {
                        newWidth = newHeight * aspectRatio;
                      }
                    }

                    // resize from the correct corner
                    double left = image.dstRect.left, top = image.dstRect.top;
                    if (position.dx < 0) {
                      left = image.dstRect.right - newWidth;
                    }
                    if (position.dy < 0) {
                      top = image.dstRect.bottom - newHeight;
                    }

                    image.dstRect = .fromLTWH(left, top, newWidth, newHeight);
                    afterDrag();
                  }
                : null,
            onPanEnd: active
                ? (details) {
                    if (parent.panStartRect == image.dstRect) return;
                    image.onMoveImage?.call(
                      image,
                      .fromLTRB(
                        image.dstRect.left - parent.panStartRect.left,
                        image.dstRect.top - parent.panStartRect.top,
                        image.dstRect.right - parent.panStartRect.right,
                        image.dstRect.bottom - parent.panStartRect.bottom,
                      ),
                    );
                    parent.panStartRect = .zero;
                  }
                : null,
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 100),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface,
                  shape: .circle,
                  border: Border.all(color: colorScheme.surface, width: 2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Drehknopf oberhalb des aktiven Fotos.
class _CanvasImageRotateHandle extends StatelessWidget {
  const new({
    required this.active,
    required this.image,
    required this.parent,
  });

  final bool active;
  final EditorImage image;
  final _CanvasImageState parent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Positioned(
      left: image.dstRect.width / 2 - 20,
      top: -64,
      child: DeferPointer(
        paintOnTop: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: active
              ? (details) {
                  final box = parent.context.findRenderObject() as RenderBox?;
                  if (box == null) return;
                  final center = box.localToGlobal(box.size.center(Offset.zero));
                  var a = (details.globalPosition - center).direction + pi / 2;
                  // leichtes Einrasten bei Vielfachen von 15 Grad
                  final deg = a * 180 / pi;
                  final snapped = (deg / 15).roundToDouble() * 15;
                  if ((deg - snapped).abs() < 3) a = snapped * pi / 180;
                  image.angle = a;
                  image.notifyListeners();
                }
              : null,
          onPanEnd: active ? (details) => image.onMiscChange?.call() : null,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: const Duration(milliseconds: 100),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.onSurface,
                shape: .circle,
                border: Border.all(color: colorScheme.surface, width: 2),
              ),
              child: Icon(Icons.rotate_right, color: colorScheme.surface, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}
