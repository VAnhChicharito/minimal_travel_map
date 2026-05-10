import 'dart:convert';
import 'dart:io';

void main() async {
  final url = Uri.parse('https://raw.githubusercontent.com/glynnbird/countriesgeojson/master/vietnam.geojson');
  print('Fetching $url...');
  final httpClient = HttpClient();
  try {
    final request = await httpClient.getUrl(url);
    final response = await request.close();
    final stringData = await response.transform(utf8.decoder).join();
    
    final geojson = json.decode(stringData);
    
    // Some GeoJSON wrap in FeatureCollection
    Map<String, dynamic> geometry;
    if (geojson['type'] == 'FeatureCollection') {
      geometry = geojson['features'][0]['geometry'];
    } else if (geojson['type'] == 'Feature') {
      geometry = geojson['geometry'];
    } else {
      geometry = geojson;
    }
    
    List<dynamic> coords = geometry['coordinates'];
    
    StringBuffer dartCode = StringBuffer();
    dartCode.writeln("import 'package:latlong2/latlong.dart';");
    dartCode.writeln("");
    dartCode.writeln("final List<List<LatLng>> vietnamBorderPolygons = [");
    
    if (geometry['type'] == 'Polygon') {
      coords = [coords];
    }
    
    int polyCount = 0;
    for (var polygon in coords) {
      var ring = polygon[0]; // exterior ring
      dartCode.writeln("  [");
      for (var pt in ring) {
        dartCode.writeln("    LatLng(${pt[1]}, ${pt[0]}),");
      }
      dartCode.writeln("  ],");
      polyCount++;
    }
    dartCode.writeln("];");
    
    File('lib/vietnam_border.dart').writeAsStringSync(dartCode.toString());
    print("Successfully wrote lib/vietnam_border.dart with \$polyCount polygons.");
    
  } catch(e) {
    print('Error: $e');
  } finally {
    httpClient.close();
  }
}
