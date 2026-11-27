import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:saber/data/routes.dart';
import 'package:saber/data/search/search_index.dart';
import 'package:saber/data/tasks/ink_recognition.dart';

/// Feder: Suche in Handschrift und getipptem Text aller Notizen.
/// Beim Öffnen wird der Index aktualisiert (nur neue/geänderte Notizen).
class HandwritingSearchPage extends StatefulWidget {
  const HandwritingSearchPage({super.key, this.scope});

  /// Notiz oder Ordner, auf den die Suche beschränkt werden kann.
  final String? scope;

  @override
  State<HandwritingSearchPage> createState() => _HandwritingSearchPageState();
}

class _HandwritingSearchPageState extends State<HandwritingSearchPage> {
  final _controller = TextEditingController();
  var _hits = <SearchHit>[];
  var _indexing = false;
  var _done = 0, _total = 0;
  var _cancelled = false;
  String? _error;
  var _searched = false;
  late var _onlyHere = widget.scope != null && widget.scope != '/';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _cancelled = true;
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool rebuild = false}) async {
    if (_indexing) return;
    setState(() {
      _indexing = true;
      _error = null;
      _cancelled = false;
    });
    try {
      if (rebuild) await SearchIndex.clear();
      await SearchIndex.refresh(
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _done = done;
            _total = total;
          });
        },
        isCancelled: () => _cancelled || !mounted,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Indexieren abgebrochen: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _indexing = false);
        if (_controller.text.trim().isNotEmpty) _search();
      }
    }
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(() {
        _hits = [];
        _searched = false;
      });
      return;
    }
    final hits = await SearchIndex.search(
      q,
      scope: _onlyHere ? widget.scope : null,
    );
    if (!mounted) return;
    setState(() {
      _hits = hits;
      _searched = true;
    });
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (_) => _search(),
          decoration: const InputDecoration(
            hintText: 'Handschrift und Text durchsuchen',
            border: InputBorder.none,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'rebuild') _refresh(rebuild: true);
              if (v == 'refresh') _refresh();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'refresh', child: Text('Index aktualisieren')),
              PopupMenuItem(
                value: 'rebuild',
                child: Text('Index komplett neu aufbauen'),
              ),
            ],
          ),
        ],
        bottom: _indexing
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: _total == 0 ? null : _done / _total,
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          if (widget.scope != null && widget.scope != '/')
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: Text('Nur in „${p.basename(widget.scope!)}“'),
                  selected: _onlyHere,
                  onSelected: (v) {
                    setState(() => _onlyHere = v);
                    _search();
                  },
                ),
              ),
            ),
          if (!InkRecognition.supported)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text(
                'Handschrift-Erkennung gibt es nur auf Android. '
                'Getippter Text wird trotzdem durchsucht.',
              ),
            ),
          if (_indexing)
            ListTile(
              dense: true,
              leading: const Icon(Icons.manage_search),
              title: Text(
                _total == 0
                    ? 'Prüfe Notizen …'
                    : 'Lese Notizen: $_done von $_total '
                          '(Treffer stammen bis dahin aus dem alten Stand)',
              ),
            ),
          if (_error != null)
            ListTile(
              leading: Icon(Icons.error_outline, color: scheme.error),
              title: Text(_error!),
              subtitle: const Text(
                'Beim ersten Mal braucht die Erkennung einmalig Internet '
                '(Sprachmodell, ca. 20 MB).',
              ),
            ),
          Expanded(
            child: _hits.isEmpty
                ? Center(
                    child: Text(
                      !_searched
                          ? 'Suchbegriff eingeben'
                          : _indexing
                          ? 'Noch keine Treffer, Index wird noch aufgebaut …'
                          : 'Keine Treffer',
                    ),
                  )
                : ListView.separated(
                    itemCount: _hits.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final hit = _hits[i];
                      final folder = p.dirname(hit.path);
                      return ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(p.basename(hit.path)),
                        subtitle: Text(
                          '${folder == '/' ? '' : '${folder.replaceFirst('/', '')} · '}'
                          'Seite ${hit.pageIndex + 1}'
                          '${hit.snippet.isEmpty ? '' : '\n${hit.snippet}'}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: hit.snippet.isNotEmpty,
                        onTap: () => context.push(
                          RoutePaths.editFilePathPage(hit.path, hit.pageIndex),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
