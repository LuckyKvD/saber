import 'package:flutter/widgets.dart' show MediaQuery;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/toolbar/pick_notebook_dialog.dart';
import 'package:saber/pages/editor/editor.dart';

/// Feder: Zwei Notizen nebeneinander (zum Abschreiben, Vergleichen, Ordnen).
///
/// Jede Seite ist ein vollständiger Editor. Die Breite wird den Editoren per
/// [MediaQuery] mitgeteilt, damit Seiten auf die halbe Breite passen.
class SplitPage extends StatefulWidget {
  const SplitPage({super.key, required this.left, required this.right});

  final String? left;
  final String? right;

  @override
  State<SplitPage> createState() => _SplitPageState();
}

class _SplitPageState extends State<SplitPage> {
  late String? _left = widget.left;
  late String? _right = widget.right;
  double _ratio = 0.5;

  static const _bar = 40.0;
  static const _divider = 14.0;

  Future<void> _choose(bool left) async {
    final other = left ? _right : _left;
    final path = await pickNotebook(
      context,
      title: left ? 'Notiz links' : 'Notiz rechts',
      excludePath: other,
    );
    if (path == null || !mounted) return;
    setState(() {
      if (left) {
        _left = path;
      } else {
        _right = path;
      }
    });
  }

  Widget _pane(String? path, bool left, double width, double height) {
    final scheme = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        children: [
          Container(
            height: _bar,
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    path == null ? 'Keine Notiz' : p.basename(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _choose(left),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Andere Notiz'),
                ),
                if (left)
                  IconButton(
                    tooltip: 'Zwei-Notizen-Ansicht schließen',
                    icon: const Icon(Icons.close),
                    onPressed: () => context.pop(),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ClipRect(
              child: path == null
                  ? Center(
                      child: FilledButton(
                        onPressed: () => _choose(left),
                        child: const Text('Notiz wählen'),
                      ),
                    )
                  : MediaQuery(
                      data: mq.copyWith(
                        size: Size(width, height - _bar),
                        padding: EdgeInsets.zero,
                        viewPadding: EdgeInsets.zero,
                      ),
                      child: Editor(
                        key: ValueKey('$left:$path'),
                        path: path,
                        inSplit: true,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final total = constraints.maxWidth - _divider;
            final leftWidth = (total * _ratio).clamp(260.0, total - 260.0).toDouble();
            final rightWidth = total - leftWidth;
            return Row(
              children: [
                _pane(_left, true, leftWidth, constraints.maxHeight),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) => setState(() {
                    _ratio = ((leftWidth + d.delta.dx) / total).clamp(0.25, 0.75);
                  }),
                  child: Container(
                    width: _divider,
                    color: Theme.of(context).colorScheme.outlineVariant,
                    child: const Center(
                      child: Icon(Icons.drag_indicator, size: 14),
                    ),
                  ),
                ),
                _pane(_right, false, rightWidth, constraints.maxHeight),
              ],
            );
          },
        ),
      ),
    );
  }
}
