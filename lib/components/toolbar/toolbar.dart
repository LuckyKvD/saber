import 'dart:math' as math;
import 'dart:io';

import 'package:collapsible/collapsible.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:keybinder/keybinder.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/theming/uni_icon.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/components/toolbar/eraser_modal.dart';
import 'package:saber/components/toolbar/export_bar.dart';
import 'package:saber/components/toolbar/pen_modal.dart';
import 'package:saber/components/toolbar/selection_bar.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/components/toolbar/toolbar_button.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/data/tools/tape_pen.dart';
import 'package:saber/i18n/strings.g.dart';

class Toolbar extends StatefulWidget {
  const new({
    super.key,
    required this.readOnly,
    required this.setTool,
    required this.currentTool,
    required this.setColor,
    required this.quillFocus,
    required this.textEditing,
    required this.toggleTextEditing,
    required this.undo,
    required this.isUndoPossible,
    required this.redo,
    required this.isRedoPossible,
    required this.toggleFingerDrawing,
    required this.pickPhoto,
    required this.toggleWritingPad,
    required this.toggleRuler,
    required this.rulerVisible,
    required this.toggleProtractor,
    required this.protractorMode,
    required this.writingPadVisible,
    required this.paste,
    required this.duplicateSelection,
    required this.deleteSelection,
    required this.exportAsSba,
    required this.exportAsPdf,
    required this.exportAsPng,
  });

  final bool readOnly;

  /// Schreibfeld (Easy-Writing) ein-/ausblenden.
  final VoidCallback toggleWritingPad;
  final bool writingPadVisible;

  /// Virtuelles Lineal ein-/ausblenden.
  final VoidCallback toggleRuler;
  final bool rulerVisible;

  /// Winkelmesser: tippen schaltet Aus, Halbkreis, Vollkreis durch.
  final VoidCallback toggleProtractor;
  final int protractorMode;

  final ValueChanged<Tool> setTool;
  final Tool currentTool;
  final ValueChanged<Color> setColor;

  final ValueNotifier<QuillStruct?> quillFocus;
  final bool textEditing;
  final VoidCallback toggleTextEditing;

  final VoidCallback undo;
  final bool isUndoPossible;
  final VoidCallback redo;
  final bool isRedoPossible;

  final VoidCallback toggleFingerDrawing;

  final VoidCallback pickPhoto;

  final VoidCallback paste;

  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;

  final Future Function(BuildContext)? exportAsSba;
  final Future Function(BuildContext)? exportAsPdf;
  final Future Function(BuildContext)? exportAsPng;

  @override
  State<Toolbar> createState() => _ToolbarState();

  static const _buttonPaddingHorizontal = EdgeInsets.symmetric(horizontal: 6);
  static const _buttonPaddingVertical = EdgeInsets.symmetric(vertical: 6);
}

class _ToolbarState extends State<Toolbar> {
  ValueNotifier<bool> showExportOptions = ValueNotifier(false);
  ValueNotifier<bool> showColorOptions = ValueNotifier(true);
  ValueNotifier<ToolOptions> toolOptionsType = ValueNotifier(ToolOptions.hide);

  /// Zuletzt benutzter normaler Stift (Füller, Kugelschreiber, Kalligrafie),
  /// damit der Formen-Stift den Stift-Knopf nicht überschreibt.
  Pen? _lastRegularPen;
  Pen get _regularPen {
    if (Pen.currentPen is! ShapePen) _lastRegularPen = Pen.currentPen;
    return _lastRegularPen ??= Pen.fountainPen();
  }

  @override
  void initState() {
    _assignKeybindings();

    DynamicMaterialApp.addFullscreenListener(_setState);

    super.initState();
  }

  void _setState() => setState(() {});

