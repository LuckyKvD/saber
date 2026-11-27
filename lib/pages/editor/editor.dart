import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collapsible/collapsible.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as flutter_quill;
import 'package:keybinder/keybinder.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas.dart';
import 'package:saber/components/canvas/guide_tools.dart';
import 'package:saber/components/toolbar/text_stamp.dart';
import 'package:saber/components/math/math_solve_dialog.dart';
import 'package:saber/data/math/handwriting_text.dart';
import 'package:saber/components/tasks/create_task_dialog.dart';
import 'package:saber/data/tasks/ink_recognition.dart';
import 'package:saber/data/tasks/nextcloud_dav.dart';
import 'package:saber/data/quick_note.dart';
import 'package:saber/data/tools/extra_pens.dart';
import 'package:saber/components/canvas/image/image_clip.dart';
import 'package:saber/data/photo_sources.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/save_indicator.dart';
import 'package:saber/components/editor/read_only_banner.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/components/toolbar/editor_bottom_sheet.dart';
import 'package:saber/components/toolbar/editor_page_manager.dart';
import 'package:saber/components/toolbar/pick_notebook_dialog.dart';
import 'package:saber/data/page_transfer.dart';
import 'package:saber/components/toolbar/toolbar.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/change_notifier_extensions.dart';
import 'package:saber/data/extensions/matrix4_extensions.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/tape_pen.dart';
import 'package:saber/components/toolbar/writing_pad.dart';
import 'package:saber/components/toolbar/writing_pad_guide.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/change.dart';
import 'package:super_clipboard/super_clipboard.dart';

class const _PhotoInfo(final Uint8List bytes, final String extension);

class Editor extends StatefulWidget {
  new({super.key, String? path, this.customTitle, this.pdfPath})
    : initialPath = path != null
          ? Future.value(path)
          : FileManager.newFilePath('/'),
      needsNaming = path == null;

  final Future<String> initialPath;
  final bool needsNaming;

  final String? customTitle;
  final String? pdfPath;

  /// The file extension used by the app.
  /// Files with this extension are
  /// encoded in BSON format.
  static const extension = '.sbn2';

  /// The old file extension used by the app.
  /// Files with this extension are
  /// encoded in JSON format.
  static const extensionOldJson = '.sbn';

  static const double gapBetweenPages = 16;

  /// Returns true if [path] belongs to a hidden file
  /// used by other functions of the app
  static bool isReservedPath(String path) {
    return _reservedFilePaths.any((regex) => regex.hasMatch(path));
  }

  static final _reservedFilePaths = <RegExp>[
    RegExp(RegExp.escape('/_whiteboard')),
  ];

  /// Whether the platform can rasterize a pdf
  static var canRasterPdf = true;

  @override
  State<Editor> createState() => EditorState();
}

class EditorState extends State<Editor> {
  final log = Logger('EditorState');

  late var coreInfo = EditorCoreInfo.placeholder;

  final _canvasGestureDetectorKey = GlobalKey<CanvasGestureDetectorState>();
  final _transformationController = TransformationController();
  double get scrollY {
    final transformation = _transformationController.value;
    final scale = transformation.approxScale;
    final translation = transformation.getTranslation();
    final gestureDetector = _canvasGestureDetectorKey.currentState;

    if (gestureDetector == null) {
      log.warning('scrollY: Could not find CanvasGestureDetectorState');
      return translation.y / scale;
    } else {
      final middle = gestureDetector.containerBounds.maxHeight / 2;
      return (translation.y - middle) / scale + middle;
    }
  }

  /// Feder: Blättern wie im Buch (Seiten nebeneinander) für dieses Notizbuch.
  bool get horizontalPaging =>
      coreInfo.filePath.isNotEmpty &&
      stows.horizontalPagingFiles.value.contains(coreInfo.filePath);

  /// Scrollt zur Seite, egal ob vertikal oder horizontal geblättert wird.
  void scrollToPageIndex(int pageIndex) {
    if (horizontalPaging) {
      CanvasGestureDetector.scrollToPageHorizontal(
        pageIndex: pageIndex,
        pages: coreInfo.pages,
        containerWidth:
            _canvasGestureDetectorKey.currentState?.containerBounds.maxWidth ??
            MediaQuery.sizeOf(context).width,
        containerHeight:
            _canvasGestureDetectorKey.currentState?.containerBounds.maxHeight ??
            MediaQuery.sizeOf(context).height * 0.85,
        transformationController: _transformationController,
      );
    } else {
      CanvasGestureDetector.scrollToPage(
        pageIndex: pageIndex,
        pages: coreInfo.pages,
        screenWidth: MediaQuery.sizeOf(context).width,
        transformationController: _transformationController,
      );
    }
  }

