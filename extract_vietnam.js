const fs = require('fs');

const content = fs.readFileSync(
  'C:\\Users\\reyhp\\.gemini\\antigravity\\brain\\270fb493-8116-429c-9cc5-2a270ee3d765\\.system_generated\\steps\\153\\content.md',
  'utf-8'
);

const jsonStart = content.indexOf('{');
const data = JSON.parse(content.slice(jsonStart));

for (const feature of data.features) {
  const props = feature.properties || {};
  const name = props.NAME || props.name || props.ADMIN || '';
  const iso3 = props.ISO_A3 || props.iso_a3 || '';

  if (name.includes('Vietnam') || name.includes('Viet') || iso3 === 'VNM') {
    const geom = feature.geometry;
    console.log(`Found Vietnam! Type: ${geom.type}`);

    let coords;
    if (geom.type === 'Polygon') {
      coords = geom.coordinates[0];
    } else if (geom.type === 'MultiPolygon') {
      // Find the largest polygon (mainland)
      let largest = geom.coordinates[0][0];
      for (const poly of geom.coordinates) {
        if (poly[0].length > largest.length) largest = poly[0];
      }
      coords = largest;
      console.log(`Total polygons: ${geom.coordinates.length}`);
      geom.coordinates.forEach((p, i) => console.log(`  Polygon ${i}: ${p[0].length} points`));
    }

    console.log(`Mainland points: ${coords.length}`);

    const lines = coords.map(([lon, lat]) => `  LatLng(${lat}, ${lon}),`);
    const output = [
      '// Vietnam border coordinates (Natural Earth 50m)',
      `// Total points: ${coords.length}`,
      'final List<LatLng> _vietnamBorder = [',
      ...lines,
      '];',
    ].join('\n');

    fs.writeFileSync('vietnam_coords.dart', output, 'utf-8');
    console.log('Written to vietnam_coords.dart');
    break;
  }
}