  Keybinding? _ctrlF;
  Keybinding? _ctrlE;
  Keybinding? _ctrlC;
  Keybinding? _ctrlShiftS;
  Keybinding? _f11;
  Keybinding? _ctrlV;
  void _assignKeybindings() {
    _ctrlF = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyF),
    ], inclusive: true);
    _ctrlE = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyE),
    ], inclusive: true);
    _ctrlC = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyC),
    ], inclusive: true);
    _ctrlShiftS = Keybinding([
      KeyCode.ctrl,
      KeyCode.shift,
      KeyCode.from(LogicalKeyboardKey.keyS),
    ], inclusive: true);
    _f11 = Keybinding([KeyCode.from(LogicalKeyboardKey.f11)], inclusive: true);
    _ctrlV = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyV),
    ], inclusive: true);

    Keybinder.bind(_ctrlF!, widget.toggleFingerDrawing);
    Keybinder.bind(_ctrlE!, toggleEraser);
    Keybinder.bind(_ctrlC!, toggleColorOptions);
    Keybinder.bind(_ctrlShiftS!, toggleExportBar);
    Keybinder.bind(_f11!, toggleFullscreen);
    Keybinder.bind(_ctrlV!, widget.paste);
  }

  void _removeKeybindings() {
    if (_ctrlF != null) Keybinder.remove(_ctrlF!);
    if (_ctrlE != null) Keybinder.remove(_ctrlE!);
    if (_ctrlC != null) Keybinder.remove(_ctrlC!);
    if (_ctrlShiftS != null) Keybinder.remove(_ctrlShiftS!);
    if (_f11 != null) Keybinder.remove(_f11!);
    if (_ctrlV != null) Keybinder.remove(_ctrlV!);
  }

  void toggleEraser() {
    final wasEraser = widget.currentTool is Eraser;
    toolOptionsType.value = wasEraser ? .hide : .eraser;
    widget.setTool(Eraser()); // this toggles eraser
  }

  void toggleColorOptions() {
    showColorOptions.value = !showColorOptions.value;
  }

  void toggleExportBar() {
    showExportOptions.value = !showExportOptions.value;
  }

  void toggleFullscreen() async {
    DynamicMaterialApp.setFullscreen(
      !DynamicMaterialApp.isFullscreen,
      updateSystem: true,
    );
  }

  /// Aufklappmenü-Knopf: fasst selten genutzte Werkzeuge zusammen.
  Widget _menuButton(
    BuildContext context,
    EdgeInsets padding, {
    required String tooltip,
    required Widget icon,
    required bool selected,
    required List<_MenuEntry> entries,
  }) {
    return Builder(
      builder: (buttonContext) => ToolbarIconButton(
        tooltip: tooltip,
        selected: selected,
        onPressed: () async {
          final box = buttonContext.findRenderObject() as RenderBox;
          final overlay =
              Overlay.of(buttonContext).context.findRenderObject() as RenderBox;
          final position = RelativeRect.fromRect(
            box.localToGlobal(Offset.zero, ancestor: overlay) & box.size,
            Offset.zero & overlay.size,
          );
          final picked = await showMenu<VoidCallback>(
            context: buttonContext,
            position: position,
            items: [
              for (final entry in entries)
                PopupMenuItem<VoidCallback>(
                  value: entry.onTap,
                  enabled: entry.enabled,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        entry.icon,
                        color: entry.selected
                            ? ColorScheme.of(buttonContext).primary
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Text(entry.label),
                      if (entry.selected) ...[
                        const SizedBox(width: 12),
                        Icon(
                          Icons.check,
                          size: 18,
                          color: ColorScheme.of(buttonContext).primary,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
          picked?.call();
        },
        padding: padding,
        child: icon,
      ),
    );
  }

  /// Hilfsmittel: Formstift, Schreibfeld, Lineal, Winkelmesser, Laserpointer.
  Widget _helpersMenu(BuildContext context, EdgeInsets padding) {
    final readOnly = widget.readOnly;
    final shapeSelected = widget.currentTool is ShapePen;
    final laserSelected =
        widget.currentTool == LaserPointer.currentLaserPointer;
    return _menuButton(
      context,
      padding,
      tooltip: 'Hilfsmittel',
      icon: const Icon(Icons.straighten),
      selected:
          shapeSelected ||
          laserSelected ||
          widget.writingPadVisible ||
          widget.rulerVisible ||
          widget.protractorMode != 0,
      entries: [
        _MenuEntry(
          icon: Icons.edit_note,
          label: 'Schreibfeld',
          selected: widget.writingPadVisible,
          enabled: !readOnly,
          onTap: widget.toggleWritingPad,
        ),
        _MenuEntry(
          icon: Icons.straighten,
          label: 'Lineal',
          selected: widget.rulerVisible,
          enabled: !readOnly,
          onTap: widget.toggleRuler,
        ),
        _MenuEntry(
          icon: Icons.square_foot,
          label: widget.protractorMode == 0
              ? 'Winkelmesser (Halbkreis)'
              : widget.protractorMode == 1
              ? 'Winkelmesser (Vollkreis)'
              : 'Winkelmesser ausblenden',
          selected: widget.protractorMode != 0,
          enabled: !readOnly,
          onTap: widget.toggleProtractor,
        ),
        _MenuEntry(
          icon: Icons.category_outlined,
          label: t.editor.pens.shapePen,
          selected: shapeSelected,
          enabled: !readOnly,
          onTap: () {
            if (shapeSelected) {
              toolOptionsType.value = toolOptionsType.value == .pen
                  ? .hide
                  : .pen;
            } else {
              toolOptionsType.value = .pen;
              widget.setTool(ShapePen());
            }
          },
        ),
        _MenuEntry(
          icon: Symbols.stylus_laser_pointer,
          label: t.editor.pens.laserPointer,
          selected: laserSelected,
          enabled: true,
          onTap: () {
            toolOptionsType.value = .hide;
            widget.setTool(LaserPointer.currentLaserPointer);
          },
        ),
      ],
    );
  }

  /// Mehr: Fingerzeichnen, Vollbild, Teilen/Export.
  Widget _moreMenu(BuildContext context, EdgeInsets padding) {
    final readOnly = widget.readOnly;
    return _menuButton(
      context,
      padding,
      tooltip: 'Mehr',
      icon: const Icon(Icons.more_horiz),
      selected: showExportOptions.value || DynamicMaterialApp.isFullscreen,
      entries: [
        if (!stows.hideFingerDrawingToggle.value)
          _MenuEntry(
            icon: CupertinoIcons.hand_draw,
            label: t.editor.toolbar.toggleFingerDrawing,
            selected: stows.editorFingerDrawing.value,
            enabled: !readOnly,
            onTap: widget.toggleFingerDrawing,
          ),
        _MenuEntry(
          icon: DynamicMaterialApp.isFullscreen
              ? Icons.fullscreen_exit
              : Icons.fullscreen,
          label: t.editor.toolbar.fullscreen,
          selected: DynamicMaterialApp.isFullscreen,
          enabled: !readOnly,
          onTap: toggleFullscreen,
        ),
        _MenuEntry(
          icon: Icons.share,
          label: t.editor.toolbar.export,
          selected: showExportOptions.value,
          enabled: !readOnly,
          onTap: toggleExportBar,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    final brightness = Theme.brightnessOf(context);
    final invert = stows.editorAutoInvert.value && brightness == .dark;

    final isToolbarVertical =
        stows.editorToolbarAlignment.value == .left ||
        stows.editorToolbarAlignment.value == .right;

    final buttonPadding = isToolbarVertical
        ? Toolbar._buttonPaddingVertical
        : Toolbar._buttonPaddingHorizontal;

    final currentColor = switch (widget.currentTool) {
      final Pen pen => pen.color,
      final Select select => select.getDominantStrokeColor(),
      _ => null,
    };

    if (widget.currentTool == Select.currentSelect) {
      // Enable selection bar only when selection is done
      toolOptionsType.value = Select.currentSelect.doneSelecting
          ? .select
          : .hide;
    }

    final bars = <Widget>[
      ValueListenableBuilder(
        valueListenable: showExportOptions,
        builder: (context, showExportOptions, child) {
          return Collapsible(
            axis: isToolbarVertical ? .horizontal : .vertical,
            maintainState: true,
            collapsed: !showExportOptions,
            child: child!,
          );
        },
        child: ExportBar(
          axis: isToolbarVertical ? .vertical : .horizontal,
          toggleExportBar: toggleExportBar,
          exportAsSba: widget.exportAsSba,
          exportAsPdf: widget.exportAsPdf,
          exportAsPng: widget.exportAsPng,
        ),
      ),
      ValueListenableBuilder(
        valueListenable: toolOptionsType,
        builder: (context, toolOptionsType, _) {
          return Collapsible(
            axis: isToolbarVertical ? .horizontal : .vertical,
            maintainState: true,
            collapsed: toolOptionsType == .hide,
            child: switch (toolOptionsType) {
              .hide => const SizedBox.square(dimension: SizePicker.smallLength),
              .pen => PenModal<Pen>(
                getTool: () => widget.currentTool is Pencil
                    ? Pencil.currentPencil
                    : Pen.currentPen,
                setTool: widget.setTool,
              ),
              .highlighter => PenModal(
                getTool: () => Highlighter.currentHighlighter,
                setTool: widget.setTool,
              ),
              .tape => PenModal(
                getTool: () => TapePen.currentTape,
                setTool: widget.setTool,
              ),
              .pencil => PenModal(
                getTool: () => Pencil.currentPencil,
                setTool: widget.setTool,
              ),
              .eraser => const EraserModal(),
              .select => SelectionBar(
                duplicateSelection: widget.duplicateSelection,
                deleteSelection: widget.deleteSelection,
              ),
            },
          );
        },
      ),
      ValueListenableBuilder(
        valueListenable: showColorOptions,
        builder: (context, showColorOptions, child) {
          return Collapsible(
            axis: isToolbarVertical ? .horizontal : .vertical,
            maintainState: true,
            collapsed: !showColorOptions,
            child: child!,
          );
        },
        child: ColorBar(
          axis: isToolbarVertical ? .vertical : .horizontal,
          setColor: widget.setColor,
          currentColor: currentColor,
          invert: invert,
        ),
      ),
      ValueListenableBuilder(
        valueListenable: widget.quillFocus,
        builder: (context, quill, _) {
          final baseButtonStyle =
              IconButtonTheme.of(context).style ?? const ButtonStyle();

          final iconTheme = QuillIconTheme(
            iconButtonUnselectedData: IconButtonData(
              style: baseButtonStyle.copyWith(
                backgroundColor: WidgetStateProperty.all(Colors.transparent),
                foregroundColor: WidgetStateProperty.all(colorScheme.primary),
              ),
            ),
            iconButtonSelectedData: IconButtonData(
              style: baseButtonStyle.copyWith(
                backgroundColor: WidgetStateProperty.all(colorScheme.primary),
                foregroundColor: WidgetStateProperty.all(colorScheme.onPrimary),
              ),
            ),
          );
          return Collapsible(
            axis: isToolbarVertical ? .horizontal : .vertical,
            maintainState: false,
            collapsed: !widget.textEditing || quill == null,
            child: quill != null
                ? QuillSimpleToolbar(
                    controller: quill.controller,
                    config: QuillSimpleToolbarConfig(
                      axis: isToolbarVertical ? .vertical : .horizontal,
                      buttonOptions: QuillSimpleToolbarButtonOptions(
                        base: QuillToolbarBaseButtonOptions(
                          iconTheme: iconTheme,
                        ),
                      ),
                      // scrollable on Android and iOS
                      multiRowsDisplay: !Platform.isAndroid && !Platform.isIOS,
                      showUndo: false,
                      showRedo: false,
                      showFontSize: false,
                      showFontFamily: false,
                      showClearFormat: false,
                    ),
                  )
                : const SizedBox.shrink(),
          );
        },
      ),
      Center(
        child: Padding(
          padding: const .all(8),
          child: Wrap(
            direction: isToolbarVertical ? .vertical : .horizontal,
            alignment: WrapAlignment.center,
            runSpacing: 8,
            children: [
              ToolbarIconButton(
                tooltip: widget.currentTool is Pencil
                    ? t.editor.pens.pencil
                    : _regularPen.name,
                selected:
                    widget.currentTool is Pencil ||
                    (widget.currentTool == Pen.currentPen &&
                        Pen.currentPen is! ShapePen),
                enabled: !widget.readOnly,
                onPressed: () {
                  if (widget.currentTool is Pencil ||
                      (widget.currentTool == Pen.currentPen &&
                          Pen.currentPen is! ShapePen)) {
                    if (toolOptionsType.value == .pen) {
                      toolOptionsType.value = .hide;
                    } else {
                      toolOptionsType.value = .pen;
                    }
                  } else {
                    toolOptionsType.value = .pen;
                    widget.setTool(_regularPen);
                  }
                },
                padding: buttonPadding,
                child: widget.currentTool is Pencil
                    ? const FaIcon(Pencil.pencilIcon, size: 16)
                    : UniIcon(_regularPen.icon, size: 16),
              ),
              ToolbarIconButton(
                tooltip: t.editor.pens.highlighter,
                selected: widget.currentTool == Highlighter.currentHighlighter,
                enabled: !widget.readOnly,
                onPressed: () {
                  if (widget.currentTool == Highlighter.currentHighlighter) {
                    if (toolOptionsType.value == .highlighter) {
                      toolOptionsType.value = .hide;
                    } else {
                      toolOptionsType.value = .highlighter;
                    }
                  } else {
                    toolOptionsType.value = .highlighter;
                    widget.setTool(Highlighter.currentHighlighter);
                  }
                },
                padding: buttonPadding,
                child: const FaIcon(Highlighter.highlighterIcon, size: 16),
              ),
              ToolbarIconButton(
                tooltip: TapePen.currentTape.name,
                selected: widget.currentTool is TapePen,
                enabled: !widget.readOnly,
                onPressed: () {
                  if (widget.currentTool is TapePen) {
                    toolOptionsType.value = toolOptionsType.value == .tape
                        ? .hide
                        : .tape;
                  } else {
                    toolOptionsType.value = .tape;
                    widget.setTool(TapePen.currentTape);
                  }
                },
                padding: buttonPadding,
                child: const FaIcon(TapePen.tapeIcon, size: 16),
              ),
              ValueListenableBuilder(
                valueListenable: showColorOptions,
                builder: (context, showColorOptions, child) {
                  return ToolbarIconButton(
                    tooltip: t.editor.toolbar.toggleColors,
                    selected: showColorOptions,
                    enabled: !widget.readOnly,
                    onPressed: toggleColorOptions,
                    padding: buttonPadding,
                    child: child!,
                  );
                },
                child: currentColor == null
                    ? const Icon(Icons.palette)
                    : Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: currentColor
                              .withInversion(invert)
                              .withValues(alpha: 1),
                          shape: .circle,
                          border: Border.all(
                            color: colorScheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
              ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.select,
                selected: widget.currentTool is Select,
                enabled: !widget.readOnly,
                onPressed: () {
                  toolOptionsType.value = .hide;
                  widget.setTool(Select.currentSelect);
                },
                padding: buttonPadding,
                child: Icon(
                  CupertinoIcons.lasso,
                  shadows: !widget.readOnly
                      ? [
                          BoxShadow(
                            color: colorScheme.primary,
                            blurRadius: 0.1,
                            spreadRadius: 10,
                            blurStyle: BlurStyle.solid,
                          ),
                        ]
                      : null,
                ),
              ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.toggleEraser,
                selected: widget.currentTool is Eraser,
                enabled: !widget.readOnly,
                onPressed: toggleEraser,
                padding: buttonPadding,
                child: const FaIcon(FontAwesomeIcons.eraser, size: 16),
              ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.photo,
                enabled: !widget.readOnly,
                onPressed: widget.pickPhoto,
                padding: buttonPadding,
                child: const AdaptiveIcon(
                  icon: Icons.photo,
                  cupertinoIcon: CupertinoIcons.photo,
                ),
              ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.text,
                selected: widget.textEditing,
                enabled: !widget.readOnly,
                onPressed: widget.toggleTextEditing,
                padding: buttonPadding,
                child: const AdaptiveIcon(
                  icon: Icons.text_fields,
                  cupertinoIcon: CupertinoIcons.text_cursor,
                ),
              ),
              _helpersMenu(context, buttonPadding),
              Wrap(
                direction: isToolbarVertical ? .vertical : .horizontal,
                children: [
                  ToolbarIconButton(
                    tooltip: t.editor.toolbar.undo,
                    enabled: !widget.readOnly && widget.isUndoPossible,
                    onPressed: widget.undo,
                    padding: buttonPadding,
                    child: const AdaptiveIcon(
                      icon: Icons.undo,
                      cupertinoIcon: CupertinoIcons.arrow_uturn_left,
                    ),
                  ),
                  ToolbarIconButton(
                    tooltip: t.editor.toolbar.redo,
                    enabled: !widget.readOnly && widget.isRedoPossible,
                    onPressed: widget.redo,
                    padding: buttonPadding,
                    child: const AdaptiveIcon(
                      icon: Icons.redo,
                      cupertinoIcon: CupertinoIcons.arrow_uturn_right,
                    ),
                  ),
                ],
              ),
              _moreMenu(context, buttonPadding),
            ],
          ),
        ),
      ),
    ];

    return Flex(
      direction: isToolbarVertical ? .horizontal : .vertical,
      textDirection: switch (stows.editorToolbarAlignment.value) {
        .left => .rtl,
        .right => .ltr,
        _ => null,
      },
      verticalDirection: switch (stows.editorToolbarAlignment.value) {
        .down => .down,
        .up => .up,
        _ => .down,
      },
      children: bars,
    );
  }

  @override
  void dispose() {
    DynamicMaterialApp.removeFullscreenListener(_setState);
    DynamicMaterialApp.setFullscreen(false, updateSystem: true);

    _removeKeybindings();
    super.dispose();
  }
}

class _MenuEntry {
  const _MenuEntry({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
}

enum ToolOptions { hide, pen, highlighter, tape, pencil, eraser, select }

/// Kleines Winkelmesser-Symbol (Halbkreis oder Vollkreis mit Skalenstrichen).
class _ProtractorIconPainter extends CustomPainter {
  _ProtractorIconPainter(this.color, {required this.full});

  final Color color;
  final bool full;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final c = full
        ? Offset(size.width / 2, size.height / 2)
        : Offset(size.width / 2, size.height * 0.75);
    final r = size.width * 0.45;
    if (full) {
      canvas.drawCircle(c, r, paint);
    } else {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), 3.14159265, 3.14159265, false, paint);
      canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), paint);
    }
    for (var d = 0; d <= (full ? 330 : 180); d += 30) {
      final a = d * 3.14159265 / 180;
      final dir = Offset(math.cos(a), -math.sin(a));
      canvas.drawLine(c + dir * (r - 4), c + dir * r, paint);
    }
  }

  @override
  bool shouldRepaint(_ProtractorIconPainter old) =>
      old.color != color || old.full != full;
}
