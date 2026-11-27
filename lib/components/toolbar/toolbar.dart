import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:collapsible/collapsible.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:keybinder/keybinder.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/tasks/nextcloud_dav.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/theming/uni_icon.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/components/toolbar/eraser_modal.dart';
import 'package:saber/components/toolbar/export_bar.dart';
import 'package:saber/components/toolbar/pen_modal.dart';
import 'package:saber/components/toolbar/selection_bar.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/components/toolbar/text_stamp.dart';
import 'package:saber/components/toolbar/toolbar_button.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/calligraphy_pen.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/extra_pens.dart';
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
    required this.saveAsTemplate,
    required this.deleteSelection,
    required this.sendToNextcloud,
    required this.solveMath,
    required this.insertTable,
    required this.insertTemplate,
    required this.extendTable,
    required this.adjustSelection,
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
  final VoidCallback saveAsTemplate;
  final VoidCallback deleteSelection;

  /// Auswahl als Aufgabe an Nextcloud senden.
  final void Function(NcKind kind) sendToNextcloud;
  final VoidCallback solveMath;

  /// Feder: Tabelle einfügen bzw. ausgewählte Tabelle um Zeilen/Spalten erweitern.
  final VoidCallback insertTable;

  /// Feder: Vorlage (Besprechung, Jour fixe) in die geöffnete Seite einfügen.
  final VoidCallback insertTemplate;
  final void Function(int rows, int cols) extendTable;

  /// Feder: Strichdicke ([thickness]) oder Größe ([scale]) der Auswahl ändern.
  final void Function({double thickness, double scale}) adjustSelection;

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
    bool compact = false,
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
                      UniIcon(
                        entry.icon,
                        color:
                            entry.tint ??
                            (entry.selected
                                ? ColorScheme.of(buttonContext).primary
                                : null),
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
        compact: compact,
        child: icon,
      ),
    );
  }

  /// Breite (bzw. Höhe) eines Knopfes samt Abstand in der Werkzeugleiste.
  static const double _slot = 32;

  /// Tatsächlich gemessene Breite eines Knopfes (Geräte unterscheiden sich).
  double _slotMeasured = _slot;
  final _slotKey = GlobalKey();

  void _measureSlot(bool vertical) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _slotKey.currentContext?.findRenderObject();
      if (!mounted || box is! RenderBox || !box.hasSize) return;
      final w = vertical ? box.size.height : box.size.width;
      if (w > 10 && (w - _slotMeasured).abs() > 0.5) {
        setState(() => _slotMeasured = w);
      }
    });
  }

  Color _tint(Color color, bool invert) =>
      color.withInversion(invert).withValues(alpha: 1);

  bool _isPen(Object icon) {
    final tool = widget.currentTool;
    return tool is Pen &&
        tool is! Highlighter &&
        tool is! TapePen &&
        tool.icon == icon;
  }

  void _onPenTap(bool selected, Pen Function() make) {
    if (selected) {
      toolOptionsType.value = toolOptionsType.value == .pen ? .hide : .pen;
    } else {
      widget.setTool(make());
      // Ist schon eine Einstellungsleiste offen, zeigt sie jetzt diesen Stift.
      if (toolOptionsType.value != .hide) toolOptionsType.value = .pen;
    }
  }

  /// Stift-Knopf mit Symbol in der zuletzt benutzten Farbe dieses Stifts.
  _ToolItem _penItem(Pen Function() make, bool invert) {
    final pen = make();
    final icon = pen.icon;
    final selected = _isPen(icon);
    var color = pen.color;
    if (selected) {
      color = (widget.currentTool as Pen).color;
    } else {
      try {
        final saved = (jsonDecode(stows.penColors.value) as Map)[pen.name];
        if (saved is int) color = Color(saved);
      } catch (_) {}
    }
    return _ToolItem(
      tooltip: pen.name,
      icon: icon,
      tint: _tint(color, invert),
      selected: selected,
      enabled: !widget.readOnly,
      onTap: () => _onPenTap(selected, make),
    );
  }

  /// Alle Werkzeuge in der Reihenfolge ihrer Wichtigkeit. Was nicht in die
  /// Reihe passt, landet automatisch im Aufklappmenü.
  List<_ToolItem> _toolItems(BuildContext context, bool invert) {
    final readOnly = widget.readOnly;
    final highlighterSelected =
        widget.currentTool == Highlighter.currentHighlighter;
    final shapeSelected = widget.currentTool is ShapePen;
    final laserSelected =
        widget.currentTool == LaserPointer.currentLaserPointer;
    return [
      _penItem(Pen.ballpointPen, invert),
      _penItem(() => Pencil.currentPencil, invert),
      _penItem(Pen.fountainPen, invert),
      _penItem(() => CalligraphyPen.current, invert),
      _penItem(() => GlitterPen.current, invert),
      _penItem(() => DashedPen.current, invert),
      _ToolItem(
        tooltip: t.editor.pens.highlighter,
        icon: Highlighter.highlighterIcon,
        tint: _tint(Highlighter.currentHighlighter.color, invert),
        selected: highlighterSelected,
        enabled: !readOnly,
        onTap: () {
          if (highlighterSelected) {
            toolOptionsType.value = toolOptionsType.value == .highlighter
                ? .hide
                : .highlighter;
          } else {
            toolOptionsType.value = .highlighter;
            widget.setTool(Highlighter.currentHighlighter);
          }
        },
      ),
      _ToolItem(
        tooltip: TapePen.currentTape.name,
        icon: TapePen.tapeIcon,
        tint: _tint(TapePen.currentTape.color, invert),
        selected: widget.currentTool is TapePen,
        enabled: !readOnly,
        onTap: () {
          if (widget.currentTool is TapePen) {
            toolOptionsType.value = toolOptionsType.value == .tape
                ? .hide
                : .tape;
          } else {
            toolOptionsType.value = .tape;
            widget.setTool(TapePen.currentTape);
          }
        },
      ),
      _ToolItem(
        tooltip: t.editor.toolbar.toggleEraser,
        icon: FontAwesomeIcons.eraser,
        selected: widget.currentTool is Eraser,
        enabled: !readOnly,
        onTap: toggleEraser,
      ),
      _ToolItem(
        tooltip: t.editor.toolbar.select,
        icon: CupertinoIcons.lasso,
        selected: widget.currentTool is Select,
        enabled: !readOnly,
        onTap: () {
          toolOptionsType.value = .hide;
          widget.setTool(Select.currentSelect);
        },
      ),
      _ToolItem(
        tooltip: t.editor.toolbar.undo,
        icon: Icons.undo,
        enabled: !readOnly && widget.isUndoPossible,
        onTap: widget.undo,
      ),
      _ToolItem(
        tooltip: t.editor.toolbar.redo,
        icon: Icons.redo,
        enabled: !readOnly && widget.isRedoPossible,
        onTap: widget.redo,
      ),
      _ToolItem(
        tooltip: 'Text-Stempel (VERTRAULICH, ERLEDIGT …)',
        icon: StampPen.stampIcon,
        tint: _tint(const Color(0xFFD32F2F), invert),
        enabled: !readOnly,
        onTap: () async {
          final result = await showTextStampDialog(context);
          if (result != null) {
            StampPen.onPlaceText?.call(result.$1, result.$2);
          }
        },
      ),
      _ToolItem(
        tooltip: 'Lineal',
        icon: Icons.straighten,
        selected: widget.rulerVisible,
        enabled: !readOnly,
        onTap: widget.toggleRuler,
      ),
      _ToolItem(
        tooltip: 'Schreibfeld',
        icon: Icons.edit_note,
        selected: widget.writingPadVisible,
        enabled: !readOnly,
        onTap: widget.toggleWritingPad,
      ),
      _ToolItem(
        tooltip: t.editor.toolbar.photo,
        icon: Icons.photo,
        enabled: !readOnly,
        onTap: widget.pickPhoto,
      ),
      _ToolItem(
        tooltip: t.editor.toolbar.text,
        icon: Icons.text_fields,
        selected: widget.textEditing,
        enabled: !readOnly,
        onTap: widget.toggleTextEditing,
      ),
      _penItem(() => BrushPen.current, invert),
      _penItem(() => FinelinerPen.current, invert),
      _ToolItem(
        tooltip: widget.protractorMode == 0
            ? 'Winkelmesser (Halbkreis)'
            : widget.protractorMode == 1
            ? 'Winkelmesser (Vollkreis)'
            : 'Winkelmesser ausblenden',
        icon: Icons.square_foot,
        selected: widget.protractorMode != 0,
        enabled: !readOnly,
        onTap: widget.toggleProtractor,
      ),
      _ToolItem(
        tooltip: t.editor.pens.shapePen,
        icon: Icons.category_outlined,
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
      _ToolItem(
        tooltip: t.editor.pens.laserPointer,
        icon: Symbols.stylus_laser_pointer,
        selected: laserSelected,
        onTap: () {
          toolOptionsType.value = .hide;
          widget.setTool(LaserPointer.currentLaserPointer);
        },
      ),
    ];
  }

  /// Einträge, die immer nur im Aufklappmenü stehen.
  List<_ToolItem> _extraItems() {
    final readOnly = widget.readOnly;
    return [
      if (!stows.hideFingerDrawingToggle.value)
        _ToolItem(
          tooltip: t.editor.toolbar.toggleFingerDrawing,
          icon: CupertinoIcons.hand_draw,
          selected: stows.editorFingerDrawing.value,
          enabled: !readOnly,
          onTap: widget.toggleFingerDrawing,
        ),
      _ToolItem(
        tooltip: 'Tabelle einfügen',
        icon: Icons.table_chart_outlined,
        selected: false,
        enabled: !readOnly,
        onTap: widget.insertTable,
      ),
      _ToolItem(
        tooltip: 'Vorlage einfügen',
        icon: Icons.assignment_outlined,
        selected: false,
        enabled: !readOnly,
        onTap: widget.insertTemplate,
      ),
      _ToolItem(
        tooltip: 'Farbleiste',
        icon: Icons.palette_outlined,
        selected: showColorOptions.value,
        enabled: !readOnly,
        onTap: toggleColorOptions,
      ),
      _ToolItem(
        tooltip: t.editor.toolbar.fullscreen,
        icon: DynamicMaterialApp.isFullscreen
            ? Icons.fullscreen_exit
            : Icons.fullscreen,
        selected: DynamicMaterialApp.isFullscreen,
        enabled: !readOnly,
        onTap: toggleFullscreen,
      ),
      _ToolItem(
        tooltip: t.editor.toolbar.export,
        icon: Icons.share,
        selected: showExportOptions.value,
        enabled: !readOnly,
        onTap: toggleExportBar,
      ),
    ];
  }

  _MenuEntry _menuEntryOf(_ToolItem item) => _MenuEntry(
    icon: item.icon,
    label: item.tooltip,
    selected: item.selected,
    enabled: item.enabled,
    onTap: item.onTap,
    tint: item.tint,
  );

  Widget _itemButton(_ToolItem item, EdgeInsets padding) {
    final tint = item.tint;
    return ToolbarIconButton(
      tooltip: item.tooltip,
      selected: item.selected,
      enabled: item.enabled,
      onPressed: item.onTap,
      padding: padding,
      compact: true,
      tinted: tint != null,
      child: _toolIcon(item, tint),
    );
  }

  /// Symbol in Stiftfarbe; sehr helle Farben (Weiß, Gelb …) bekommen einen
  /// dunklen Kreis dahinter, damit sie auf hellem Grund lesbar bleiben.
  Widget _toolIcon(_ToolItem item, Color? tint) {
    if (tint == null) return UniIcon(item.icon);
    final icon = UniIcon(
      item.icon,
      color: item.enabled ? tint : tint.withValues(alpha: 0.4),
    );
    if (tint.computeLuminance() <= 0.75) return icon;
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: -4,
            right: -4,
            top: -4,
            bottom: -4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
            ),
          ),
          icon,
        ],
      ),
    );
  }

  /// Eine Reihe mit den wichtigsten Werkzeugen; der Rest steckt hinter ⋮.
  Widget _toolRow(BuildContext context, bool vertical, bool invert) {
    final allItems = _toolItems(context, invert);
    final extras = _extraItems();
    final padding = vertical
        ? const EdgeInsets.symmetric(vertical: 1)
        : const EdgeInsets.symmetric(horizontal: 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = vertical ? constraints.maxHeight : constraints.maxWidth;
        // Smartphone (schmale Leiste): Rückgängig/Wiederholen bleiben immer sichtbar.
        final phone = !vertical && extent.isFinite && extent < 600;
        final undoTip = t.editor.toolbar.undo;
        final redoTip = t.editor.toolbar.redo;
        final pinned = phone
            ? [
                for (final i in allItems)
                  if (i.tooltip == undoTip || i.tooltip == redoTip) i,
              ]
            : <_ToolItem>[];
        final items = phone
            ? [
                for (final i in allItems)
                  if (!pinned.contains(i)) i,
              ]
            : allItems;
        final capacity = extent.isFinite
            ? ((extent - 16) / _slotMeasured).floor()
            : 99;
        final visibleCount = math.max(
          0,
          math.min(items.length, capacity - 1 - pinned.length),
        );
        final overflow = [...items.skip(visibleCount), ...extras];
        final shown = [...pinned, ...items.take(visibleCount)];
        _measureSlot(vertical);
        return Center(
          child: Padding(
            padding: const .all(8),
            child: Flex(
              direction: vertical ? .vertical : .horizontal,
              mainAxisSize: .min,
              children: [
                for (var i = 0; i < shown.length; i++)
                  i == 0
                      ? KeyedSubtree(
                          key: _slotKey,
                          child: _itemButton(shown[i], padding),
                        )
                      : _itemButton(shown[i], padding),
                _menuButton(
                  context,
                  padding,
                  tooltip: 'Mehr',
                  icon: const Icon(Icons.more_vert),
                  selected:
                      overflow.any((e) => e.selected) &&
                      overflow.length > extras.length,
                  entries: [for (final e in overflow) _menuEntryOf(e)],
                  compact: true,
                ),
              ],
            ),
          ),
        );
      },
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
                saveAsTemplate: widget.saveAsTemplate,
                deleteSelection: widget.deleteSelection,
                sendToNextcloud: widget.sendToNextcloud,
                solveMath: widget.solveMath,
                hasTable: (widget.currentTool as Select).selectResult.strokes
                    .any((s) => s.tableAxis != null),
                extendTable: widget.extendTable,
                adjustSelection: widget.adjustSelection,
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
      _toolRow(context, isToolbarVertical, invert),
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
    this.tint,
  });

  final Object icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final Color? tint;
}

/// Ein Werkzeug der Leiste (Knopf in der Reihe oder Eintrag im Menü).
class _ToolItem {
  const _ToolItem({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.tint,
    this.selected = false,
    this.enabled = true,
  });

  final String tooltip;
  final Object icon;
  final VoidCallback onTap;
  final Color? tint;
  final bool selected;
  final bool enabled;
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
