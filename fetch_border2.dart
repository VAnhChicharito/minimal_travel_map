import 'dart:convert';
import 'dart:io';

void main() async {
  final url = Uri.parse('https://raw.githubusercontent.com/nguyenduy1133/data/main/Dia_phan_Tinh_cap_nhat.geojson');
  print('Fetching $url...');
  final httpClient = HttpClient();
  try {
    final request = await httpClient.getUrl(url);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('HTTP Error: ${response.statusCode}');
    }
    final stringData = await response.transform(utf8.decoder).join();
    
    final geojson = json.decode(stringData);
    
    StringBuffer dartCode = StringBuffer();
    dartCode.writeln("import 'package:latlong2/latlong.dart';");
    dartCode.writeln("");
    dartCode.writeln("final List<List<LatLng>> vietnamBorderPolygons = [");
    
    int polyCount = 0;
    
    List features = geojson['features'];
    for (var feature in features) {
      var geometry = feature['geometry'];
      if (geometry == null) continue;
      
      var type = geometry['type'];
      var coords = geometry['coordinates'];
      
      if (type == 'Polygon') {
        coords = [coords];
      } else if (type != 'MultiPolygon') {
        continue;
      }
      
      for (var polygon in coords) {
        var ring = polygon[0]; // exterior ring
        dartCode.writeln("  [");
        for (var pt in ring) {
          dartCode.writeln("    LatLng(${pt[1]}, ${pt[0]}),");
        }
        dartCode.writeln("  ],");
        polyCount++;
      }
    }
    
    dartCode.writeln("];");
    
    File('lib/vietnam_border.dart').writeAsStringSync(dartCode.toString());
    print("Successfully wrote lib/vietnam_border.dart with $polyCount polygons.");
    
  } catch(e) {
    print('Error: $e');
  } finally {
    httpClient.close();
  }
}