  void toggleHorizontalPaging() {
    final pageIndex = currentPageIndex;
    final files = [...stows.horizontalPagingFiles.value];
    if (!files.remove(coreInfo.filePath)) files.add(coreInfo.filePath);
    stows.horizontalPagingFiles.value = files;
    _transformationController.value = Matrix4.identity();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) scrollToPageIndex(pageIndex);
    });
  }

  var history = EditorHistory();

  /// Schreibfeld (Easy-Writing) sichtbar?
  bool showWritingPad = false;
  final writingPadController = WritingPadController();
  bool _placingWritingPad = false;
  bool _draggingWritingPad = false;
  bool _resizingWritingPad = false;
  double _resizeStartWidth = 0;
  Offset _resizeStartPosition = Offset.zero;
  Offset _guideDragLast = Offset.zero;

  /// Stift, mit dem der aktuelle Strich im Schreibfeld entsteht.
  Pen? _writingStrokePen;

  /// Stift für das Schreibfeld: der aktuelle Stift, sonst der letzte normale.
  Pen get _writingPadPen {
    final tool = currentTool;
    if (tool is Pen &&
        tool is! Highlighter &&
        tool is! TapePen &&
        tool is! ShapePen) {
      return tool;
    }
    final pen = Pen.currentPen;
    return pen is ShapePen ? Pen.fountainPen() : pen;
  }

  void _writingStrokeStart(int pageIndex, Offset position, double? pressure) {
    if (coreInfo.readOnly) return;
    final pen = _writingPadPen;
    _writingStrokePen = pen;
    history.canRedo = false;
    Select.currentSelect.unselect();
    pen.onDragStart(position, coreInfo.pages[pageIndex], pageIndex, pressure);
    // setState, damit die Seite den laufenden Strich kennt
    setState(() {});
  }

  void _writingStrokeUpdate(Offset position, double? pressure) {
    final pen = _writingStrokePen;
    if (pen == null) return;
    pen.onDragUpdate(position, pressure);
    final index = Pen.currentStroke?.pageIndex;
    if (index != null && index < coreInfo.pages.length) {
      coreInfo.pages[index].redrawStrokes();
    }
  }

  void _writingStrokeEnd() {
    final pen = _writingStrokePen;
    _writingStrokePen = null;
    if (pen == null) return;

    final newStroke = pen.onDragEnd();
    if (newStroke == null || newStroke.isEmpty) {
      setState(() {});
      return;
    }
    if (stows.autoStraightenLines.value &&
        pen is! ShapePen &&
        newStroke.isStraightLine()) {
      newStroke.convertToLine();
    }
    setState(() {
      createPage(newStroke.pageIndex);
      coreInfo.pages[newStroke.pageIndex].insertStroke(newStroke);
      history.recordChange(HistoricAdd(strokes: [newStroke], images: []));
    });
    autosaveAfterDelay();
  }

  void _attachWritingPad() {
    writingPadController.attach(
      pages: coreInfo.pages,
      ensurePage: (index) => setState(() => createPage(index)),
      cell: coreInfo.lineHeight.toDouble(),
      owner: coreInfo,
    );
  }

  GuideEdge? _guideEdge;

  int? _guideSyncPage;

  /// Hilfsmittel folgen der Seite, zu der man scrollt (nur beim Seitenwechsel
  /// durch Scrollen, nicht nach einem Ziehen des Hilfsmittels selbst).
  void _syncGuidesToPage() {
    if (!mounted || !Guides.anyVisible || !identical(Guides.owner, coreInfo)) {
      return;
    }
    _prepareGuides();
    final index = currentPageIndex;
    if (index == _guideSyncPage) return;
    _guideSyncPage = index;
    if (index == Guides.pageIndex || Guides.grabbing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !Guides.grabbing) Guides.moveToPage(index);
    });
  }

  void _prepareGuides() {
    Guides.pageSizes = [for (final p in coreInfo.pages) p.size];
    Guides.verticalPages = !horizontalPaging;
  }

  void _toggleRuler() {
    _prepareGuides();
    _guideSyncPage = currentPageIndex;
    final index = currentPageIndex.clamp(0, coreInfo.pages.length - 1);
    setState(() {
      Guides.toggleRuler(coreInfo, index, coreInfo.pages[index].size);
    });
  }

  void _toggleProtractor() {
    _prepareGuides();
    _guideSyncPage = currentPageIndex;
    final index = currentPageIndex.clamp(0, coreInfo.pages.length - 1);
    setState(() {
      Guides.cycleProtractor(coreInfo, index, coreInfo.pages[index].size);
    });
  }

  void _toggleWritingPad() {
    if (showWritingPad) {
      _closeWritingPad();
    } else {
      showWritingPad = true;
      _attachWritingPad();
      // meldet sich über den Listener: Rahmen zeichnen und Blatt mitscrollen
      writingPadController.openAt(currentPageIndex);
    }
  }

  /// Schließt das Schreibfeld und nimmt den Rahmen im selben Schritt vom Blatt.
  void _closeWritingPad() {
    showWritingPad = false;
    writingPadController.close();
  }

  void _onWritingPadChanged() {
    if (!mounted) return;
    setState(() {});
    // Beim Ziehen mit dem Finger nicht mitscrollen, sonst läuft der Rahmen weg.
    if (showWritingPad && !_draggingWritingPad && !_resizingWritingPad) {
      _revealWritingWindow();
    }
  }

  /// Scrollt das Blatt so, dass der Rahmen sichtbar bleibt
  /// (das Schreibfeld nimmt unten Platz weg).
  void _revealWritingWindow({bool retry = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !showWritingPad) return;
      final controller = writingPadController;
      if (controller.pageIndex >= coreInfo.pages.length) return;
      final pageBox = coreInfo.pages[controller.pageIndex].renderBox;
      final viewBox =
          _canvasGestureDetectorKey.currentContext?.findRenderObject()
              as RenderBox?;
      if (pageBox == null ||
          viewBox == null ||
          !pageBox.attached ||
          !viewBox.attached) {
        // Seite ist noch nicht aufgebaut (z. B. neue Seite): dorthin scrollen
        // und es danach noch einmal versuchen.
        if (retry && viewBox != null) {
          scrollToPageIndex(controller.pageIndex);
          _revealWritingWindow(retry: false);
        }
        return;
      }

      final rect = controller.rect;
      final top = viewBox
          .globalToLocal(pageBox.localToGlobal(rect.topLeft))
          .dy;
      final bottom = viewBox
          .globalToLocal(pageBox.localToGlobal(rect.bottomRight))
          .dy;
      const gap = 12.0;
      var dy = 0.0;
      if (bottom > viewBox.size.height - gap) {
        dy = viewBox.size.height - gap - bottom;
      }
      if (top + dy < gap) dy = gap - top;
      if (dy.abs() < 0.5) return;

      _transformationController.value =
          Matrix4.translationValues(0, dy, 0) * _transformationController.value;
    });
  }

  Widget _buildWritingPad() {
    _attachWritingPad();
    return WritingPad(
      key: const ValueKey('writingPad'),
      controller: writingPadController,
      coreInfo: coreInfo,
      enabled: !coreInfo.readOnly,
      onStrokeStart: _writingStrokeStart,
      onStrokeUpdate: _writingStrokeUpdate,
      onStrokeEnd: _writingStrokeEnd,
    );
  }

  late bool needsNaming = widget.needsNaming && stows.editorPromptRename.value;

  late Tool _currentTool = () {
    switch (stows.lastTool.value) {
      case .fountainPen:
        if (Pen.currentPen.toolId != stows.lastTool.value) {
          Pen.currentPen = Pen.fountainPen();
        }
        return Pen.currentPen;
      case .ballpointPen:
        if (Pen.currentPen.toolId != stows.lastTool.value) {
          Pen.currentPen = Pen.ballpointPen();
        }
        return Pen.currentPen;
      case .shapePen:
        if (Pen.currentPen.toolId != stows.lastTool.value) {
          Pen.currentPen = ShapePen();
        }
        return Pen.currentPen;
      case .highlighter:
        return Highlighter.currentHighlighter;
      case .tape:
        return TapePen.currentTape;
      case .pencil:
        return Pencil.currentPencil;
      case .eraser:
        return Eraser();
      case .select:
        return Select.currentSelect;
      case .textEditing:
        return Tool.textEditing;
      case .laserPointer:
        return LaserPointer.currentLaserPointer;
    }
  }();
  Tool get currentTool => _currentTool;
  set currentTool(Tool tool) {
    _currentTool = tool;
    if (tool is! Eraser) _lastNonEraserTool = tool;
    stows.lastTool.value = tool.toolId;
  }

  ValueNotifier<SavingState> savingState = ValueNotifier(SavingState.saved);
  Timer? _delayedSaveTimer;
  Timer? _watchServerTimer;

  // used to prevent accidentally drawing when pinch zooming
  var lastSeenPointerCount = 0;
  Timer? _lastSeenPointerCountTimer;

  ValueNotifier<QuillStruct?> quillFocus = ValueNotifier(null);

  /// The last non-Eraser [currentTool] value.
  late Tool _lastNonEraserTool = Pen.currentPen;

  /// If the stylus button is pressed, or was pressed, during the current draw gesture.
  ///
  /// For now, this also includes when an [PointerDeviceKind.inverseStylus] is
  /// used since the stylus rear-end and stylus button currently act the same.
  /// If we add customized button bindings, we may have to separate this again.
  var stylusButtonWasPressed = false;

  @override
  void initState() {
    DynamicMaterialApp.addFullscreenListener(_setState);
    Pen.onHoldShapeDetected = _setState;
    writingPadController.addListener(_onWritingPadChanged);
    _transformationController.addListener(_syncGuidesToPage);
    StampPen.onPlaceText = _placeTextStamp;
    EditorImage.dropHandler = _onDropImage;
    EditorImage.targetHandler = _startImageTarget;

    _initAsync();
    _assignKeybindings();

    super.initState();
  }

  void _initAsync() async {
    final filePath = await widget.initialPath;
    filenameTextEditingController.text = p.basename(filePath);

    if (needsNaming) {
      filenameTextEditingController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: filenameTextEditingController.text.length,
      );
    }

    await _loadCoreInfo(filePath);

    if (widget.pdfPath != null) {
      await importPdfFromFilePath(widget.pdfPath!);
    }
  }

  Future _loadCoreInfo(String filePath) async {
    coreInfo = await EditorCoreInfo.loadFromFilePath(filePath);
    if (coreInfo.readOnly) {
      log.info('Loaded file as read-only: ${coreInfo.readOnlyReason}');
    }

    for (int pageIndex = 0; pageIndex < coreInfo.pages.length; pageIndex++) {
      listenToQuillChanges(coreInfo.pages[pageIndex].quill, pageIndex);
    }

    if (coreInfo.isEmpty) {
      createPage(-1);
    } else {
      for (final page in coreInfo.pages) {
        page.backgroundImage?.onMoveImage = onMoveImage;
        page.backgroundImage?.onDeleteImage = onDeleteImage;
        page.backgroundImage?.onMiscChange = autosaveAfterDelay;
        for (final image in page.images) {
          image.onMoveImage = onMoveImage;
          image.onDeleteImage = onDeleteImage;
          image.onMiscChange = autosaveAfterDelay;
        }
      }
    }

    if (currentTool == Tool.textEditing) {
      int pageIndex;
      if (coreInfo.initialPageIndex != null) {
        pageIndex = coreInfo.initialPageIndex!;
      } else {
        pageIndex = 0;
      }
      assert(pageIndex < coreInfo.pages.length);

      quillFocus.value = coreInfo.pages[pageIndex].quill
        ..focusNode.requestFocus();
    }

    setState(() {});
  }

  void _setState() => setState(() {});

  Keybinding? _ctrlZ, _ctrlY, _ctrlShiftZ;
  void _assignKeybindings() {
    _ctrlZ = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyZ),
    ], inclusive: true);
    _ctrlY = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyY),
    ], inclusive: true);
    _ctrlShiftZ = Keybinding([
      KeyCode.ctrl,
      KeyCode.shift,
      KeyCode.from(LogicalKeyboardKey.keyZ),
    ], inclusive: true);
    Keybinder.bind(_ctrlZ!, undo);
    Keybinder.bind(_ctrlY!, redo);
    Keybinder.bind(_ctrlShiftZ!, redo);
  }

  void _removeKeybindings() {
    if (_ctrlZ != null) Keybinder.remove(_ctrlZ!);
    if (_ctrlY != null) Keybinder.remove(_ctrlY!);
    if (_ctrlShiftZ != null) Keybinder.remove(_ctrlShiftZ!);
  }

  /// Creates pages until the given page index exists,
  /// plus an extra blank page
  void createPage(int pageIndex) {
    while (pageIndex >= coreInfo.pages.length - 1) {
      final page = EditorPage();
      coreInfo.pages.add(page);
      listenToQuillChanges(page.quill, coreInfo.pages.length - 1);
    }
  }

  void removeExcessPages() {
    bool removedAPage = false;

    // remove excess pages if all pages >= this one are empty
    for (int i = coreInfo.pages.length - 1; i >= 1; --i) {
      final thisPage = coreInfo.pages[i];
      final prevPage = coreInfo.pages[i - 1];
      if (thisPage.isEmpty && prevPage.isEmpty) {
        final page = coreInfo.pages.removeAt(i);
        page.dispose();
        removedAPage = true;
      } else {
        break;
      }
    }

    if (removedAPage && !horizontalPaging) {
      // scroll to the last page (only if we're below the last page)

      final scrollY = this.scrollY;
      late final topOfLastPage = -CanvasGestureDetector.getTopOfPage(
        pageIndex: coreInfo.pages.length - 1,
        pages: coreInfo.pages,
        screenWidth: MediaQuery.sizeOf(context).width,
      );
      final bottomOfLastPage = -CanvasGestureDetector.getTopOfPage(
        pageIndex: coreInfo.pages.length,
        pages: coreInfo.pages,
        screenWidth: MediaQuery.sizeOf(context).width,
      );

      if (scrollY < bottomOfLastPage) {
        _transformationController.value = Matrix4.translationValues(
          0,
          // Slight upwards offset so that the page is not flush with the top of the screen
          topOfLastPage + 50,
          0,
        );
      }
    }
  }

  void undo([Historic? historic]) {
    if (historic == null) {
      if (!history.canUndo) return;

      // if we disabled redo, re-enable it
      if (!history.canRedo) {
        // no redo is possible, so clear the redo stack
        history.clearRedo();
        // don't disable redoing anymore
        history.canRedo = true;
      }

      historic = history.undo();
    }

    switch (historic) {
      case (final HistoricAdd historic):
        for (final stroke in historic.strokes) {
          coreInfo.pages[stroke.pageIndex].strokes.remove(stroke);
        }
        for (final image in historic.images) {
          coreInfo.pages[image.pageIndex].images.remove(image);
        }
        removeExcessPages();

      case (final HistoricDelete historic):
        for (final stroke in historic.strokes) {
          createPage(stroke.pageIndex);
          coreInfo.pages[stroke.pageIndex].insertStroke(stroke);
        }
        for (final image in historic.images) {
          createPage(image.pageIndex);
          coreInfo.pages[image.pageIndex].images.add(image);
          image.newImage = true;
        }

      case (final HistoricReplace historic):
        // Rückgängig: neue Teilstriche entfernen, alte Striche wieder einsetzen
        for (final stroke in historic.added) {
          coreInfo.pages[stroke.pageIndex].strokes.remove(stroke);
        }
        for (final stroke in historic.removed) {
          createPage(stroke.pageIndex);
          coreInfo.pages[stroke.pageIndex].insertStroke(stroke);
        }
        for (final image in historic.addedImages) {
          coreInfo.pages[image.pageIndex].images.remove(image);
        }
        for (final image in historic.removedImages) {
          createPage(image.pageIndex);
          coreInfo.pages[image.pageIndex].images.add(image);
        }
        removeExcessPages();

      case (final HistoricPageDelete historic):
        // make sure we already have a (blank/otherwise) page at this index
        createPage(historic.pageIndex - 1);

        // insert the page at the correct index
        coreInfo.pages.insert(historic.pageIndex, historic.page);

        // fix the page indices of all pages after this one
        for (int i = historic.pageIndex + 1; i < coreInfo.pages.length; ++i) {
          final page = coreInfo.pages[i];
          page.updatePageIndex(i);
        }

      case (final HistoricPageInsert historic):
        // remove the page at the given index
        coreInfo.pages.removeAt(historic.pageIndex);

        // fix the page indices of all pages after this one
        for (int i = historic.pageIndex; i < coreInfo.pages.length; ++i) {
          final page = coreInfo.pages[i];
          page.updatePageIndex(i);
        }

      case (final HistoricMove historic):
        for (final stroke in historic.strokes) {
          stroke.shift(Offset(-historic.offset.left, -historic.offset.top));
          if (historic.pageIndex != historic.prevPageIndex) {
            moveStrokeToPage(
              stroke,
              historic.pageIndex,
              historic.prevPageIndex,
            );
          }
        }
        final select = Select.currentSelect;
        if (select.doneSelecting) {
          select.selectResult.path = select.selectResult.path.shift(
            Offset(-historic.offset.left, -historic.offset.top),
          );
          if (historic.pageIndex != historic.prevPageIndex) {
            select.selectResult.pageIndexStart = historic.prevPageIndex;
            select.selectResult.pageIndex = historic.prevPageIndex;
          }
        }
        for (final image in historic.images) {
          image.dstRect = .fromLTRB(
            image.dstRect.left - historic.offset.left,
            image.dstRect.top - historic.offset.top,
            image.dstRect.right - historic.offset.right,
            image.dstRect.bottom - historic.offset.bottom,
          );
          if (historic.pageIndex != historic.prevPageIndex) {
            moveImageToPage(image, historic.pageIndex, historic.prevPageIndex);
          }
        }

      case (final HistoricQuillChange historic):
        final quill = coreInfo.pages[historic.pageIndex].quill;
        quill.controller.undo();

      case (final HistoricQuillReverseChange historic):
        final quill = coreInfo.pages[historic.pageIndex].quill;
        quill.controller.redo();

      case (final HistoricColorChange historic):
        for (final entry in historic.colorChanges.entries) {
          entry.key.color = entry.value.previous;
        }

      case (final HistoricBackgroundPatternChange historic):
        coreInfo.backgroundPattern = historic.change.previous;
    }

    if (historic is! HistoricMove) {
      Select.currentSelect.unselect();
    }

    if (mounted) setState(() {});

    autosaveAfterDelay();
  }

  void redo() {
    if (!history.canRedo) return;
    final historic = history.redo();
    undo(historic.reverse());
  }

  int? onWhichPageIsFocalPoint(Offset focalPoint) {
    for (int i = 0; i < coreInfo.pages.length; ++i) {
      if (coreInfo.pages[i].renderBox == null) continue;
      final pageBounds = Offset.zero & coreInfo.pages[i].size;
      if (pageBounds.contains(
        coreInfo.pages[i].renderBox!.globalToLocal(focalPoint),
      ))
        return i;
    }
    return null;
  }

  /// The position of the previous draw gesture event.
  /// Used to move a selection.
  Offset previousPosition = .zero;

  /// The total offset of the current move gesture.
  /// Used to record a move in the history.
  Offset moveOffset = .zero;

  var isHovering = true;
  int? dragPageIndex;
  PointerDeviceKind? currentPointerKind;
  double? currentPressure;
  bool _focalPointInWritingGuide(Offset focalPoint, int pageIndex) {
    final rect = WritingPadGuide.rectFor(coreInfo, pageIndex);
    final box = coreInfo.pages[pageIndex].renderBox;
    if (rect == null || box == null) return false;
    return rect.inflate(12).contains(box.globalToLocal(focalPoint));
  }

  bool _focalPointOnWritingHandle(Offset focalPoint, int pageIndex) {
    final rect = WritingPadGuide.rectFor(coreInfo, pageIndex);
    final box = coreInfo.pages[pageIndex].renderBox;
    if (rect == null || box == null) return false;
    return (box.globalToLocal(focalPoint) - rect.bottomRight).distance < 34;
  }

  bool isDrawGesture(ScaleStartDetails details) {
    if (coreInfo.readOnly) return false;

    CanvasImage.activeListener
        .notifyListenersPlease(); // un-select active image

    _lastSeenPointerCountTimer?.cancel();
    if (lastSeenPointerCount >= 2) {
      // was a zoom gesture, ignore
      lastSeenPointerCount = lastSeenPointerCount;
      return false;
    } else if (details.pointerCount >= 2) {
      // is a zoom gesture, remove accidental stroke
      if (lastSeenPointerCount == 1 &&
          stows.editorFingerDrawing.value &&
          (currentTool is Pen || currentTool is Eraser)) {
        final item = history.removeAccidentalStroke();
        if (item != null) undo(item);
      }
      lastSeenPointerCount = details.pointerCount;
      return false;
    } else {
      // is a stroke
      lastSeenPointerCount = details.pointerCount;
    }

    dragPageIndex = onWhichPageIsFocalPoint(details.focalPoint);
    if (dragPageIndex == null) return false;

    if (currentTool == Tool.textEditing) {
      return false;
    } else if (showWritingPad &&
        currentPointerKind == PointerDeviceKind.touch &&
        (_focalPointOnWritingHandle(details.focalPoint, dragPageIndex!) ||
            _focalPointInWritingGuide(details.focalPoint, dragPageIndex!))) {
      // Finger auf dem Rahmen des Schreibfelds: Rahmen verschieben.
      return true;
    } else if (stows.editorFingerDrawing.value ||
        currentPointerKind == PointerDeviceKind.stylus ||
        currentPointerKind == PointerDeviceKind.invertedStylus ||
        currentPressure != null) {
      return true;
    } else {
      log.fine('Non-stylus found, rejected stroke');
      return false;
    }
  }

  static const changePageThreshold = 50.0;

  void onDrawStart(ScaleStartDetails details) {
    final page = coreInfo.pages[dragPageIndex!];
    var position = page.renderBox!.globalToLocal(details.focalPoint);

    _guideEdge = null;
    if (currentTool is Pen &&
        currentPointerKind != PointerDeviceKind.touch &&
        Guides.isActiveFor(coreInfo, dragPageIndex!)) {
      final edge = Guides.edgeNear(position, page.size);
      if (edge != null) {
        _guideEdge = edge;
        position = Guides.project(edge, position, page.size);
      }
    }

    if (showWritingPad &&
        currentPointerKind == PointerDeviceKind.touch &&
        _focalPointOnWritingHandle(details.focalPoint, dragPageIndex!)) {
      // Eckgriff: Rahmen breiter oder schmaler ziehen.
      _placingWritingPad = true;
      _resizingWritingPad = true;
      _resizeStartPosition = position;
      _resizeStartWidth = writingPadController.width;
      return;
    }
    if (showWritingPad &&
        currentPointerKind == PointerDeviceKind.touch &&
        _focalPointInWritingGuide(details.focalPoint, dragPageIndex!)) {
      // Finger im Rahmen: Rahmen verschieben.
      _placingWritingPad = true;
      _draggingWritingPad = true;
      _guideDragLast = position;
      return;
    }
    history.canRedo = false;

    if (currentTool is Pen) {
      (currentTool as Pen).onDragStart(
        position,
        page,
        dragPageIndex!,
        currentPressure,
      );
    } else if (currentTool is Eraser) {
      final eraser = currentTool as Eraser;
      if (eraser.partial) {
        for (final (old, pieces) in eraser.erasePartially(
          position,
          page.strokes,
        )) {
          page.strokes.remove(old);
          pieces.forEach(page.insertStroke);
        }
      } else {
        for (final stroke in eraser.checkForOverlappingStrokes(
          position,
          page.strokes,
        )) {
          page.strokes.remove(stroke);
        }
      }
      removeExcessPages();
    } else if (currentTool is Select) {
      final select = currentTool as Select;
      if (select.doneSelecting &&
          select.selectResult.pageIndex == dragPageIndex! &&
          select.selectResult.path.contains(position)) {
        // drag selection in onDrawUpdate
      } else {
        select.onDragStart(position, dragPageIndex!);
        history.canRedo = true; // selection doesn't affect history
      }
    } else if (currentTool is LaserPointer) {
      (currentTool as LaserPointer).onDragStart(position, page, dragPageIndex!);
    }

    previousPosition = position;
    moveOffset = .zero;

    if (currentTool is! Select) {
      Select.currentSelect.unselect();
    }

    // setState to let canvas know about currentStroke
    setState(() {});
  }

  void onDrawUpdate(ScaleUpdateDetails details) {
    if (_resizingWritingPad && dragPageIndex != null) {
      final box = coreInfo.pages[dragPageIndex!].renderBox;
      if (box != null) {
        final now = box.globalToLocal(details.focalPoint);
        final controller = writingPadController;
        final dx = now.dx - _resizeStartPosition.dx;
        final dy = now.dy - _resizeStartPosition.dy;
        // Diagonal ziehen: Breite und Höhe (über das feste Seitenverhältnis) mitteln.
        controller.setWidth(
          _resizeStartWidth + (dx + dy / controller.aspect) / 2,
        );
      }
      return;
    }
    if (_draggingWritingPad && dragPageIndex != null) {
      final box = coreInfo.pages[dragPageIndex!].renderBox;
      if (box != null) {
        final now = box.globalToLocal(details.focalPoint);
        writingPadController.moveBy(now - _guideDragLast);
        _guideDragLast = now;
      }
      return;
    }
    if (dragPageIndex == null || _placingWritingPad) {
      return;
    }
    final page = coreInfo.pages[dragPageIndex!];
    Offset position = page.renderBox!.globalToLocal(details.focalPoint);
    if (_guideEdge != null && currentTool is Pen) {
      position = Guides.project(_guideEdge!, position, page.size);
    }
    Offset offset = position - previousPosition;

    if (currentTool is Pen) {
      (currentTool as Pen).onDragUpdate(position, currentPressure);
      page.redrawStrokes();
    } else if (currentTool is Eraser) {
      final eraser = currentTool as Eraser;
      if (eraser.partial) {
        for (final (old, pieces) in eraser.erasePartially(
          position,
          page.strokes,
        )) {
          page.strokes.remove(old);
          pieces.forEach(page.insertStroke);
        }
      } else {
        for (final stroke in eraser.checkForOverlappingStrokes(
          position,
          page.strokes,
        )) {
          page.strokes.remove(stroke);
        }
      }
      page.redrawStrokes();
      removeExcessPages();
    } else if (currentTool is Select) {
      final select = currentTool as Select;
      if (select.doneSelecting) {
        // Between -1 and 1
        int pageOffset = 0;
        if (position.dy > page.size.height + changePageThreshold) {
          // Selection is dragged past the bottom of the original page
          if (coreInfo.pages.length > select.selectResult.pageIndex + 1) {
            offset = Offset(
              offset.dx,
              offset.dy - (page.size.height + changePageThreshold),
            );
            pageOffset = 1;
          }
        } else if (position.dy < -changePageThreshold) {
          // Selection is dragged past the top of the original page
          if (select.selectResult.pageIndex > 0) {
            offset = Offset(
              offset.dx,
              offset.dy + (page.size.height + changePageThreshold),
            );
            pageOffset = -1;
          }
        }
        for (final stroke in select.selectResult.strokes) {
          stroke.shift(offset);
        }
        for (final image in select.selectResult.images) {
          image.dstRect = image.dstRect.shift(offset);
        }
        select.selectResult.path = select.selectResult.path.shift(offset);

        if (pageOffset != 0) {
          offset = position - previousPosition;
          selectionOffsetPage(select, pageOffset);
          dragPageIndex = onWhichPageIsFocalPoint(details.focalPoint);

          if (dragPageIndex == null) {
            return;
          }
          final pageNew = coreInfo.pages[dragPageIndex!];
          // Recalculate position according new drag page
          position = pageNew.renderBox!.globalToLocal(details.focalPoint);
          // Recalculate the offset as if the selection were always moving to one page. Important for undo/redo
          offset = Offset(
            offset.dx,
            offset.dy - pageOffset * (page.size.height + changePageThreshold),
          );
          pageNew.redrawStrokes();
        }
      } else {
        select.onDragUpdate(position);
      }
      page.redrawStrokes();
    } else if (currentTool is LaserPointer) {
      (currentTool as LaserPointer).onDragUpdate(position);
      page.redrawStrokes();
    }
    previousPosition = position;
    moveOffset += offset;
  }

  bool moveStrokeToPage(Stroke stroke, int pageIndexOrig, int pageIndexDest) {
    if (pageIndexOrig == pageIndexDest ||
        pageIndexOrig == -1 ||
        pageIndexDest == -1) {
      return false;
    }
    if (pageIndexOrig < 0 || pageIndexOrig > coreInfo.pages.length - 1) {
      return false;
    }
    if (pageIndexDest < 0 || pageIndexDest > coreInfo.pages.length - 1) {
      return false;
    }
    final pageOrig = coreInfo.pages[pageIndexOrig];
    final pageDest = coreInfo.pages[pageIndexDest];

    pageOrig.strokes.remove(stroke);
    stroke.pageIndex = pageIndexDest;
    stroke.page = pageDest;
    pageDest.insertStroke(stroke);
    return true;
  }

  bool moveImageToPage(
    EditorImage image,
    int pageIndexOrig,
    int pageIndexDest,
  ) {
    if (pageIndexOrig == pageIndexDest ||
        pageIndexOrig == -1 ||
        pageIndexDest == -1) {
      return false;
    }
    if (pageIndexOrig < 0 || pageIndexOrig > coreInfo.pages.length - 1) {
      return false;
    }
    if (pageIndexDest < 0 || pageIndexDest > coreInfo.pages.length - 1) {
      return false;
    }
    final pageOrig = coreInfo.pages[pageIndexOrig];
    final pageDest = coreInfo.pages[pageIndexDest];

    pageOrig.images.remove(image);
    image.pageIndex = pageIndexDest;
    pageDest.images.add(image);
    return true;
  }

  void selectionOffsetPage(Select select, int pageOffset) {
    final int oldPage = select.selectResult.pageIndex;
    final int newPage = select.selectResult.pageIndex + pageOffset;
    if (oldPage < 0 || oldPage > coreInfo.pages.length - 1) {
      return;
    }
    if (newPage < 0 || newPage > coreInfo.pages.length - 1) {
      return;
    }
    final strokes = select.selectResult.strokes;
    final images = select.selectResult.images;

    setState(() {
      for (final stroke in strokes) {
        moveStrokeToPage(stroke, oldPage, newPage);
      }
      for (final image in images) {
        moveImageToPage(image, oldPage, newPage);
      }
      select.selectResult.pageIndex += pageOffset;
    });
  }

  void onDrawEnd(ScaleEndDetails details) {
    _guideEdge = null;
    if (_placingWritingPad) {
      if (_draggingWritingPad) writingPadController.endMove();
      if (_resizingWritingPad) writingPadController.endResize();
      _placingWritingPad = false;
      _draggingWritingPad = false;
      _resizingWritingPad = false;
      _revealWritingWindow();
      return;
    }
    if (dragPageIndex == null) {
      return;
    }
    final page = coreInfo.pages[dragPageIndex!];
    bool shouldSave = true;
    setState(() {
      if (currentTool is Pen) {
        final newStroke = (currentTool as Pen).onDragEnd();
        if (newStroke == null) return;
        if (newStroke.isEmpty) return;

        if (stows.autoStraightenLines.value &&
            currentTool is! ShapePen &&
            newStroke.isStraightLine()) {
          newStroke.convertToLine();
        }

        createPage(newStroke.pageIndex);
        page.insertStroke(newStroke);
        history.recordChange(HistoricAdd(strokes: [newStroke], images: []));
      } else if (currentTool is Eraser) {
        final partialChange = (currentTool as Eraser).onDragEndPartial();
        final erased = (currentTool as Eraser).onDragEnd();
        if (stylusButtonWasPressed || stows.disableEraserAfterUse.value) {
          // restore previous tool
          stylusButtonWasPressed = false;
          currentTool = _lastNonEraserTool;
        }
        if (partialChange != null) {
          history.recordChange(partialChange);
        } else {
          if (erased.isEmpty) return;
          history.recordChange(HistoricDelete(strokes: erased, images: []));
        }
      } else if (currentTool is Select) {
        if (moveOffset == .zero) return;
        final select = currentTool as Select;
        if (select.doneSelecting) {
          history.recordChange(
            HistoricMove(
              pageIndex: select.selectResult.pageIndex,
              prevPageIndex: select.selectResult.pageIndexStart!,
              strokes: select.selectResult.strokes,
              images: select.selectResult.images,
              offset: .fromLTRB(
                moveOffset.dx,
                moveOffset.dy,
                moveOffset.dx,
                moveOffset.dy,
              ),
            ),
          );
          select.selectResult.pageIndexStart = select.selectResult.pageIndex;
        } else {
          shouldSave = false;
          select.onDragEnd(page.strokes, page.images);

          // Linien und Fotos, die nur teilweise im Lasso liegen, am Rand abschneiden.
          final cuts = select.cutStrokes(List.of(page.strokes));
          final removed = <Stroke>[];
          final added = <Stroke>[];
          for (final (old, inside, outside) in cuts) {
            page.strokes.remove(old);
            removed.add(old);
            for (final piece in [...inside, ...outside]) {
              page.insertStroke(piece);
              added.add(piece);
            }
          }
          final removedImages = <EditorImage>[];
          final addedImages = <EditorImage>[];
          _cutImages(select, page, removedImages, addedImages);
          if (removed.isNotEmpty || removedImages.isNotEmpty) {
            history.recordChange(
              HistoricReplace(
                removed: removed,
                added: added,
                removedImages: removedImages,
                addedImages: addedImages,
              ),
            );
            shouldSave = true;
          }

          if (select.selectResult.isEmpty) {
            Select.currentSelect.unselect();
          }
        }
      } else if (currentTool is LaserPointer) {
        shouldSave = false;
        final newStroke = (currentTool as LaserPointer).onDragEnd(
          page.redrawStrokes,
          (Stroke stroke) {
            page.laserStrokes.remove(stroke);
          },
        );
        if (newStroke != null) page.laserStrokes.add(newStroke);
      }
    });

    if (shouldSave) autosaveAfterDelay();
  }

  void onInteractionEnd(ScaleEndDetails details) {
    // reset after 1ms to keep track of the same gesture only
    _lastSeenPointerCountTimer?.cancel();
    _lastSeenPointerCountTimer = Timer(const Duration(milliseconds: 10), () {
      lastSeenPointerCount = 0;
    });
  }

  void updatePointerData(PointerDeviceKind kind, double? pressure) {
    currentPointerKind = kind;
    currentPressure = pressure;
  }

  void onHovering() {
    isHovering = true;
  }

  void onHoveringEnd() {
    isHovering = false;
  }

  void onStylusButtonChanged(bool buttonIsPressed) {
    stylusButtonWasPressed |= buttonIsPressed;

    if (!isHovering) return;
    if (buttonIsPressed) {
      // button pressed while hovering, switch to Eraser
      if (currentTool is! Eraser) {
        currentTool = Eraser();
      }
    } else {
      // button was released while hovering, switch back to non-Eraser
      if (currentTool is Eraser) {
        currentTool = _lastNonEraserTool;
      }
    }

    if (mounted) setState(() {});
  }

  void onMoveImage(EditorImage image, Rect offset) {
    history.recordChange(
      HistoricMove(
        pageIndex: image.pageIndex,
        prevPageIndex: image.pageIndex,
        strokes: [],
        images: [image],
        offset: offset,
      ),
    );
    // setState to update undo button
    setState(() {});
    autosaveAfterDelay();
  }

  void onDeleteImage(EditorImage image) {
    history.recordChange(HistoricDelete(strokes: [], images: [image]));
    setState(() {
      coreInfo.pages[image.pageIndex].images.remove(image);
    });
    autosaveAfterDelay();
  }

  void listenToQuillChanges(QuillStruct quill, int pageIndex) {
    quill.changeSubscription?.cancel();
    quill.changeSubscription = quill.controller.changes.listen((event) {
      final undoRedoButtonsNeedUpdating = !history.canUndo || history.canRedo;
      _addQuillChangeToHistory(
        quill: quill,
        pageIndex: pageIndex,
        event: event,
      );
      createPage(pageIndex); // create empty last page
      if (undoRedoButtonsNeedUpdating) {
        setState(() {});
      }
      autosaveAfterDelay();
    });
    quill.focusNode.addListener(_onQuillFocusChange);
  }

  void _onQuillFocusChange() {
    for (final page in coreInfo.pages) {
      if (!page.quill.focusNode.hasFocus) continue;
      quillFocus.value = page.quill;
    }
  }

  void _addQuillChangeToHistory({
    required QuillStruct quill,
    required int pageIndex,
    required flutter_quill.DocChange event,
  }) {
    final eventWasUndo = quill.controller.hasRedo;
    if (eventWasUndo) return;

    // the change subscription sometimes fires multiple times for the same change
    // so compare the "before" of each change to merge them
    if (history.canUndo && !history.canRedo) {
      final lastChange = history.peekUndo();
      if (lastChange is HistoricQuillChange &&
          lastChange.pageIndex == pageIndex &&
          lastChange.quillChange.before == event.before) {
        // Remove the last change, to be replaced.
        // This only pops it from the list; [this.undo] is not called.
        history.undo();
      }
    }

    history.recordChange(
      HistoricQuillChange(pageIndex: pageIndex, quillChange: event),
    );
  }

  void _refreshCurrentNote() async {
    if (coreInfo.readOnlyReason != .watchingServer) return;
    if (!stows.loggedIn) return;

    final relativeFilePath = coreInfo.filePath;
    assert(relativeFilePath.isNotEmpty, 'Cannot refresh unnamed file');
    final syncFile = await SaberSyncFile.relative(
      relativeFilePath + Editor.extension,
    );

    final bestFile = await SaberSyncInterface.getBestFile(
      syncFile,
      onLocalFileNotFound: .local,
      onEqualFiles: .local,
      preferCache: false,
    );
    if (bestFile != .remote) return;

    late final StreamSubscription<SaberSyncFile> subscription;
    void listener(SaberSyncFile transferred) {
      if (transferred != syncFile) return;
      subscription.cancel();
      _loadCoreInfo(relativeFilePath)
          .then((_) => coreInfo.readOnlyReason = .watchingServer);
    }

    subscription = syncer.downloader.transferStream.listen(listener);

    await syncer.downloader.enqueue(syncFile: syncFile);
    syncer.downloader.bringToFront(syncFile);
  }

  void autosaveAfterDelay() {
    if (history.isCurrentStateSaved) return cancelAutosaveAndMarkSaved();

    late final void Function() callback;

    void startTimer() {
      _delayedSaveTimer?.cancel();
      if (stows.autosaveDelay.value < 0) return;
      _delayedSaveTimer = Timer(
        Duration(milliseconds: stows.autosaveDelay.value),
        callback,
      );
    }

    callback = () {
      if (Pen.currentStroke != null) {
        // don't save yet if the pen is currently drawing
        startTimer();
        return;
      }
      saveToFile();
    };

    savingState.value = .waitingToSave;
    startTimer();
  }

  void cancelAutosaveAndMarkSaved() {
    _delayedSaveTimer?.cancel();
    savingState.value = .saved;
    history.markLastChangeAsSaved();
  }

  Future<void> saveToFile() async {
    if (coreInfo.readOnly) return;

    switch (savingState.value) {
      case .saved:
        // avoid saving if nothing has changed
        return;
      case .saving:
        // avoid saving if already saving
        log.warning('saveToFile() called while already saving');
        return;
      case .waitingToSave:
        // continue
        _delayedSaveTimer?.cancel();
        savingState.value = .saving;
    }
    if (history.isCurrentStateSaved) return cancelAutosaveAndMarkSaved();

    await _renameFileNow();

    final filePath = coreInfo.filePath + Editor.extension;
    // Fotos, die noch auf eine Datei zeigen, werden vor dem Speichern in den
    // Arbeitsspeicher geholt. Sonst koennen sich die Dateinummern beim
    // Speichern verschieben und ein Foto zeigt auf das Bild eines anderen.
    for (final page in coreInfo.pages) {
      for (final image in page.images) {
        if (image is PngEditorImage && image.imageProvider is FileImage) {
          final file = (image.imageProvider as FileImage).file;
          try {
            image.imageProvider = MemoryImage(await FileManager.readBytes(file));
            image.notifyListeners();
          } catch (e, st) {
            log.severe('Foto konnte nicht eingelesen werden: $e', e, st);
          }
        }
      }
    }
    final Uint8List bson;
    final OrderedAssetCache assets;
    coreInfo.assetCache.allowRemovingAssets = false;
    try {
      (bson, assets) = coreInfo.saveToBinary(
        currentPageIndex: currentPageIndex,
      );
    } finally {
      coreInfo.assetCache.allowRemovingAssets = true;
    }
    try {
      // Erst alles lesen, dann schreiben (sonst werden Dateien ueberschrieben,
      // die noch gelesen werden muessen).
      final assetBytes = [
        for (int i = 0; i < assets.length; ++i) await assets.getBytes(i),
      ];
      await Future.wait([
        FileManager.writeFile(filePath, bson, awaitWrite: true),
        for (int i = 0; i < assetBytes.length; ++i)
          FileManager.writeFile('$filePath.$i', assetBytes[i], awaitWrite: true),
        FileManager.removeUnusedAssets(filePath, numAssets: assets.length),
      ]);
      savingState.value = .saved;
      history.markLastChangeAsSaved();
    } catch (e, st) {
      log.severe('Failed to save file: $e', e, st);
      savingState.value = .waitingToSave;
      if (kDebugMode) rethrow;
      return;
    }

    if (!mounted) return;
    final page = coreInfo.pages.first;
    final previewHeight = page.previewHeight(lineHeight: coreInfo.lineHeight);
    final thumbnailSize = Size(720, 720 * previewHeight / page.size.width);
    final thumbnail = await EditorExporter.screenshotPage(
      coreInfo: coreInfo,
      pageIndex: 0,
      rasterizeAllStrokes: true,
      targetSize: thumbnailSize,
      cropHeight: previewHeight,
      pixelRatio: 1,
    );
    final thumbnailPng = await thumbnail.toByteData(format: .png);
    thumbnail.dispose();
    if (coreInfo.filePath == QuickNote.path) {
      unawaited(
        QuickNote.updatePreview(thumbnailPng!.buffer.asUint8List()),
      );
    }
    await FileManager.writeFile(
      // Note that this ends with .sbn2.p
      '$filePath.p',
      thumbnailPng!.buffer.asUint8List(),
      awaitWrite: true,
    );
  }

  late final _filenameFormKey = GlobalKey<FormState>();
  late final filenameTextEditingController = TextEditingController();
  Timer? _renameTimer;
  void renameFile([String? _]) {
    _renameTimer?.cancel();
    _renameTimer = Timer(const Duration(seconds: 5), _renameFileNow);
  }

  Future<void> _renameFileNow() async {
    final newName = filenameTextEditingController.text.trim();
    if (newName == coreInfo.fileName) return;

    if (_filenameFormKey.currentState?.validate() ??
        _validateFilenameTextField(newName) == null) {
      coreInfo.filePath = await FileManager.moveFile(
        coreInfo.filePath + Editor.extension,
        newName.trim() + Editor.extension,
      );
      coreInfo.filePath = coreInfo.filePath.substring(
        0,
        coreInfo.filePath.lastIndexOf(Editor.extension),
      );
      needsNaming = false;
    }

    final actualName = coreInfo.fileName;
    if (actualName != newName) {
      // update text field if renamed differently
      filenameTextEditingController.value = filenameTextEditingController.value
          .copyWith(
            text: actualName,
            selection: TextSelection.fromPosition(
              TextPosition(offset: actualName.length),
            ),
            composing: TextRange.empty,
          );
    }
  }

  String? _validateFilenameTextField(String? newName) {
    if (newName == null) return null;
    return FileManager.validateFilename(newName);
  }

  void updateColorBar(Color color) {
    if (stows.recentColorsDontSavePresets.value) {
      if (ColorBar.colorPresets.any(
        (colorPreset) => colorPreset.color == color,
      )) {
        return;
      }
    }

    final newColorString = color.toARGB32().toString();

    // migrate from old pref format
    if (stows.recentColorsChronological.value.length !=
        stows.recentColorsPositioned.value.length) {
      log.info(
        'MIGRATING recentColors: ${stows.recentColorsChronological.value.length} vs ${stows.recentColorsPositioned.value.length}',
      );
      stows.recentColorsChronological.value = List.of(
        stows.recentColorsPositioned.value,
      );
    }

    if (stows.pinnedColors.value.contains(newColorString)) {
      // do nothing, color is already pinned
    } else if (stows.recentColorsPositioned.value.contains(newColorString)) {
      // if it's already a recent color, move it to the top
      stows.recentColorsChronological.value.remove(newColorString);
      stows.recentColorsChronological.value.add(newColorString);
      stows.recentColorsChronological.notifyListeners();
    } else {
      if (stows.recentColorsPositioned.value.length >=
          stows.recentColorsLength.value) {
        // if full, replace the oldest color with the new one
        final removedColorString = stows.recentColorsChronological.value
            .removeAt(0);
        stows.recentColorsChronological.value.add(newColorString);
        final int removedColorPosition = stows.recentColorsPositioned.value
            .indexOf(removedColorString);
        stows.recentColorsPositioned.value[removedColorPosition] =
            newColorString;
      } else {
        // if not full, add the new color to the end
        stows.recentColorsChronological.value.add(newColorString);
        stows.recentColorsPositioned.value.insert(0, newColorString);
      }
      stows.recentColorsChronological.notifyListeners();
      stows.recentColorsPositioned.notifyListeners();
    }
  }

  /// Feder: Jeder Stift merkt sich seine zuletzt benutzte Farbe.
  void _savePenColor(Pen pen) {
    try {
      final map = Map<String, dynamic>.from(
        jsonDecode(stows.penColors.value) as Map,
      );
      map[pen.name] = pen.color.toARGB32();
      stows.penColors.value = jsonEncode(map);
    } catch (_) {}
  }

  void _restorePenColor(Tool tool) {
    if (tool is! Pen || tool is Highlighter || tool is TapePen) return;
    try {
      final map = jsonDecode(stows.penColors.value) as Map;
      final saved = map[tool.name];
      if (saved is int) tool.color = Color(saved);
    } catch (_) {}
  }

  /// Feder: Handschrift der Lasso-Auswahl erkennen und als Aufgabe, Termin
  /// oder Kontakt an Nextcloud senden (Erkennung auf dem Gerät, Bestätigungsfenster).
  Future<void> _sendSelectionToNextcloud(NcKind kind) async {
    final select = currentTool;
    if (select is! Select || !select.doneSelecting) return;
    final messenger = ScaffoldMessenger.of(context);
    final strokes = [...select.selectResult.strokes];
    if (strokes.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Im Lasso ist keine Handschrift.')),
      );
      return;
    }
    final notReady = NextcloudDav.notReadyReason();
    if (notReady != null) {
      messenger.showSnackBar(SnackBar(content: Text(notReady)));
      return;
    }

    messenger.showSnackBar(
      const SnackBar(
        content: Text('Handschrift wird gelesen …'),
        duration: Duration(seconds: 20),
      ),
    );
    var candidates = <String>[];
    String? problem;
    try {
      candidates = await InkRecognition.recognize(strokes);
      if (candidates.isEmpty) {
        problem = 'Es wurde kein Text erkannt. Bitte selbst eintippen.';
      }
    } catch (e) {
      problem = 'Erkennung nicht möglich: $e';
    }
    messenger.hideCurrentSnackBar();
    if (!mounted) return;

    final created = await showSendToNextcloudDialog(
      context,
      kind: kind,
      candidates: candidates,
      problem: problem,
    );
    if (created == true) {
      messenger.showSnackBar(
        SnackBar(content: Text('${kind.label} in Nextcloud angelegt.')),
      );
    }
  }

  /// Feder: Handschrift der Lasso-Auswahl als Matheaufgabe lesen und lösen
  /// (Erkennung und Rechnen auf dem Gerät).
  Future<void> _solveMathFromSelection() async {
    final select = currentTool;
    if (select is! Select || !select.doneSelecting) return;
    final messenger = ScaffoldMessenger.of(context);
    final strokes = [...select.selectResult.strokes];
    if (strokes.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Im Lasso ist keine Handschrift.')),
      );
      return;
    }
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Handschrift wird gelesen …'),
        duration: Duration(seconds: 20),
      ),
    );
    var candidates = <String>[];
    String? problem;
    try {
      candidates = await InkRecognition.recognize(strokes);
      if (candidates.isEmpty) {
        problem = 'Es wurde nichts erkannt. Bitte selbst eintippen.';
      }
    } catch (e) {
      problem = 'Erkennung nicht möglich: $e';
    }
    messenger.hideCurrentSnackBar();
    if (!mounted) return;

    // Lage der Handschrift merken, bevor sich die Auswahl ändert.
    final pageIndex = select.selectResult.pageIndex;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final stroke in strokes) {
      for (final p in stroke.points) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
    }
    final color = strokes.first.color;

    final text = await showMathSolveDialog(
      context,
      candidates: candidates,
      problem: problem,
    );
    if (text == null || !mounted) return;
    if (!minX.isFinite || pageIndex < 0 || pageIndex >= coreInfo.pages.length) {
      return;
    }
    await _writeHandwrittenResult(
      text,
      color,
      Rect.fromLTRB(minX, minY, maxX, maxY),
      pageIndex,
    );
  }

  /// Feder: Ergebnis in Handschrift-Optik rechts hinter die Aufgabe setzen
  /// (passt nichts mehr daneben, dann darunter).
  Future<void> _writeHandwrittenResult(
    String text,
    Color color,
    Rect task,
    int pageIndex,
  ) async {
    if (coreInfo.readOnly) return;
    final fontSize = (task.height * 0.9).clamp(28.0, 110.0).toDouble();
    final img = await renderHandwriting(text, color, fontSize);
    if (!mounted) return;

    final page = coreInfo.pages[pageIndex];
    final gap = fontSize * 0.4;
    var left = task.right + gap;
    var top = task.center.dy - img.size.height / 2;
    if (page.size.isFinite && left + img.size.width > page.size.width) {
      left = task.left;
      top = task.bottom + gap;
    }
    if (page.size.isFinite) {
      left = left.clamp(0, math.max(0, page.size.width - img.size.width)).toDouble();
      top = top.clamp(0, math.max(0, page.size.height - img.size.height)).toDouble();
    }

    final image = PngEditorImage(
      id: coreInfo.nextImageId++,
      extension: '.png',
      imageProvider: MemoryImage(img.bytes),
      pageIndex: pageIndex,
      pageSize: page.size,
      onMoveImage: onMoveImage,
      onDeleteImage: onDeleteImage,
      onMiscChange: autosaveAfterDelay,
      onLoad: () => setState(() {}),
      assetCache: coreInfo.assetCache,
      dstRect: Rect.fromLTWH(left, top, img.size.width, img.size.height),
    );
    history.recordChange(HistoricAdd(strokes: const [], images: [image]));
    setState(() {
      createPage(pageIndex);
      coreInfo.pages[pageIndex].images.add(image);
    });
    autosaveAfterDelay();
  }

  /// Feder: Text-Stempel als Bild in die Bildmitte legen.
  Future<void> _placeTextStamp(String text, Color color) async {
    final bytes = await renderTextStamp(text, color);
    // Dialog erst ganz schließen lassen, sonst deaktiviert dessen
    // Abschlussgeste den neuen Rahmen sofort wieder.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    _lastPickedImages = const [];
    await _pickPhotos([_PhotoInfo(bytes, '.png')]);
    for (final image in _lastPickedImages) {
      image.stamp = true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    for (final image in _lastPickedImages) {
      image.reactivate = true;
      image.notifyListenersPlease();
    }
  }

  List<EditorImage> _lastPickedImages = const [];

  /// Prompts the user to pick photos from their device.
  /// Returns the number of photos picked.
  ///
  /// If [photoInfos] is provided, it will be used instead of the file picker.
  Future<int> _pickPhotos([List<_PhotoInfo>? photoInfos]) async {
    if (coreInfo.readOnly) return 0;

    photoInfos ??= await _pickPhotosFromChosenSource();
    if (photoInfos.isEmpty) return 0;

    // Neue Bilder erscheinen in der Mitte des sichtbaren Bereichs.
    final (currentPageIndex, visibleCenter) = _visibleTarget();
    var staggerCount = 0;

    /// Some Android platforms allow selecting a pdf here.
    /// Tell user to use the Import PDF function instead.
    var triedToPickPdf = false;

    final images = <EditorImage>[];
    for (final _PhotoInfo photoInfo in photoInfos) {
      if (photoInfo.extension.toLowerCase() == '.pdf') {
        triedToPickPdf = true;
        continue;
      } else if (photoInfo.extension.toLowerCase() == '.svg') {
        images.add(
          SvgEditorImage(
            id: coreInfo.nextImageId++,
            svgString: utf8.decode(photoInfo.bytes),
            svgFile: null,
            pageIndex: currentPageIndex,
            pageSize: coreInfo.pages[currentPageIndex].size,
            onMoveImage: onMoveImage,
            onDeleteImage: onDeleteImage,
            onMiscChange: autosaveAfterDelay,
            onLoad: () => setState(() {}),
            assetCache: coreInfo.assetCache,
          )..centerHint = visibleCenter + Offset(24.0, 24.0) * (staggerCount++).toDouble(),
        );
      } else {
        images.add(
          PngEditorImage(
            id: coreInfo.nextImageId++,
            extension: photoInfo.extension,
            imageProvider: MemoryImage(photoInfo.bytes),
            pageIndex: currentPageIndex,
            pageSize: coreInfo.pages[currentPageIndex].size,
            onMoveImage: onMoveImage,
            onDeleteImage: onDeleteImage,
            onMiscChange: autosaveAfterDelay,
            onLoad: () => setState(() {}),
            assetCache: coreInfo.assetCache,
          )..centerHint = visibleCenter + Offset(24.0, 24.0) * (staggerCount++).toDouble(),
        );
      }
    }

    _lastPickedImages = images;
    if (images.isNotEmpty) {
      // use the Select tool so that the user can move the new image
      currentTool = Select.currentSelect;

      history.recordChange(HistoricAdd(strokes: const [], images: images));
      setState(() {
        createPage(currentPageIndex);
        coreInfo.pages[currentPageIndex].images.addAll(images);
      });
      autosaveAfterDelay();
    }

    if (triedToPickPdf && mounted) {
      await showDialog(
        context: context,
        builder: (context) => AdaptiveAlertDialog(
          title: Text(t.editor.photoPdfError.title),
          content: Text(t.editor.photoPdfError.message),
          actions: [
            CupertinoDialogAction(
              child: Text(t.common.done),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }

    return images.length;
  }

  /// Schneidet Fotos am Lassorand: ganz innen = ausgewählt, teilweise =
  /// in zwei Fotos geteilt (innen ausgewählt, außen bleibt), außen = unberührt.
  void _cutImages(
    Select select,
    EditorPage page,
    List<EditorImage> removedImages,
    List<EditorImage> addedImages,
  ) {
    final path = select.selectResult.path;
    final lasso = select.lassoPoints;
    if (lasso.length < 3) return;
    for (final image in List.of(page.images)) {
      final rect = image.dstRect;
      if (rect.isEmpty) continue;
      // Anteil der Abtastpunkte des Fotos, die im Lasso liegen.
      const n = 14;
      var inside = 0;
      for (int ix = 0; ix < n; ix++) {
        for (int iy = 0; iy < n; iy++) {
          final p = Offset(
            rect.left + rect.width * (ix + 0.5) / n,
            rect.top + rect.height * (iy + 0.5) / n,
          );
          if (path.contains(p)) inside++;
        }
      }
      if (inside == 0) continue;
      if (inside == n * n) {
        select.selectResult.images.add(image);
        continue;
      }
      // Das ganze (ungeschnittene) Foto in Seitenkoordinaten.
      final fullW = rect.width / image.crop.width;
      final fullH = rect.height / image.crop.height;
      final fullLeft = rect.left - image.crop.left * fullW;
      final fullTop = rect.top - image.crop.top * fullH;
      final fractions = [
        for (final p in lasso)
          Offset((p.dx - fullLeft) / fullW, (p.dy - fullTop) / fullH),
      ];
      EditorImage? piece(bool isInside) {
        final layers = [
          ...image.clip,
          ImageClip(inside: isInside, points: fractions),
        ];
        final visible = ImageClip.pathFor(layers, Size(fullW, fullH)).getBounds();
        final cropNew = Rect.fromLTRB(
          visible.left / fullW,
          visible.top / fullH,
          visible.right / fullW,
          visible.bottom / fullH,
        ).intersect(image.crop);
        if (cropNew.isEmpty || cropNew.width < 0.005 || cropNew.height < 0.005) {
          return null;
        }
        return image.clone()
          ..id = coreInfo.nextImageId++
          ..newImage = false
          ..clip = layers
          ..crop = cropNew
          ..dstRect = Rect.fromLTWH(
            fullLeft + cropNew.left * fullW,
            fullTop + cropNew.top * fullH,
            cropNew.width * fullW,
            cropNew.height * fullH,
          );
      }

      final inner = piece(true);
      final outer = piece(false);
      page.images.remove(image);
      final pieces = [?outer, ?inner];
      page.images.addAll(pieces);
      removedImages.add(image);
      addedImages.addAll(pieces);
      if (inner != null) select.selectResult.images.add(inner);
    }
  }

  /// Seite und Mitte (Seitenkoordinaten) des gerade sichtbaren Bereichs.
  (int, Offset) _visibleTarget() {
    final size = MediaQuery.sizeOf(context);
    final screenCenter = Offset(size.width / 2, size.height / 2);
    final index = (onWhichPageIsFocalPoint(screenCenter) ?? currentPageIndex)
        .clamp(0, coreInfo.pages.length - 1);
    final page = coreInfo.pages[index];
    final box = page.renderBox;
    var local = box != null
        ? box.globalToLocal(screenCenter)
        : Offset(page.size.width / 2, page.size.height / 2);
    local = Offset(
      local.dx.clamp(0, page.size.width).toDouble(),
      local.dy.clamp(0, page.size.height).toDouble(),
    );
    return (index, local);
  }

  /// Fragt, woher die Fotos kommen sollen.
  Future<List<_PhotoInfo>> _pickPhotosFromChosenSource() async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Foto einfügen aus …')),
            for (final s in PhotoSource.values)
              ListTile(
                leading: Icon(switch (s) {
                  PhotoSource.gallery => Icons.photo_library,
                  PhotoSource.camera => Icons.photo_camera,
                  PhotoSource.googlePhotos => Icons.cloud,
                  PhotoSource.ente => Icons.lock,
                  PhotoSource.files => Icons.folder_open,
                }),
                title: Text(s.label),
                onTap: () => Navigator.of(context).pop(s),
              ),
          ],
        ),
      ),
    );
    if (source == null) return const [];
    if (source == PhotoSource.files) return _pickPhotosWithFilePicker();

    if (!stows.maxImageSize.loaded) await stows.maxImageSize.waitUntilRead();
    try {
      final picked = await PhotoSources.pick(
        source,
        maxSize: stows.maxImageSize.value.round(),
      );
      return [for (final p in picked) _PhotoInfo(p.bytes, p.extension)];
    } on PhotoSourceUnavailable {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${source.label} ist nicht installiert oder bietet keine '
              'Bildauswahl für andere Apps an. Nimm "Galerie (System)" oder '
              '"Dateien durchsuchen".',
            ),
          ),
        );
      }
      return const [];
    }
  }

  // ---- Foto auf andere Seite: Loslassen und Ziel antippen ----

  /// Wird nach dem Ziehen eines Fotos aufgerufen. Liegt die Mitte des Fotos
  /// auf einer anderen Seite, wechselt es dorthin.
  bool _onDropImage(EditorImage image, Rect startRect) {
    final from = image.pageIndex;
    if (from < 0 || from >= coreInfo.pages.length) return false;
    final fromBox = coreInfo.pages[from].renderBox;
    if (fromBox == null) return false;
    final globalCenter = fromBox.localToGlobal(image.dstRect.center);
    final to = onWhichPageIsFocalPoint(globalCenter);
    if (to == null || to == from) {
      // Ins Leere gezogen: zurück an den Rand der eigenen Seite.
      final size = coreInfo.pages[from].size;
      final r = image.dstRect;
      final fixed = Rect.fromLTWH(
        r.left.clamp(0, math.max(0, size.width - r.width)).toDouble(),
        r.top.clamp(0, math.max(0, size.height - r.height)).toDouble(),
        r.width,
        r.height,
      );
      if (fixed != r) {
        image.dstRect = fixed;
        onMoveImage(
          image,
          Rect.fromLTRB(
            fixed.left - startRect.left,
            fixed.top - startRect.top,
            fixed.right - startRect.right,
            fixed.bottom - startRect.bottom,
          ),
        );
        return true;
      }
      return false;
    }
    final toBox = coreInfo.pages[to].renderBox;
    if (toBox == null) return false;
    final newTopLeft = toBox.globalToLocal(
      fromBox.localToGlobal(image.dstRect.topLeft),
    );
    _transferImage(image, from, to, startRect, newTopLeft);
    return true;
  }

  void _transferImage(
    EditorImage image,
    int from,
    int to,
    Rect startRect,
    Offset newTopLeft,
  ) {
    final size = coreInfo.pages[to].size;
    final w = image.dstRect.width;
    final h = image.dstRect.height;
    final left = newTopLeft.dx.clamp(0, math.max(0, size.width - w)).toDouble();
    final top = newTopLeft.dy.clamp(0, math.max(0, size.height - h)).toDouble();
    setState(() {
      moveImageToPage(image, from, to);
      image.dstRect = Rect.fromLTWH(left, top, w, h);
    });
    final dx = left - startRect.left;
    final dy = top - startRect.top;
    history.recordChange(
      HistoricMove(
        pageIndex: to,
        prevPageIndex: from,
        strokes: const [],
        images: [image],
        offset: Rect.fromLTRB(dx, dy, dx, dy),
      ),
    );
    autosaveAfterDelay();
  }

  EditorImage? _targetImage;
  Offset? _targetDownPosition;
  int? _targetDownTime;

  void _startImageTarget(EditorImage image) {
    _targetImage = image;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(days: 1),
        content: const Text('Tippe auf die Stelle, an der das Foto stehen soll.'),
        action: SnackBarAction(label: 'Abbrechen', onPressed: _cancelImageTarget),
      ),
    );
  }

  void _cancelImageTarget() {
    _targetImage = null;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  }

  void _targetPointerDown(PointerDownEvent e) {
    if (_targetImage == null) return;
    _targetDownPosition = e.position;
    _targetDownTime = DateTime.now().millisecondsSinceEpoch;
  }

  void _targetPointerUp(PointerUpEvent e) {
    final image = _targetImage;
    final down = _targetDownPosition;
    final time = _targetDownTime;
    _targetDownPosition = null;
    _targetDownTime = null;
    if (image == null || down == null || time == null) return;
    // nur ein kurzer Tipp zählt, kein Wischen
    if ((e.position - down).distance > 24) return;
    if (DateTime.now().millisecondsSinceEpoch - time > 700) return;
    final to = onWhichPageIsFocalPoint(e.position);
    if (to == null) return;
    final from = image.pageIndex;
    final box = coreInfo.pages[to].renderBox;
    if (box == null) return;
    final local = box.globalToLocal(e.position);
    final start = image.dstRect;
    final newTopLeft = Offset(
      local.dx - start.width / 2,
      local.dy - start.height / 2,
    );
    _cancelImageTarget();
    if (to == from) {
      final size = coreInfo.pages[to].size;
      final left = newTopLeft.dx
          .clamp(0, math.max(0, size.width - start.width))
          .toDouble();
      final top = newTopLeft.dy
          .clamp(0, math.max(0, size.height - start.height))
          .toDouble();
      setState(() {
        image.dstRect = Rect.fromLTWH(left, top, start.width, start.height);
      });
      onMoveImage(
        image,
        Rect.fromLTRB(
          left - start.left,
          top - start.top,
          left + start.width - start.right,
          top + start.height - start.bottom,
        ),
      );
    } else {
      _transferImage(image, from, to, start, newTopLeft);
    }
  }

  Future<List<_PhotoInfo>> _pickPhotosWithFilePicker() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.custom,
      // Taken from
      // https://github.com/brendan-duncan/image/blob/main/doc/formats.md
      // (plus .svg)
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'tiff',
        'bmp',
        'tga',
        'ico',
        'pvrtc',
        'svg',
        'webp',
        'psd',
        'exr',
      ],
    );
    if (files.isEmpty) return const [];

    return Future.wait([
      for (final file in files)
        () async {
          final extension = p.extension(file.path ?? file.name);
          if (extension.isEmpty) return null;
          final bytes = await file.readAsBytes();
          return _PhotoInfo(bytes, extension);
        }(),
    ]).then((list) => list.nonNulls.toList());
  }

  /// Prompts the user to pick a PDF to import.
  /// Returns whether a PDF was picked.
  Future<bool> importPdf() async {
    if (coreInfo.readOnly) return false;
    if (!Editor.canRasterPdf) return false;

    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null) return false;

    return importPdfFromFilePath(file.path!);
  }

  Future<bool> importPdfFromFilePath(String path) async {
    final pdfDocument = await coreInfo.assetCache.pdfDocumentCache.load(path);

    final emptyPage = coreInfo.pages.removeLast();
    assert(emptyPage.isEmpty);

    for (final pdfPage in pdfDocument.pages) {
      assert(pdfPage.pageNumber >= 1, 'pdfrx page numbers start at 1');

      // resize to [defaultWidth] to keep pen sizes consistent
      final pageSize = Size(
        EditorPage.defaultWidth,
        EditorPage.defaultWidth * pdfPage.height / pdfPage.width,
      );

      final page = EditorPage(
        size: pageSize,
        backgroundImage: PdfEditorImage(
          id: coreInfo.nextImageId++,
          pdfBytes: null,
          pdfFile: File(path),
          pdfPage: pdfPage.pageNumber - 1,
          pageIndex: coreInfo.pages.length,
          pageSize: pageSize,
          naturalSize: pdfPage.size,
          onMoveImage: onMoveImage,
          onDeleteImage: onDeleteImage,
          onMiscChange: autosaveAfterDelay,
          onLoad: () => setState(() {}),
          assetCache: coreInfo.assetCache,
        ),
      );
      coreInfo.pages.add(page);
      // TODO(adil192): Group multiple pages into one atomic change
      history.recordChange(
        HistoricPageInsert(pageIndex: coreInfo.pages.length - 1, page: page),
      );
    }

    coreInfo.pages.add(emptyPage);
    if (mounted) setState(() {});

    autosaveAfterDelay();

    return true;
  }

  Future paste() async {
    /// Maps image formats to their file extension.
    const Map<SimpleFileFormat, String> formats = {
      Formats.jpeg: '.jpeg',
      Formats.png: '.png',
      Formats.gif: '.gif',
      Formats.tiff: '.tiff',
      Formats.bmp: '.bmp',
      Formats.ico: '.ico',
      Formats.svg: '.svg',
      Formats.webp: '.webp',
    };

    final reader = await SystemClipboard.instance?.read();
    if (reader == null) return;

    final List<_PhotoInfo> photoInfos = [];
    final List<ReadProgress> progresses = [];

    for (final format in formats.keys) {
      if (!reader.canProvide(format)) continue;
      final progress = reader.getFile(format, (file) async {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in file.getStream()) {
          builder.add(chunk);
        }

        final bytes = builder.takeBytes();
        if (bytes.isEmpty) {
          log.warning('Pasted empty file: $file (${formats[format]})');
          return;
        }

        final String extension;
        if (file.fileName != null) {
          extension = file.fileName!.substring(file.fileName!.lastIndexOf('.'));
        } else {
          extension = formats[format]!;
        }

        photoInfos.add(_PhotoInfo(bytes, extension));
      });
      if (progress != null) progresses.add(progress);
    }

    while (progresses.isNotEmpty) {
      progresses.removeWhere((progress) => progress.fraction.value == 1);
      await Future.delayed(const Duration(milliseconds: 50));
    }

    await _pickPhotos(photoInfos);
  }

  Future exportAsPdf(BuildContext context) async {
    final pdf = await EditorExporter.generatePdf(coreInfo, context);
    final bytes = await pdf.save();
    if (!context.mounted) return;
    await FileManager.exportFile(
      '${coreInfo.fileName}.pdf',
      bytes,
      context: context,
    );
  }

  /// Exports the current note as an SBA (Saber Archive) file.
  Future exportAsSba(BuildContext context) async {
    final sba = await coreInfo.saveToSba(currentPageIndex: currentPageIndex);
    if (!context.mounted) return;
    await FileManager.exportFile(
      '${coreInfo.fileName}.sba',
      Uint8List.fromList(sba),
      context: context,
    );
  }

  /// Exports the current page as a PNG image file.
  ///
  /// This captures the canvas natively via [EditorExporter.screenshotPage],
  /// which guarantees the correct background color and omits UI elements
  /// like selection bounds or the text cursor. It computes a dynamic [pixelRatio]
  /// to ensure high quality while averting Out-Of-Memory exceptions on large canvases.
  Future exportAsPng(BuildContext context) async {
    final page = coreInfo.pages[currentPageIndex];

    const maxRasterizableSize = 3000.0;
    var targetPixelRatio = maxRasterizableSize / page.size.longestSide;
    if (targetPixelRatio > 1) targetPixelRatio = 1;

    try {
      final image = await EditorExporter.screenshotPage(
        coreInfo: coreInfo,
        pageIndex: currentPageIndex,
        rasterizeAllStrokes: true,
        pixelRatio: targetPixelRatio,
      );
      final pngBytes = await image.toByteData(format: .png);
      image.dispose();

      if (!context.mounted) return;
      await FileManager.exportFile(
        '${coreInfo.fileName}_page_${currentPageIndex + 1}.png',
        pngBytes!.buffer.asUint8List(),
        isImage: true,
        context: context,
      );
    } catch (e, st) {
      log.severe('Failed to export PNG', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final platform = Theme.of(context).platform;
    final isToolbarVertical =
        stows.editorToolbarAlignment.value == .left ||
        stows.editorToolbarAlignment.value == .right;

    final Widget canvas = CanvasGestureDetector(
      key: _canvasGestureDetectorKey,
      filePath: coreInfo.filePath,
      isDrawGesture: isDrawGesture,
      onInteractionEnd: onInteractionEnd,
      onDrawStart: onDrawStart,
      onDrawUpdate: onDrawUpdate,
      onDrawEnd: onDrawEnd,
      onHovering: onHovering,
      onHoveringEnd: onHoveringEnd,
      onStylusButtonChanged: onStylusButtonChanged,
      updatePointerData: updatePointerData,
      undo: undo,
      redo: redo,
      pages: coreInfo.pages,
      horizontal: horizontalPaging,
      initialPageIndex: coreInfo.initialPageIndex,
      pageBuilder: pageBuilder,
      isTextEditing: () => currentTool == Tool.textEditing,
      placeholderPageBuilder: (BuildContext context, int pageIndex) {
        return Canvas(
          path: coreInfo.filePath,
          page: coreInfo.pages[pageIndex],
          pageIndex: 0,
          textEditing: false,
          coreInfo: EditorCoreInfo.placeholder,
          currentStroke: null,
          currentStrokeDetectedShape: null,
          currentSelection: null,
          placeholder: true,
          setAsBackground: null,
          currentTool: currentTool,
          currentScale: double.minPositive,
        );
      },
      transformationController: _transformationController,
    );

    final readonlyBanner = ReadOnlyBanner(
      coreInfo.readOnlyReason,
      action: coreInfo.readOnlyReason == .versionTooNew
          ? showVersionTooNewDialog
          : null,
    );

    final Widget toolbar = Collapsible(
      axis: isToolbarVertical ? .horizontal : .vertical,
      collapsed:
          _toolbarHidden ||
          (DynamicMaterialApp.isFullscreen &&
              !stows.editorToolbarShowInFullscreen.value),
      maintainState: true,
      child: SafeArea(
        bottom: stows.editorToolbarAlignment.value != .up,
        child: Toolbar(
          readOnly: coreInfo.readOnly,
          setTool: (tool) {
            if (tool is Eraser && currentTool is Eraser) {
              // setTool(Eraser) is a special case to toggle the eraser on/off
              tool = _lastNonEraserTool;
            }

            _restorePenColor(tool);
            currentTool = tool;

            if (tool is Highlighter) {
              Highlighter.currentHighlighter = tool;
            } else if (tool is TapePen) {
              TapePen.currentTape = tool;
            } else if (tool is Pencil) {
              Pencil.currentPencil = tool;
            } else if (tool is Pen) {
              Pen.currentPen = tool;
            }

            if (mounted) setState(() {});
          },
          currentTool: currentTool,
          sendToNextcloud: _sendSelectionToNextcloud,
          solveMath: _solveMathFromSelection,
          duplicateSelection: () {
            final select = currentTool as Select;
            if (!select.doneSelecting) return;

            setState(() {
              final page = coreInfo.pages[select.selectResult.pageIndex];
              final strokes = select.selectResult.strokes;
              final images = select.selectResult.images;

              const duplicationFeedbackOffset = Offset(25, -25);

              final duplicatedStrokes = strokes.map((stroke) {
                return stroke.copy()..shift(duplicationFeedbackOffset);
              }).toList();

              final duplicatedImages = images.map((image) {
                return image.clone()
                  ..id = coreInfo.nextImageId++
                  ..dstRect.shift(duplicationFeedbackOffset);
              }).toList();

              page.strokes.addAll(duplicatedStrokes);
              page.images.addAll(duplicatedImages);

              select.selectResult = select.selectResult.copyWith(
                strokes: duplicatedStrokes,
                images: duplicatedImages,
                path: select.selectResult.path.shift(duplicationFeedbackOffset),
              );

              history.recordChange(
                HistoricAdd(
                  strokes: duplicatedStrokes,
                  images: duplicatedImages,
                ),
              );
              autosaveAfterDelay();
            });
          },
          deleteSelection: () {
            final select = currentTool as Select;
            if (!select.doneSelecting) {
              return;
            }

            setState(() {
              final page = coreInfo.pages[select.selectResult.pageIndex];
              final strokes = select.selectResult.strokes;
              final images = select.selectResult.images;

              for (final stroke in strokes) {
                page.strokes.remove(stroke);
              }
              for (final image in images) {
                page.images.remove(image);
              }

              select.unselect();

              history.recordChange(
                HistoricDelete(strokes: strokes, images: images),
              );
              autosaveAfterDelay();
            });
          },
          setColor: (color) {
            setState(() {
              updateColorBar(color);

              if (currentTool is Highlighter) {
                (currentTool as Highlighter).color = color.withAlpha(
                  Highlighter.alpha,
                );
              } else if (currentTool is TapePen) {
                (currentTool as TapePen).color = color.withAlpha(
                  TapePen.alpha,
                );
                stows.lastTapePattern.value = -1; // Farbe gewählt = einfarbig
              } else if (currentTool is Pen) {
                (currentTool as Pen).color = color;
                _savePenColor(currentTool as Pen);
              } else if (currentTool is Select) {
                // Changes color of selected strokes
                final select = currentTool as Select;
                if (select.doneSelecting) {
                  final strokes = select.selectResult.strokes;

                  final colorChanges = <Stroke, Change<Color>>{};
                  for (final stroke in strokes) {
                    colorChanges[stroke] = Change(
                      previous: stroke.color,
                      current: color,
                    );
                    stroke.color = color;
                  }

                  history.recordChange(
                    HistoricColorChange(
                      pageIndex: strokes.first.pageIndex,
                      colorChanges: colorChanges,
                    ),
                  );
                  autosaveAfterDelay();
                }
              }
            });
          },
          quillFocus: quillFocus,
          textEditing: currentTool == Tool.textEditing,
          toggleTextEditing: () => setState(() {
            if (currentTool == Tool.textEditing) {
              currentTool = Pen.currentPen;
              for (final page in coreInfo.pages) {
                // unselect text, but maintain cursor position
                page.quill.controller.moveCursorToPosition(
                  page.quill.controller.selection.extentOffset,
                );
                page.quill.focusNode.unfocus();
              }
            } else {
              currentTool = Tool.textEditing;
              quillFocus.value = coreInfo.pages[currentPageIndex].quill
                ..focusNode.requestFocus();
            }
          }),
          undo: undo,
          isUndoPossible: history.canUndo,
          redo: redo,
          isRedoPossible: history.canRedo,
          toggleFingerDrawing: () {
            stows.editorFingerDrawing.value = !stows.editorFingerDrawing.value;
            lastSeenPointerCount = 0;
          },
          pickPhoto: _pickPhotos,
          toggleWritingPad: _toggleWritingPad,
          toggleRuler: _toggleRuler,
          rulerVisible: Guides.ruler != null,
          toggleProtractor: _toggleProtractor,
          protractorMode: Guides.protractor == null
              ? 0
              : (Guides.protractor!.full ? 2 : 1),
          writingPadVisible: showWritingPad,
          paste: paste,
          exportAsSba: exportAsSba,
          exportAsPdf: exportAsPdf,
          exportAsPng: exportAsPng,
        ),
      ),
    );

    Widget body;
    if (isToolbarVertical) {
      final editorToolbarAlignment = stows.editorToolbarAlignment.value;
      body = Row(
        textDirection: editorToolbarAlignment == .left ? .ltr : .rtl,
        children: [
          toolbar,
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: SafeArea(
                    left: editorToolbarAlignment != .left,
                    right: editorToolbarAlignment != .right,
                    child: canvas,
                  ),
                ),
                if (showWritingPad) _buildWritingPad(),
                readonlyBanner,
              ],
            ),
          ),
        ],
      );
    } else {
      final editorToolbarAlignment = stows.editorToolbarAlignment.value;
      body = Column(
        verticalDirection: editorToolbarAlignment == .up ? .up : .down,
        children: [
          // Bei Leiste oben läuft die Spalte von unten nach oben: Das Schreibfeld
          // steht dann als Erstes und damit ganz unten. Es ist immer unten.
          if (showWritingPad && editorToolbarAlignment == .up)
            _buildWritingPad(),
          Expanded(
            child: SafeArea(
              top: editorToolbarAlignment != .up,
              bottom: editorToolbarAlignment != .down,
              child: canvas,
            ),
          ),
          if (showWritingPad && editorToolbarAlignment != .up)
            _buildWritingPad(),
          toolbar,
          readonlyBanner,
        ],
      );
    }

    body = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _targetPointerDown,
      onPointerUp: _targetPointerUp,
      child: body,
    );

    return ValueListenableBuilder(
      valueListenable: savingState,
      builder: (context, savingState, child) {
        // don't allow user to go back until saving is done
        return PopScope(
          canPop: savingState == .saved,
          onPopInvokedWithResult: (didPop, _) {
            switch (savingState) {
              case .waitingToSave:
                assert(!didPop);
                saveToFile(); // trigger save now
                snackBarNeedsToSaveBeforeExiting();
              case .saving:
                assert(!didPop);
                snackBarNeedsToSaveBeforeExiting();
              case .saved:
                break;
            }
          },
          child: child!,
        );
      },
      child: Scaffold(
        appBar: DynamicMaterialApp.isFullscreen
            ? null
            : AppBar(
                toolbarHeight: kToolbarHeight,
                title: widget.customTitle != null
                    ? Text(widget.customTitle!)
                    : Form(
                        key: _filenameFormKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: TextFormField(
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                          ),
                          controller: filenameTextEditingController,
                          onChanged: renameFile,
                          autofocus: needsNaming,
                          validator: _validateFilenameTextField,
                        ),
                      ),
                leading: SaveIndicator(
                  savingState: savingState,
                  triggerSave: saveToFile,
                ),
                actions: [
                  IconButton(
                    icon: const AdaptiveIcon(
                      icon: Icons.insert_page_break,
                      cupertinoIcon: CupertinoIcons.add,
                    ),
                    tooltip: t.editor.menu.insertPage,
                    onPressed: () => setState(() {
                      final currentPageIndex = this.currentPageIndex;
                      insertPageAfter(currentPageIndex);
                      scrollToPageIndex(currentPageIndex + 1);
                    }),
                  ),
                  IconButton(
                    icon: Icon(
                      _toolbarHidden
                          ? Icons.edit_outlined
                          : Icons.keyboard_hide_outlined,
                    ),
                    tooltip: _toolbarHidden
                        ? 'Werkzeugleiste einblenden'
                        : 'Werkzeugleiste ausblenden',
                    onPressed: () => setState(() {
                      _toolbarHidden = !_toolbarHidden;
                    }),
                  ),
                  IconButton(
                    icon: Icon(
                      horizontalPaging ? Icons.swap_vert : Icons.swap_horiz,
                    ),
                    tooltip: horizontalPaging
                        ? 'Seiten untereinander (vertikal blättern)'
                        : 'Seiten nebeneinander (wie ein Buch blättern)',
                    onPressed: toggleHorizontalPaging,
                  ),
                  IconButton(
                    icon: const AdaptiveIcon(
                      icon: Icons.grid_view,
                      cupertinoIcon: CupertinoIcons.rectangle_grid_2x2,
                    ),
                    tooltip: t.editor.pages,
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AdaptiveAlertDialog(
                          title: Text(t.editor.pages),
                          content: pageManager(context),
                          actions: const [],
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const AdaptiveIcon(
                      icon: Icons.more_vert,
                      cupertinoIcon: CupertinoIcons.ellipsis_vertical,
                    ),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (context) => bottomSheet(context),
                        isScrollControlled: true,
                        showDragHandle: true,
                        backgroundColor: colorScheme.surface,
                        constraints: const BoxConstraints(maxWidth: 500),
                      );
                    },
                  ),
                ],
              ),
        body: body,
        floatingActionButton:
            (DynamicMaterialApp.isFullscreen &&
                !stows.editorToolbarShowInFullscreen.value)
            ? FloatingActionButton(
                shape: platform.isCupertino ? const CircleBorder() : null,
                onPressed: () {
                  DynamicMaterialApp.setFullscreen(false, updateSystem: true);
                },
                child: const Icon(Icons.fullscreen_exit),
              )
            : null,
      ),
    );
  }

  /// Feder: Werkzeugleiste manuell ausblenden (mehr Platz im Quermodus).
  bool _toolbarHidden = false;

  void snackBarNeedsToSaveBeforeExiting() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.editor.needsToSaveBeforeExiting)));
  }

  Widget bottomSheet(BuildContext context) {
    final Brightness brightness = Theme.brightnessOf(context);
    final invert = stows.editorAutoInvert.value && brightness == .dark;
    final int currentPageIndex = this.currentPageIndex;

    return EditorBottomSheet(
      invert: invert,
      coreInfo: coreInfo,
      currentPageIndex: currentPageIndex,
      setBackgroundPattern: (pattern) => setState(() {
        if (coreInfo.readOnly) return;
        final previous = coreInfo.backgroundPattern;
        coreInfo.backgroundPattern = pattern;
        stows.lastBackgroundPattern.value = pattern;
        history.recordChange(
          HistoricBackgroundPatternChange(
            pageIndex: currentPageIndex,
            change: Change(previous: previous, current: pattern),
          ),
        );
        autosaveAfterDelay();
      }),
      setLineHeight: (lineHeight) => setState(() {
        if (coreInfo.readOnly) return;
        coreInfo.lineHeight = lineHeight;
        stows.lastLineHeight.value = lineHeight;
        autosaveAfterDelay();
      }),
      setLineThickness: (lineThickness) => setState(() {
        if (coreInfo.readOnly) return;
        coreInfo.lineThickness = lineThickness;
        stows.lastLineThickness.value = lineThickness;
        autosaveAfterDelay();
      }),
      removeBackgroundImage: () => setState(() {
        if (coreInfo.readOnly) return;

        final page = coreInfo.pages[currentPageIndex];
        if (page.backgroundImage == null) return;
        page.images.add(page.backgroundImage!);
        page.backgroundImage = null;

        autosaveAfterDelay();
      }),
      redrawImage: () => setState(() {}),
      clearPage: () {
        clearPage(currentPageIndex);
      },
      clearAllPages: clearAllPages,
      redrawAndSave: () => setState(() {
        if (coreInfo.readOnly) return;
        autosaveAfterDelay();
      }),
      pickPhotos: _pickPhotos,
      importPdf: importPdf,
      canRasterPdf: Editor.canRasterPdf,
      getIsWatchingServer: () => _watchServerTimer?.isActive ?? false,
      setIsWatchingServer: (bool watch) {
        if (watch) {
          _watchServerTimer ??= Timer.periodic(
            const Duration(seconds: 5),
            (_) => _refreshCurrentNote(),
          );
          if (coreInfo.readOnlyReason != .watchingServer) {
            assert(coreInfo.readOnlyReason == null);
            coreInfo.readOnlyReason = .watchingServer;
            if (mounted) setState(() {});
          }
        } else {
          _watchServerTimer?.cancel();
          _watchServerTimer = null;
          if (coreInfo.readOnlyReason == .watchingServer) {
            coreInfo.readOnlyReason = null;
            if (mounted) setState(() {});
          }
        }
      },
    );
  }

  Widget pageBuilder(BuildContext context, int pageIndex) {
    final page = coreInfo.pages[pageIndex];
    final currentStroke = Pen.currentStroke?.pageIndex == pageIndex
        ? Pen.currentStroke
        : null;
    return Canvas(
      path: coreInfo.filePath,
      page: page,
      pageIndex: pageIndex,
      textEditing: currentTool == Tool.textEditing,
      coreInfo: coreInfo,
      currentStroke: currentStroke,
      currentStrokeDetectedShape:
          (currentTool is ShapePen ||
              (currentTool is Pen && stows.autoShape.value)) &&
              currentStroke != null
          ? ShapePen.detectedShape
          : null,
      currentSelection: () {
        if (currentTool is! Select) return null;
        final selectResult = (currentTool as Select).selectResult;
        if (selectResult.pageIndex != pageIndex) return null;
        return selectResult;
      }(),
      setAsBackground: (EditorImage image) {
        if (page.backgroundImage != null) {
          // restore previous background image as normal image
          page.images.add(page.backgroundImage!);
        }
        page.images.remove(image);
        page.backgroundImage = image;

        CanvasImage.activeListener
            .notifyListenersPlease(); // un-select active image

        autosaveAfterDelay();
        setState(() {});
      },
      currentTool: currentTool,
      currentScale: _transformationController.value.approxScale,
    );
  }

  /// Kopiert oder verschiebt Seiten in ein anderes Notizbuch.
  Future<bool> transferPages(
    BuildContext context,
    List<int> pageIndexes,
    bool move,
  ) async {
    if (coreInfo.readOnly && move) return false;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final target = await pickNotebook(
      context,
      title: move ? 'Seiten verschieben nach' : 'Seiten kopieren nach',
      excludePath: coreInfo.filePath,
    );
    if (target == null) return false;

    try {
      final count = await copyPagesToNote(
        source: coreInfo,
        pageIndexes: pageIndexes,
        targetPath: target,
      );
      if (move && mounted) {
        setState(() {
          for (final pageIndex in [...pageIndexes]..sort((a, b) => b - a)) {
            final page = coreInfo.pages.removeAt(pageIndex);
            createPage(pageIndex - 1);
            history.recordChange(
              HistoricPageDelete(pageIndex: pageIndex, page: page),
            );
          }
          autosaveAfterDelay();
        });
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            move ? '$count Seite(n) verschoben' : '$count Seite(n) kopiert',
          ),
        ),
      );
      return true;
    } catch (e, st) {
      log.severe('Seiten übertragen fehlgeschlagen: $e', e, st);
      messenger?.showSnackBar(
        const SnackBar(content: Text('Übertragen fehlgeschlagen')),
      );
      return false;
    }
  }

  Widget pageManager(BuildContext context) {
    return EditorPageManager(
      coreInfo: coreInfo,
      onTransfer: (pages, move) => transferPages(context, pages, move),
      scrollToPageOverride: scrollToPageIndex,
      currentPageIndex: currentPageIndex,
      redrawAndSave: () => setState(() {
        if (coreInfo.readOnly) return;
        autosaveAfterDelay();
      }),
      insertPageAfter: insertPageAfter,
      duplicatePage: (int pageIndex) => setState(() {
        if (coreInfo.readOnly) return;
        final page = coreInfo.pages[pageIndex];
        final newPage = page.copyWith(
          strokes: page.strokes
              .map((stroke) => stroke.copy()..pageIndex += 1)
              .toList(),
          images: page.images
              .map((image) => image.clone()..pageIndex += 1)
              .toList(),
          quill: QuillStruct(
            controller: flutter_quill.QuillController(
              document: flutter_quill.Document.fromDelta(
                page.quill.controller.document.toDelta(),
              ),
              selection: const TextSelection.collapsed(offset: 0),
            ),
            focusNode: FocusNode(debugLabel: 'Quill Focus Node'),
          ),
          backgroundImage: page.backgroundImage?.copy()?..pageIndex += 1,
        );
        coreInfo.pages.insert(pageIndex + 1, newPage);
        listenToQuillChanges(newPage.quill, pageIndex + 1);
        history.recordChange(
          HistoricPageInsert(pageIndex: pageIndex + 1, page: newPage),
        );
        autosaveAfterDelay();
      }),
      clearPage: clearPage,
      deletePage: (int pageIndex) => setState(() {
        if (coreInfo.readOnly) return;
        final page = coreInfo.pages.removeAt(pageIndex);
        createPage(pageIndex - 1);
        history.recordChange(
          HistoricPageDelete(pageIndex: pageIndex, page: page),
        );
        autosaveAfterDelay();
      }),
      transformationController: _transformationController,
    );
  }

  void insertPageAfter(int pageIndex) => setState(() {
    if (coreInfo.readOnly) return;
    final page = EditorPage();
    coreInfo.pages.insert(pageIndex + 1, page);
    listenToQuillChanges(page.quill, pageIndex + 1);
    history.recordChange(
      HistoricPageInsert(pageIndex: pageIndex + 1, page: page),
    );
    autosaveAfterDelay();
  });

  void clearPage(int pageIndex) {
    if (coreInfo.readOnly) return;
    final page = coreInfo.pages[pageIndex];
    setState(() {
      final removedStrokes = page.strokes.toList();
      final removedImages = page.images.toList();
      page.strokes.clear();
      page.images.clear();
      removeExcessPages();
      history.recordChange(
        HistoricDelete(strokes: removedStrokes, images: removedImages),
      );
      autosaveAfterDelay();
    });
  }

  void clearAllPages() {
    if (coreInfo.readOnly) return;
    setState(() {
      final removedStrokes = <Stroke>[];
      final removedImages = <EditorImage>[];
      for (final page in coreInfo.pages) {
        removedStrokes.addAll(page.strokes);
        removedImages.addAll(page.images);
        page.strokes.clear();
        page.images.clear();
      }
      removeExcessPages();
      history.recordChange(
        HistoricDelete(strokes: removedStrokes, images: removedImages),
      );
    });
    autosaveAfterDelay();
  }

  Future<void> showVersionTooNewDialog() async {
    final disableReadOnly =
        await showDialog(
          context: context,
          builder: (context) => AdaptiveAlertDialog(
            title: Text(t.editor.versionTooNew.title),
            content: Text(t.editor.versionTooNew.subtitle),
            actions: [
              CupertinoDialogAction(
                child: Text(t.common.cancel),
                onPressed: () => Navigator.pop(context, false),
              ),
              CupertinoDialogAction(
                child: Text(t.editor.versionTooNew.allowEditing),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted) return;
    if (!disableReadOnly) return;

    if (coreInfo.readOnlyReason == .versionTooNew) {
      coreInfo.readOnlyReason = null;
      if (mounted) setState(() {});
    }
  }

  late int _lastCurrentPageIndex = coreInfo.initialPageIndex ?? 0;

  /// The index of the page that is currently centered on screen.
  int get currentPageIndex {
    if (!mounted) return _lastCurrentPageIndex;

    final screenWidth = MediaQuery.sizeOf(context).width;

    if (horizontalPaging) {
      final detector = _canvasGestureDetectorKey.currentState;
      if (detector == null) return _lastCurrentPageIndex;
      return _lastCurrentPageIndex = detector.horizontalPageIndex
          .clamp(0, math.max(0, coreInfo.pages.length - 1))
          .toInt();
    }

    return _lastCurrentPageIndex = getPageIndexFromScrollPosition(
      scrollY: -scrollY,
      screenWidth: screenWidth,
      pages: coreInfo.pages,
    );
  }

  @visibleForTesting
  static int getPageIndexFromScrollPosition({
    required double scrollY,
    required double screenWidth,
    required List<EditorPage> pages,
  }) {
    for (int pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final bottomOfPage = CanvasGestureDetector.getTopOfPage(
        pageIndex: pageIndex + 1, // top of next page
        pages: pages,
        screenWidth: screenWidth,
      );

      if (scrollY < bottomOfPage) {
        return pageIndex;
      }
    }
    // below the last page
    return pages.length - 1;
  }

  @override
  void dispose() {
    unawaited(_cleanUpAsync());

    DynamicMaterialApp.removeFullscreenListener(_setState);
    if (Pen.onHoldShapeDetected == _setState) Pen.onHoldShapeDetected = null;
    writingPadController.removeListener(_onWritingPadChanged);
    _transformationController.removeListener(_syncGuidesToPage);
    StampPen.onPlaceText = null;
    WritingPadGuide.clear();
    Guides.clear();
    if (EditorImage.dropHandler == _onDropImage) EditorImage.dropHandler = null;
    if (EditorImage.targetHandler == _startImageTarget) {
      EditorImage.targetHandler = null;
    }
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    writingPadController.dispose();

    _delayedSaveTimer?.cancel();
    _watchServerTimer?.cancel();
    _lastSeenPointerCountTimer?.cancel();

    _removeKeybindings();

    // manually save pen properties since the listeners don't fire if a property is changed
    stows.lastFountainPenOptions.notifyListeners();
    stows.lastBallpointPenOptions.notifyListeners();
    stows.lastHighlighterOptions.notifyListeners();
    stows.lastTapeOptions.notifyListeners();
    stows.lastPencilOptions.notifyListeners();
    stows.lastShapePenOptions.notifyListeners();

    super.dispose();
  }

  Future<void> _cleanUpAsync() async {
    try {
      if (_renameTimer?.isActive ?? false) {
        _renameTimer!.cancel();
        await _renameFileNow();
        filenameTextEditingController.dispose();
      }
      await saveToFile();
    } finally {
      coreInfo.dispose();
    }
  }
}
