import json
import sys

# Read the Natural Earth 50m GeoJSON
with open(r'C:\Users\reyhp\.gemini\antigravity\brain\270fb493-8116-429c-9cc5-2a270ee3d765\.system_generated\steps\153\content.md', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the JSON part (after the --- separator)
json_start = content.find('{')
data = json.loads(content[json_start:])

# Find Vietnam
for feature in data['features']:
    props = feature.get('properties', {})
    name = props.get('NAME', '') or props.get('name', '') or props.get('ADMIN', '')
    iso = props.get('ISO_A2', '') or props.get('iso_a2', '')
    iso3 = props.get('ISO_A3', '') or props.get('iso_a3', '')
    if 'Vietnam' in name or 'Viet' in name or iso == 'VN' or iso3 == 'VNM':
        geom = feature['geometry']
        print(f"Found Vietnam! Type: {geom['type']}")
        
        if geom['type'] == 'Polygon':
            coords = geom['coordinates'][0]  # outer ring
            print(f"Total points in main polygon: {len(coords)}")
            # Output as Dart LatLng list
            with open(r'C:\Users\reyhp\.gemini\antigravity\scratch\minimal_travel_map\vietnam_coords.dart', 'w') as out:
                out.write("// Vietnam border coordinates (Natural Earth 50m)\n")
                out.write(f"// Total points: {len(coords)}\n")
                out.write("final List<LatLng> _vietnamBorder = [\n")
                for lon, lat in coords:
                    out.write(f"  LatLng({lat}, {lon}),\n")
                out.write("];\n")
            print("Written to vietnam_coords.dart")
            
        elif geom['type'] == 'MultiPolygon':
            # Find the largest polygon (mainland)
            largest = max(geom['coordinates'], key=lambda p: len(p[0]))
            coords = largest[0]
            print(f"Total polygons: {len(geom['coordinates'])}")
            print(f"Largest polygon points: {len(coords)}")
            
            # Also list all polygon sizes
            for i, poly in enumerate(geom['coordinates']):
                print(f"  Polygon {i}: {len(poly[0])} points")
            
            with open(r'C:\Users\reyhp\.gemini\antigravity\scratch\minimal_travel_map\vietnam_coords.dart', 'w') as out:
                out.write("// Vietnam border coordinates (Natural Earth 50m)\n")
                out.write(f"// Total points in mainland: {len(coords)}\n")
                out.write("final List<LatLng> _vietnamBorder = [\n")
                for lon, lat in coords:
                    out.write(f"  LatLng({lat}, {lon}),\n")
                out.write("];\n")
            print("Written to vietnam_coords.dart")
        
        break
else:
    print("Vietnam not found!")
    # List all country names to debug
    for feature in data['features'][:10]:
        props = feature.get('properties', {})
        print(f"  - {props.get('NAME', 'N/A')} / {props.get('ADMIN', 'N/A')} / {props.get('ISO_A3', 'N/A')}")
