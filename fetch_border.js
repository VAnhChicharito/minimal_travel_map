const fs = require('fs');
const https = require('https');

const url = 'https://raw.githubusercontent.com/glynnbird/countriesgeojson/master/vietnam.geojson';

https.get(url, (res) => {
    let data = '';
    res.on('data', chunk => { data += chunk; });
    res.on('end', () => {
        try {
            const geojson = JSON.parse(data);
            let coords = [];
            
            // Handle Polygon or MultiPolygon
            let type = geojson.geometry ? geojson.geometry.type : geojson.features[0].geometry.type;
            let geometryCoords = geojson.geometry ? geojson.geometry.coordinates : geojson.features[0].geometry.coordinates;

            let dartCode = "import 'package:latlong2/latlong.dart';\n\n";
            dartCode += "final List<List<LatLng>> vietnamBorderPolygons = [\n";

            if (type === 'Polygon') {
                geometryCoords = [geometryCoords];
            }

            // MultiPolygon is [[[ [lng, lat], ... ]]]
            for (let polygon of geometryCoords) {
                // Usually polygon[0] is the exterior ring
                let ring = polygon[0];
                dartCode += "  [\n";
                for (let pt of ring) {
                    dartCode += `    LatLng(${pt[1]}, ${pt[0]}),\n`;
                }
                dartCode += "  ],\n";
            }
            dartCode += "];\n";

            fs.writeFileSync('lib/vietnam_border.dart', dartCode);
            console.log("Successfully wrote lib/vietnam_border.dart with " + geometryCoords.length + " polygons.");
        } catch(e) {
            console.error("Error parsing GeoJSON:", e);
        }
    });
}).on('error', (e) => {
    console.error(e);
});
