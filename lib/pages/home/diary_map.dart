import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/diary.dart';
import 'package:saber/data/routes.dart';

/// Weltkarte mit allen Tagebuch-Orten (Kartenkacheln von OpenStreetMap).
class DiaryMapPage extends StatefulWidget {
  const new({super.key});

  @override
  State<DiaryMapPage> createState() => _DiaryMapPageState();
}

class _DiaryMapPageState extends State<DiaryMapPage> {
  List<(DateTime, DiaryLocation)>? entries;

  @override
  void initState() {
    super.initState();
    Diary.allLocations().then((value) {
      if (mounted) setState(() => entries = value);
    });
  }

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final list = entries;
    return Scaffold(
      appBar: AppBar(title: const Text('Tagebuch-Karte')),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Noch keine Orte gespeichert. Orte werden beim ersten '
                  'Schreiben am jeweiligen Tag erfasst.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _map(list),
    );
  }

  Widget _map(List<(DateTime, DiaryLocation)> list) {
    final points = [for (final e in list) LatLng(e.$2.lat, e.$2.lon)];
    final options = points.length == 1
        ? MapOptions(initialCenter: points.first, initialZoom: 10)
        : MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.all(48),
              maxZoom: 12,
            ),
          );
    return FlutterMap(
      options: options,
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'de.luckykvd.feder',
        ),
        MarkerLayer(
          markers: [
            for (final e in list)
              Marker(
                point: LatLng(e.$2.lat, e.$2.lon),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => _showDay(e.$1),
                  child: const Icon(Icons.location_on, color: Colors.red, size: 36),
                ),
              ),
          ],
        ),
        const SimpleAttributionWidget(source: Text('© OpenStreetMap-Mitwirkende')),
      ],
    );
  }

  void _showDay(DateTime day) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.menu_book),
          title: Text('Eintrag vom ${_fmt(day)}'),
          subtitle: const Text('Antippen zum Öffnen'),
          onTap: () {
            Navigator.of(sheetContext).pop();
            context.push(RoutePaths.editFilePath(Diary.pathFor(day)));
          },
        ),
      ),
    );
  }
}
