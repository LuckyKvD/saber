import 'dart:math';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/editor/page.dart';
import 'package:sbn/quill_styles.dart';

/// Rückmeldungen eines Textfelds an den Editor (Rückgängig, Speichern).
class TextBoxActions {
  const TextBoxActions({
    required this.onRectChanged,
    required this.onDelete,
    required this.onBackgroundChanged,
    required this.onOpenLink,
    required this.neighborPage,
    required this.onTransfer,
  });

  /// Nachbarseite links/rechts (Doppelblatt, zwei Seiten nebeneinander).
  final int? Function(int pageIndex, bool toRight) neighborPage;

  /// Textfeld wurde über den Seitenrand auf die Nachbarseite gezogen.
  final void Function(
    FreeTextBox box,
    int fromPage,
    int toPage,
    Rect before,
    Rect overflow,
  )
  onTransfer;

  final void Function(FreeTextBox box, Rect before, Rect after) onRectChanged;
  final void Function(FreeTextBox box) onDelete;
  final void Function(FreeTextBox box, bool before, bool after)
  onBackgroundChanged;
  final void Function(FreeTextBox box) onOpenLink;
}

/// Feder: Ein frei platzierbares Textfeld auf einer Seite.
class TextBoxWidget extends StatefulWidget {
  const TextBoxWidget({
    super.key,
    required this.box,
    required this.pageIndex,
    required this.pageSize,
    required this.lineHeight,
    required this.invert,
    required this.secondary,
    required this.textEditing,
    required this.readOnly,
    required this.actions,
  });

  final FreeTextBox box;
  final int pageIndex;
  final Size pageSize;
  final int lineHeight;
  final bool invert;
  final Color secondary;
  final bool textEditing;
  final bool readOnly;
  final TextBoxActions? actions;

  @override
  State<TextBoxWidget> createState() => _TextBoxWidgetState();
}

class _TextBoxWidgetState extends State<TextBoxWidget> {
  static const double _minWidth = 140;
  static const double _minHeight = 70;
  static const double _handle = 48;

  late final ScrollController _scroll = ScrollController();
  Rect? _before;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _start() => _before = widget.box.rect;

  void _end() {
    final before = _before;
    _before = null;
    if (before == null || before == widget.box.rect) return;
    final actions = widget.actions;
    final r = widget.box.rect;
    final pw = widget.pageSize.width;
    if (actions != null) {
      final toRight = r.center.dx > pw;
      final toLeft = r.center.dx < 0;
      if (toRight || toLeft) {
        final to = actions.neighborPage(widget.pageIndex, toRight);
        if (to != null) {
          actions.onTransfer(widget.box, widget.pageIndex, to, before, r);
          return;
        }
      }
    }
    // Nicht hinübergezogen: zurück in die eigene Seite.
    final inside = Rect.fromLTWH(
      r.left.clamp(0.0, max(0.0, pw - r.width)).toDouble(),
      r.top,
      r.width,
      r.height,
    );
    if (inside != r) setState(() => widget.box.rect = inside);
    if (before == widget.box.rect) return;
    actions?.onRectChanged(widget.box, before, widget.box.rect);
  }

  void _move(Offset delta) {
    final r = widget.box.rect.shift(delta);
    // Mit Nachbarseite darf das Feld über den Rand hinaus gezogen werden.
    final canLeft = widget.actions?.neighborPage(widget.pageIndex, false) != null;
    final canRight = widget.actions?.neighborPage(widget.pageIndex, true) != null;
    final minLeft = canLeft ? -(r.width - 40) : 0.0;
    final maxRight = widget.pageSize.width + (canRight ? r.width - 40 : 0.0);
    final dx = r.left < minLeft
        ? minLeft - r.left
        : (r.right > maxRight ? maxRight - r.right : 0.0);
    final dy = r.top < 0
        ? -r.top
        : (r.bottom > widget.pageSize.height
              ? widget.pageSize.height - r.bottom
              : 0.0);
    setState(() => widget.box.rect = r.shift(Offset(dx, dy)));
  }

  void _resize(Offset delta) {
    final r = widget.box.rect;
    final w = (r.width + delta.dx).clamp(
      _minWidth,
      max(_minWidth, widget.pageSize.width - r.left),
    );
    final h = (r.height + delta.dy).clamp(
      _minHeight,
      max(_minHeight, widget.pageSize.height - r.top),
    );
    setState(
      () => widget.box.rect = Rect.fromLTWH(r.left, r.top, w.toDouble(), h.toDouble()),
    );
  }

  Widget _handleButton({
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    GestureDragStartCallback? onPanStart,
    GestureDragUpdateCallback? onPanUpdate,
    GestureDragEndCallback? onPanEnd,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      child: SizedBox.square(
        dimension: _handle,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 21, color: Colors.white),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final box = widget.box;
    final editing = widget.textEditing && !widget.readOnly;
    final lh = widget.lineHeight.toDouble();

    final editor = QuillEditor(
      controller: box.quill.controller,
      config: QuillEditorConfig(
        customStyles: SaberQuillStyles.get(
          invert: widget.invert && !box.whiteBackground,
          secondary: widget.secondary,
          lineHeight: widget.lineHeight,
        ),
        scrollable: true,
        autoFocus: false,
        expands: true,
        placeholder: editing ? 'Text …' : null,
        showCursor: true,
        keyboardAppearance: widget.invert && !box.whiteBackground ? .dark : .light,
        padding: EdgeInsets.only(
          top: lh * 0.4,
          left: lh * 0.4,
          right: lh * 0.4,
          bottom: lh * 0.4,
        ),
        showCodeBlockLineNumbers: false,
      ),
      scrollController: _scroll,
      focusNode: box.quill.focusNode,
    );

    const m = _handle / 2;
    return Positioned(
      left: box.rect.left - m,
      top: box.rect.top - m,
      width: box.rect.width + _handle,
      height: box.rect.height + _handle,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: m,
            top: m,
            right: m,
            bottom: m,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: box.whiteBackground
                    ? Colors.white
                    : (box.linkPath != null
                          ? colorScheme.primary.withValues(alpha: 0.10)
                          : null),
                border: editing
                    ? Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.7),
                        width: 1.5,
                      )
                    : null,
              ),
              child: box.linkPath != null && !editing
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.actions?.onOpenLink(box),
                      child: IgnorePointer(child: editor),
                    )
                  : IgnorePointer(ignoring: !editing, child: editor),
            ),
          ),
          if (editing) ...[
            Positioned(
              left: 0,
              top: 0,
              child: _handleButton(
                icon: Icons.open_with,
                color: colorScheme.primary,
                onPanStart: (_) => _start(),
                onPanUpdate: (d) => _move(d.delta),
                onPanEnd: (_) => _end(),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: _handleButton(
                icon: Icons.close,
                color: colorScheme.error,
                onTap: () => widget.actions?.onDelete(box),
              ),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              child: _handleButton(
                icon: box.whiteBackground
                    ? Icons.format_color_reset
                    : Icons.format_color_fill,
                color: colorScheme.secondary,
                onTap: () {
                  final before = box.whiteBackground;
                  setState(() => box.whiteBackground = !before);
                  widget.actions?.onBackgroundChanged(box, before, !before);
                },
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: _handleButton(
                icon: Icons.open_in_full,
                color: colorScheme.primary,
                onPanStart: (_) => _start(),
                onPanUpdate: (d) => _resize(d.delta),
                onPanEnd: (_) => _end(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
