import 'dart:io';
import 'dart:convert';

void main() {
  final content = File(
    r'C:\Users\reyhp\.gemini\antigravity\brain\270fb493-8116-429c-9cc5-2a270ee3d765\.system_generated\steps\153\content.md'
  ).readAsStringSync();

  final jsonStart = content.indexOf('{');
  final data = jsonDecode(content.substring(jsonStart)) as Map<String, dynamic>;

  final features = data['features'] as List;

  for (final feature in features) {
    final props = (feature['properties'] ?? {}) as Map<String, dynamic>;
    final name = (props['NAME'] ?? props['name'] ?? props['ADMIN'] ?? '').toString();
    final iso3 = (props['ISO_A3'] ?? props['iso_a3'] ?? '').toString();

    if (name.contains('Vietnam') || name.contains('Viet') || iso3 == 'VNM') {
      final geom = feature['geometry'] as Map<String, dynamic>;
      print('Found Vietnam! Type: ${geom['type']}');

      List<dynamic> coords;

      if (geom['type'] == 'Polygon') {
        coords = geom['coordinates'][0] as List;
      } else {
        // MultiPolygon: find the largest polygon
        final polys = geom['coordinates'] as List;
        var largest = polys[0][0] as List;
        for (final poly in polys) {
          final ring = poly[0] as List;
          if (ring.length > largest.length) largest = ring;
        }
        coords = largest;
        print('Total polygons: ${polys.length}');
        for (int i = 0; i < polys.length; i++) {
          print('  Polygon $i: ${(polys[i][0] as List).length} points');
        }
      }

      print('Mainland points: ${coords.length}');

      final buf = StringBuffer();
      buf.writeln('// Vietnam border coordinates (Natural Earth 50m)');
      buf.writeln('// Total points: ${coords.length}');
      buf.writeln('final List<LatLng> _vietnamBorder = [');
      for (final point in coords) {
        final lon = point[0];
        final lat = point[1];
        buf.writeln('  LatLng($lat, $lon),');
      }
      buf.writeln('];');

      File('vietnam_coords.dart').writeAsStringSync(buf.toString());
      print('Written to vietnam_coords.dart');
      return;
    }
  }

  print('Vietnam not found!');
}
