import 'package:material_ui/material_ui.dart';

/// Eine Schnittebene eines Fotos: ein Vieleck (Anteile der Fotogröße 0..1).
/// [inside] = nur das Innere des Vielecks bleibt sichtbar, sonst nur das Äußere.
@immutable
class ImageClip {
  const ImageClip({required this.inside, required this.points});

  final bool inside;
  final List<Offset> points;

  Map<String, dynamic> toJson() => {
    'm': inside ? 0 : 1,
    'p': [
      for (final p in points) ...[p.dx, p.dy],
    ],
  };

  factory ImageClip.fromJson(Map<String, dynamic> json) {
    final flat = (json['p'] as List<dynamic>).cast<num>();
    return ImageClip(
      inside: (json['m'] ?? 0) == 0,
      points: [
        for (int i = 0; i + 1 < flat.length; i += 2)
          Offset(flat[i].toDouble(), flat[i + 1].toDouble()),
      ],
    );
  }

  static List<ImageClip> listFromJson(dynamic json) {
    if (json is! List) return const [];
    return [
      for (final item in json)
        ImageClip.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  /// Sichtbarer Bereich für ein Foto der Größe [size].
  static Path pathFor(List<ImageClip> layers, Size size) {
    var path = Path()..addRect(Offset.zero & size);
    for (final layer in layers) {
      if (layer.points.length < 3) continue;
      final poly = Path()
        ..addPolygon([
          for (final p in layer.points) Offset(p.dx * size.width, p.dy * size.height),
        ], true);
      path = Path.combine(
        layer.inside ? PathOperation.intersect : PathOperation.difference,
        path,
        poly,
      );
    }
    return path;
  }
}

class ImageClipper extends CustomClipper<Path> {
  const ImageClipper(this.layers);
  final List<ImageClip> layers;

  @override
  Path getClip(Size size) => ImageClip.pathFor(layers, size);

  @override
  bool shouldReclip(ImageClipper oldClipper) => true;
}
