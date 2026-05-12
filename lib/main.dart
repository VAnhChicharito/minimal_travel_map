import 'dart:math';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:html' as html;
import 'dart:typed_data';

import 'vietnam_cities.dart';
import 'route_segment.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minimal Travel Map',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          colorSchemeSeed: const Color(0xFF16A34A),
          useMaterial3: true,
          fontFamily: 'Segoe UI'),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class MapImageOverlay {
  MapImageOverlay({
    required this.id,
    required this.bytes,
    this.position = const Offset(80, 80),
    this.size = const Size(220, 120),
  });

  final String id;
  final Uint8List bytes;
  Offset position;
  Size size;
}

class MapTextOverlay {
  MapTextOverlay({
    required this.id,
    required this.text,
    this.position = const Offset(100, 100),
    this.size = const Size(240, 80),
    this.color = Colors.black,
    this.fontSize = 16.0,
    this.isBold = false,
    this.isItalic = false,
    this.textAlign = TextAlign.center,
  });

  final String id;
  String text;
  Offset position;
  Size size;
  Color color;
  double fontSize;
  bool isBold;
  bool isItalic;
  TextAlign textAlign;
}

class CountryBoundary {
  const CountryBoundary({
    required this.name,
    required this.code,
    required this.rings,
  });

  final String name;
  final String code;
  final List<List<LatLng>> rings;
}

class _HomePageState extends State<HomePage> {
  final MapController _mapController = MapController();
  final GlobalKey _mapKey = GlobalKey();
  final GlobalKey _boundaryKey = GlobalKey();

  final List<RouteSegment> _routes = [];
  final List<MapImageOverlay> _imageOverlays = [];
  final List<MapTextOverlay> _textOverlays = [];
  List<CountryBoundary> _countryBoundaries = [];
  List<List<LatLng>> _disputedIslandRings = [];
  int _expandedRouteIndex = -1;
  int _idCounter = 0;
  int _overlayIdCounter = 0;

  // Legend State
  bool _showLegend = true;
  Offset _legendPos = const Offset(20, 20);
  double _legendScale = 1.0;
  Set<TransportMode> _legendTransportModes = {};
  String? _activeOverlayId;

  // Crop State
  bool _isCropMode = false;
  Rect _cropRect = const Rect.fromLTWH(50, 50, 600, 400);

  final List<Color> _presetColors = const [
    Colors.blue,
    Colors.red,
    Colors.black,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink
  ];

  static const Color colorOutgoing = Color(0xFF16A34A); // Green
  static const Color colorReturn = Color(0xFFDB2777); // Pink

  // --- Input State ---
  final TextEditingController _startCtrl = TextEditingController();
  final TextEditingController _endCtrl = TextEditingController();
  final FocusNode _startFocus = FocusNode();
  final FocusNode _endFocus = FocusNode();
  List<String> _startSuggestions = [];
  List<String> _endSuggestions = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadGeoJsonBoundaries();
  }

  Future<void> _loadGeoJsonBoundaries() async {
    final countries = await _loadCountryBoundaries(
      'assets/geojson/indochina_admin0.geojson',
    );
    final islands = await _loadGeoJsonRings(
      'assets/geojson/south_china_sea_islands.geojson',
    );
    if (!mounted) return;
    setState(() {
      _countryBoundaries = countries;
      _disputedIslandRings = islands;
    });
  }

  Future<List<CountryBoundary>> _loadCountryBoundaries(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final features = data['features'] as List<dynamic>;

    return features.map((feature) {
      final featureMap = feature as Map<String, dynamic>;
      final properties = featureMap['properties'] as Map<String, dynamic>;
      final name = properties['NAME'] as String? ?? '';
      final code = properties['ADM0_A3'] as String? ??
          properties['ISO_A3'] as String? ??
          '';
      final rings = _extractGeoJsonRings(
        featureMap['geometry'] as Map<String, dynamic>,
      );
      return CountryBoundary(name: name, code: code, rings: rings);
    }).toList();
  }

  Future<List<List<LatLng>>> _loadGeoJsonRings(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final features = data['features'] as List<dynamic>;
    return features
        .expand((feature) => _extractGeoJsonRings(
              (feature as Map<String, dynamic>)['geometry']
                  as Map<String, dynamic>,
            ))
        .toList();
  }

  List<List<LatLng>> _extractGeoJsonRings(Map<String, dynamic> geometry) {
    final type = geometry['type'] as String;
    final coordinates = geometry['coordinates'] as List<dynamic>;

    if (type == 'Polygon') {
      return [_parseLinearRing(coordinates.first as List<dynamic>)];
    }
    if (type == 'MultiPolygon') {
      return coordinates
          .map((polygon) =>
              _parseLinearRing((polygon as List<dynamic>).first as List))
          .toList();
    }
    return [];
  }

  List<LatLng> _parseLinearRing(List<dynamic> ring) {
    return ring.map((point) {
      final coord = point as List<dynamic>;
      final longitude = (coord[0] as num).toDouble();
      final latitude = (coord[1] as num).toDouble();
      return LatLng(latitude, longitude);
    }).toList();
  }

  void _onStartChanged(String value) {
    final q = value.trim().toLowerCase();
    setState(() => _startSuggestions = q.isEmpty
        ? []
        : vietnamCities.keys.where((c) => c.contains(q)).take(4).toList());
  }

  void _onEndChanged(String value) {
    final q = value.trim().toLowerCase();
    setState(() => _endSuggestions = q.isEmpty
        ? []
        : vietnamCities.keys.where((c) => c.contains(q)).take(4).toList());
  }

  void _addRoute() {
    final sName = _startCtrl.text.trim().toLowerCase();
    final eName = _endCtrl.text.trim().toLowerCase();

    if (sName.isEmpty || eName.isEmpty) {
      setState(() => _errorMessage = 'Vui lòng nhập cả điểm đi và điểm đến');
      return;
    }

    final sPos = vietnamCities[sName];
    final ePos = vietnamCities[eName];

    if (sPos == null) {
      setState(() => _errorMessage = 'Không tìm thấy "${_startCtrl.text}"');
      return;
    }
    if (ePos == null) {
      setState(() => _errorMessage = 'Không tìm thấy "${_endCtrl.text}"');
      return;
    }
    if (sName == eName) {
      setState(() => _errorMessage = 'Điểm đi và đến trùng nhau!');
      return;
    }

    _idCounter++;
    setState(() {
      _routes.add(RouteSegment(
        id: '$_idCounter',
        startCity: Waypoint(name: _capitalize(sName), position: sPos),
        endCity: Waypoint(name: _capitalize(eName), position: ePos),
      ));
      _errorMessage = null;
      _startCtrl.clear();
      _endCtrl.clear();
      _startSuggestions.clear();
      _endSuggestions.clear();
      _expandedRouteIndex = _routes.length - 1; // Auto expand the new route
    });

    _fitMapToRoutes();
  }

  void _removeRoute(int index) {
    setState(() {
      _routes.removeAt(index);
      if (_expandedRouteIndex >= _routes.length) _expandedRouteIndex = -1;
    });
    _fitMapToRoutes();
  }

  List<LatLng> _getUniqueWaypointPositions() {
    final Map<String, LatLng> unique = {};
    for (var r in _routes) {
      unique[r.startCity.name] = r.effectiveStartPosition;
      unique[r.endCity.name] = r.effectiveEndPosition;
    }
    return unique.values.toList();
  }

  void _fitMapToRoutes() {
    final points = _getUniqueWaypointPositions();
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 8);
      return;
    }
    _mapController.fitBounds(
      LatLngBounds.fromPoints(points),
      options: const FitBoundsOptions(padding: EdgeInsets.all(80), maxZoom: 10),
    );
  }

  String _capitalize(String s) => s
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  Future<void> _insertImageOverlay() async {
    final input = html.FileUploadInputElement()..accept = 'image/*';
    input.click();
    await input.onChange.first;
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) return;

    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;
    final result = reader.result;
    final bytes = result is ByteBuffer
        ? Uint8List.view(result)
        : Uint8List.fromList(result as List<int>);

    setState(() {
      _overlayIdCounter++;
      _imageOverlays.add(MapImageOverlay(
        id: 'image-$_overlayIdCounter',
        bytes: bytes,
      ));
    });
  }

  Future<void> _insertTextOverlay() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm chữ lên bản đồ'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Nhập nội dung...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;

    setState(() {
      _overlayIdCounter++;
      _textOverlays.add(MapTextOverlay(
        id: 'text-$_overlayIdCounter',
        text: text,
      ));
    });
  }

  void _generateLegend() {
    setState(() {
      _legendTransportModes = _routes
          .map((route) => route.transportMode)
          .where((mode) => mode != TransportMode.none)
          .toSet();
      _showLegend = true;
    });
  }

  Future<void> _exportMap() async {
    try {
      RenderRepaintBoundary boundary = _boundaryKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      const double pr = 3.0;
      ui.Image image = await boundary.toImage(pixelRatio: pr);

      if (_isCropMode) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final paint = Paint();

        final src = Rect.fromLTWH(
          _cropRect.left * pr,
          _cropRect.top * pr,
          _cropRect.width * pr,
          _cropRect.height * pr,
        );
        final dst =
            Rect.fromLTWH(0, 0, _cropRect.width * pr, _cropRect.height * pr);

        canvas.drawImageRect(image, src, dst, paint);
        image = await recorder.endRecording().toImage(
              (_cropRect.width * pr).toInt(),
              (_cropRect.height * pr).toInt(),
            );
      }

      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();
        final blob = html.Blob([pngBytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'minimal_travel_map.png')
          ..click();
        html.Url.revokeObjectUrl(url);
      }
    } catch (e) {
      debugPrint("Export failed: $e");
    }
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    _startFocus.dispose();
    _endFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(children: [
        SizedBox(width: 380, child: _buildControlPanel()),
        Expanded(
          child: Stack(
            children: [
              RepaintBoundary(
                key: _boundaryKey,
                child: Stack(
                  children: [
                    _buildMap(),
                    ..._imageOverlays.map(_buildImageOverlay),
                    ..._textOverlays.map(_buildTextOverlay),
                    if (_showLegend) _buildLegend(),
                  ],
                ),
              ),
              if (_isCropMode) _buildCropOverlay(),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildCropOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          // Background Dim
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.5),
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                Container(decoration: const BoxDecoration(color: Colors.black)),
                Positioned(
                  left: _cropRect.left,
                  top: _cropRect.top,
                  child: Container(
                    width: _cropRect.width,
                    height: _cropRect.height,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Draggable handles
          Positioned(
            left: _cropRect.left,
            top: _cropRect.top,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _cropRect = Rect.fromLTWH(
                    _cropRect.left + details.delta.dx,
                    _cropRect.top + details.delta.dy,
                    _cropRect.width,
                    _cropRect.height,
                  );
                });
              },
              child: Container(
                width: _cropRect.width,
                height: _cropRect.height,
                decoration: BoxDecoration(
                  border: Border.all(color: colorOutgoing, width: 2),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            _cropRect = Rect.fromLTWH(
                              _cropRect.left,
                              _cropRect.top,
                              max(50, _cropRect.width + details.delta.dx),
                              max(50, _cropRect.height + details.delta.dy),
                            );
                          });
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          color: colorOutgoing,
                          child: const Icon(Icons.open_in_full,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                    const Center(
                      child: Text(
                        'Kéo để di chuyển / Resize góc dưới',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(blurRadius: 4)]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // CONTROL PANEL
  // =========================================================================
  Widget _buildControlPanel() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(2, 0)),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Lịch trình của bạn',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800)),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Chọn vùng xuất ảnh',
                    icon: Icon(Icons.crop,
                        color: _isCropMode ? colorOutgoing : Colors.grey),
                    onPressed: () => setState(() => _isCropMode = !_isCropMode),
                  ),
                  IconButton(
                    tooltip: 'Xuất ảnh bản đồ',
                    icon: const Icon(Icons.download, color: colorOutgoing),
                    onPressed: _exportMap,
                  ),
                ],
              )
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
          child: Column(
            children: [
              Row(
                children: [
                  Text("Hiển thị chú thích",
                      style:
                          TextStyle(fontSize: 14, color: Colors.grey.shade700)),
                  const Spacer(),
                  Switch(
                      value: _showLegend,
                      onChanged: (v) => setState(() => _showLegend = v),
                      activeColor: colorOutgoing)
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _insertImageOverlay,
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('Chèn ảnh'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _insertTextOverlay,
                      icon: const Icon(Icons.text_fields, size: 18),
                      label: const Text('Chèn text'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _generateLegend,
                  icon: const Icon(Icons.auto_awesome_motion, size: 18),
                  label: const Text('Generate chú thích'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorOutgoing,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // --- Input Area ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Start Input
                _buildInputRow(
                    icon: Icons.trip_origin,
                    iconColor: Colors.blue,
                    hint: 'Điểm xuất phát...',
                    ctrl: _startCtrl,
                    focus: _startFocus,
                    onChanged: _onStartChanged,
                    suggestions: _startSuggestions,
                    onSelect: (city) {
                      setState(() {
                        _startCtrl.text = _capitalize(city);
                        _startSuggestions.clear();
                      });
                      _endFocus.requestFocus();
                    }),
                const Padding(
                  padding: EdgeInsets.only(left: 7, top: 4, bottom: 4),
                  child: Icon(Icons.more_vert, size: 16, color: Colors.black38),
                ),
                // End Input
                _buildInputRow(
                    icon: Icons.location_on,
                    iconColor: Colors.red,
                    hint: 'Điểm đến...',
                    ctrl: _endCtrl,
                    focus: _endFocus,
                    onChanged: _onEndChanged,
                    suggestions: _endSuggestions,
                    onSelect: (city) {
                      setState(() {
                        _endCtrl.text = _capitalize(city);
                        _endSuggestions.clear();
                      });
                      _addRoute();
                    }),

                if (_errorMessage != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_errorMessage!,
                          style: const TextStyle(
                              color: Color(0xFFDC2626), fontSize: 12))),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _addRoute,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Thêm tuyến đường'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: colorOutgoing,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),
        const Divider(height: 1),

        // --- Scrollable Route Cards ---
        Expanded(
          child: _routes.isEmpty
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.map_outlined,
                            size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('Tạo tuyến đường\nđể bắt đầu hiển thị bản đồ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey.shade400)),
                      ])))
              : ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  children: [
                      Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                          child: Text('Danh sách tuyến đường',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade700))),
                      ..._routes
                          .asMap()
                          .entries
                          .map((e) => _buildRouteCard(e.key)),
                    ]),
        ),

        if (_routes.isNotEmpty)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _routes.clear();
                    _expandedRouteIndex = -1;
                  }),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Xóa tất cả'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
              )),
      ]),
    );
  }

  Widget _buildInputRow({
    required IconData icon,
    required Color iconColor,
    required String hint,
    required TextEditingController ctrl,
    required FocusNode focus,
    required Function(String) onChanged,
    required List<String> suggestions,
    required Function(String) onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: ctrl,
              focusNode: focus,
              onChanged: onChanged,
              onSubmitted: (_) => _addRoute(),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        const BorderSide(color: colorOutgoing, width: 1.5)),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ]),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6, left: 26),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2))
                ]),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: suggestions
                  .map((city) => InkWell(
                        onTap: () => onSelect(city),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(children: [
                              Icon(Icons.place,
                                  size: 14, color: Colors.grey.shade500),
                              const SizedBox(width: 8),
                              Text(_capitalize(city),
                                  style: const TextStyle(fontSize: 13))
                            ])),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _colorPickerBtn(
      String label, Color currentColor, Function(Color) onSelect) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 4),
        PopupMenuButton<Color>(
          onSelected: onSelect,
          tooltip: 'Đổi màu',
          itemBuilder: (context) => _presetColors
              .map((c) => PopupMenuItem(
                    value: c,
                    child: Container(
                        width: 24,
                        height: 24,
                        color: c,
                        margin: const EdgeInsets.only(bottom: 4)),
                  ))
              .toList(),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
                color: currentColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade400)),
          ),
        ),
      ],
    );
  }

  Widget _posPickerBtn(
      String label, String currentPos, Function(String) onSelect) {
    IconData getIcon(String pos) {
      if (pos == 'top') return Icons.arrow_upward;
      if (pos == 'bottom') return Icons.arrow_downward;
      if (pos == 'left') return Icons.arrow_back;
      return Icons.arrow_forward;
    }

    return Column(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 4),
        PopupMenuButton<String>(
          onSelected: onSelect,
          tooltip: 'Chọn vị trí',
          itemBuilder: (context) => ['top', 'bottom', 'left', 'right']
              .map((p) => PopupMenuItem(
                    value: p,
                    child: Row(children: [
                      Icon(getIcon(p), size: 16),
                      const SizedBox(width: 8),
                      Text(p.toUpperCase())
                    ]),
                  ))
              .toList(),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade300)),
            child: Icon(getIcon(currentPos), size: 16, color: Colors.black87),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // ROUTE CARD
  // =========================================================================
  Widget _buildRouteCard(int index) {
    final seg = _routes[index];
    final isExpanded = _expandedRouteIndex == index;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: isExpanded ? colorOutgoing : Colors.grey.shade200)),
      elevation: isExpanded ? 2 : 0,
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () =>
              setState(() => _expandedRouteIndex = isExpanded ? -1 : index),
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                        color: colorOutgoing, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('${seg.startCity.name} ➔ ${seg.endCity.name}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis)),

                // Nút xóa tuyến
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon:
                      Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                  onPressed: () => _removeRoute(index),
                ),
                const SizedBox(width: 8),
                Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20, color: Colors.grey.shade500),
              ])),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Return Route Toggle
              Row(
                children: [
                  Text('Thêm tuyến về (màu hồng)',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700)),
                  const Spacer(),
                  Switch(
                    value: seg.hasReturnRoute,
                    onChanged: (v) => setState(() => seg.hasReturnRoute = v),
                    activeColor: colorReturn,
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Line style
              Text('Kiểu nét',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600)),
              const SizedBox(height: 6),
              Row(children: [
                _styleButton('Nét liền', seg.lineStyle == LineStyle.solid,
                    () => setState(() => seg.lineStyle = LineStyle.solid)),
                const SizedBox(width: 8),
                _styleButton('Nét đứt', seg.lineStyle == LineStyle.dashed,
                    () => setState(() => seg.lineStyle = LineStyle.dashed)),
              ]),
              const SizedBox(height: 12),
              // Label
              Text('Ghi chú',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600)),
              const SizedBox(height: 6),
              TextField(
                controller: TextEditingController(text: seg.label ?? ''),
                onChanged: (v) => seg.label = v.isEmpty ? null : v,
                decoration: InputDecoration(
                  hintText: 'VD: 1h30 bay',
                  hintStyle:
                      TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _formatButton('B', Icons.format_bold, seg.isLabelBold,
                      () => setState(() => seg.isLabelBold = !seg.isLabelBold)),
                  const SizedBox(width: 8),
                  _formatButton(
                      'I',
                      Icons.format_italic,
                      seg.isLabelItalic,
                      () => setState(
                          () => seg.isLabelItalic = !seg.isLabelItalic)),
                ],
              ),
              const SizedBox(height: 12),
              // Transport icon
              Text('Phương tiện',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600)),
              const SizedBox(height: 6),
              Wrap(
                  spacing: 6,
                  children: TransportMode.values
                      .where((m) => m != TransportMode.none)
                      .map((mode) {
                    final isActive = seg.transportMode == mode;
                    return GestureDetector(
                      onTap: () => setState(() => seg.transportMode =
                          isActive ? TransportMode.none : mode),
                      child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                              color: isActive
                                  ? colorOutgoing.withOpacity(0.15)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: isActive
                                  ? Border.all(color: colorOutgoing, width: 2)
                                  : null),
                          child: Icon(transportIconData(mode),
                              size: 18,
                              color: isActive
                                  ? colorOutgoing
                                  : Colors.grey.shade500)),
                    );
                  }).toList()),
              const SizedBox(height: 12),
              // Sliders for Position and Sizes
              Text('Vị trí ghi chú',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600)),
              Slider(
                value: seg.labelPosition,
                min: 0.05,
                max: 0.95,
                activeColor: colorOutgoing,
                onChanged: (v) => setState(() => seg.labelPosition = v),
              ),

              Text('Cỡ chữ',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600)),
              Slider(
                value: seg.labelSize,
                min: 8.0,
                max: 24.0,
                divisions: 16,
                activeColor: colorOutgoing,
                onChanged: (v) => setState(() => seg.labelSize = v),
              ),

              Text('Cỡ Icon',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600)),
              Slider(
                value: seg.iconSize,
                min: 14.0,
                max: 36.0,
                divisions: 22,
                activeColor: colorOutgoing,
                onChanged: (v) => setState(() => seg.iconSize = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Đảo vị trí Icon/Chữ',
                      style: TextStyle(fontSize: 12)),
                  Switch(
                    value: seg.swapLabelIcon,
                    onChanged: (v) => setState(() => seg.swapLabelIcon = v),
                    activeColor: colorOutgoing,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Tùy chỉnh Điểm dừng (Marker)',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600)),
              Row(
                children: [
                  Text('Kiểu marker: ',
                      style: const TextStyle(fontSize: 12)),
                  Expanded(
                    child: SegmentedButton<MarkerStyle>(
                      segments: const [
                        ButtonSegment(value: MarkerStyle.solid, label: Text('Đơn')),
                        ButtonSegment(value: MarkerStyle.halfBlueRed, label: Text('Nửa')),
                      ],
                      selected: <MarkerStyle>{seg.markerStyle},
                      onSelectionChanged: (Set<MarkerStyle> newSelection) {
                        setState(() => seg.markerStyle = newSelection.first);
                      },
                      style: ButtonStyle(
                        backgroundColor: MaterialStateProperty.resolveWith<Color?>(
                          (Set<MaterialState> states) {
                            if (states.contains(MaterialState.selected)) {
                              return const Color(0xFFF0FDF4);
                            }
                            return Colors.grey.shade100;
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Cỡ điểm: ${seg.markerSize.toInt()}  ',
                      style: const TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: seg.markerSize,
                      min: 10,
                      max: 40,
                      activeColor: colorOutgoing,
                      onChanged: (v) => setState(() => seg.markerSize = v),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text('Cỡ chữ: ${seg.markerTextSize.toInt()}  ',
                      style: const TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: seg.markerTextSize,
                      min: 8,
                      max: 20,
                      divisions: 12,
                      activeColor: colorOutgoing,
                      onChanged: (v) => setState(() => seg.markerTextSize = v),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  _colorPickerBtn('Màu đi', seg.startColor,
                      (c) => setState(() => seg.startColor = c)),
                  const SizedBox(width: 8),
                  _posPickerBtn('Vị trí chữ', seg.startTextPos,
                      (p) => setState(() => seg.startTextPos = p)),
                  const SizedBox(width: 24),
                  _colorPickerBtn('Màu đến', seg.endColor,
                      (c) => setState(() => seg.endColor = c)),
                  const SizedBox(width: 8),
                  _posPickerBtn('Vị trí chữ', seg.endTextPos,
                      (p) => setState(() => seg.endTextPos = p)),
                ],
              ),
              Row(
                children: [
                  Row(children: [
                    Checkbox(
                        value: seg.showStartLabel,
                        onChanged: (v) =>
                            setState(() => seg.showStartLabel = v!),
                        activeColor: colorOutgoing),
                    const Text('Hiện tên đi', style: TextStyle(fontSize: 11)),
                  ]),
                  const SizedBox(width: 16),
                  Row(children: [
                    Checkbox(
                        value: seg.showEndLabel,
                        onChanged: (v) => setState(() => seg.showEndLabel = v!),
                        activeColor: colorOutgoing),
                    const Text('Hiện tên đến', style: TextStyle(fontSize: 11)),
                  ]),
                ],
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: seg.hasCustomMarkerPosition
                      ? () => setState(() => seg.resetMarkerPositions())
                      : null,
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text('Đặt lại vị trí marker'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorOutgoing,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _styleButton(String text, bool active, VoidCallback onTap) {
    return Expanded(
        child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
            color: active ? const Color(0xFFF0FDF4) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: active ? colorOutgoing : Colors.grey.shade300,
                width: active ? 2 : 1)),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? colorOutgoing : Colors.grey.shade600)),
      ),
    ));
  }

  Widget _formatButton(
      String label, IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 32,
        decoration: BoxDecoration(
          color:
              active ? colorOutgoing.withOpacity(0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: active
              ? Border.all(color: colorOutgoing, width: 1.5)
              : Border.all(color: Colors.grey.shade300),
        ),
        child: Icon(icon,
            size: 18, color: active ? colorOutgoing : Colors.grey.shade600),
      ),
    );
  }

  Widget _buildImageOverlay(MapImageOverlay overlay) {
    final isActive = _activeOverlayId == overlay.id;
    return _buildResizableOverlay(
      id: overlay.id,
      position: overlay.position,
      size: overlay.size,
      onMove: (delta) => setState(() => overlay.position += delta),
      onResize: (delta) => setState(() {
        overlay.size = Size(
          max(48, overlay.size.width + delta.dx),
          max(32, overlay.size.height + delta.dy),
        );
      }),
      onDelete: () => setState(() => _imageOverlays.remove(overlay)),
      showControls: isActive,
      child: Image.memory(
        overlay.bytes,
        width: overlay.size.width,
        height: overlay.size.height,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildTextOverlay(MapTextOverlay overlay) {
    final isActive = _activeOverlayId == overlay.id;
    return _buildResizableOverlay(
      id: overlay.id,
      position: overlay.position,
      size: overlay.size,
      onMove: (delta) => setState(() => overlay.position += delta),
      onResize: (delta) => setState(() {
        overlay.size = Size(
          max(60, overlay.size.width + delta.dx),
          max(28, overlay.size.height + delta.dy),
        );
      }),
      onDelete: () => setState(() => _textOverlays.remove(overlay)),
      onDoubleTap: () => _editTextOverlay(overlay),
      showControls: isActive,
      child: SizedBox(
        width: overlay.size.width,
        height: overlay.size.height,
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.center,
          child: Text(
            overlay.text,
            textAlign: overlay.textAlign,
            style: TextStyle(
              color: overlay.color,
              fontSize: overlay.fontSize,
              fontWeight: overlay.isBold ? FontWeight.w800 : FontWeight.w500,
              fontStyle: overlay.isItalic ? FontStyle.italic : FontStyle.normal,
              shadows: [
                Shadow(color: Colors.white.withOpacity(0.8), blurRadius: 4),
                Shadow(color: Colors.white.withOpacity(0.8), blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResizableOverlay({
    required String id,
    required Offset position,
    required Size size,
    required Widget child,
    required ValueChanged<Offset> onMove,
    required ValueChanged<Offset> onResize,
    required VoidCallback onDelete,
    required bool showControls,
    VoidCallback? onDoubleTap,
  }) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        onEnter: (_) => setState(() => _activeOverlayId = id),
        onExit: (_) => setState(() => _activeOverlayId = null),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanUpdate: (details) => onMove(details.delta),
          onDoubleTap: onDoubleTap,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: child),
                if (showControls)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: colorOutgoing.withOpacity(0.55),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showControls)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: onDelete,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 4)
                          ],
                        ),
                        child: const Icon(Icons.close, size: 16),
                      ),
                    ),
                  ),
                if (showControls)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: GestureDetector(
                        onPanUpdate: (details) => onResize(details.delta),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4)
                            ],
                          ),
                          child: const Icon(Icons.open_in_full, size: 14),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editTextOverlay(MapTextOverlay overlay) async {
    final controller = TextEditingController(text: overlay.text);
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Sửa chữ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Nội dung',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => overlay.text = v),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Màu: '),
                    ..._presetColors.map((c) => GestureDetector(
                          onTap: () {
                            setDialogState(() => overlay.color = c);
                            setState(() {});
                          },
                          child: Container(
                            width: 24,
                            height: 24,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: overlay.color == c
                                    ? Colors.black
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                        )),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Cỡ chữ: '),
                    Expanded(
                      child: Slider(
                        value: overlay.fontSize,
                        min: 8,
                        max: 72,
                        onChanged: (v) {
                          setDialogState(() => overlay.fontSize = v);
                          setState(() {});
                        },
                      ),
                    ),
                    Text(overlay.fontSize.toInt().toString()),
                  ],
                ),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('Đậm'),
                      selected: overlay.isBold,
                      onSelected: (v) {
                        setDialogState(() => overlay.isBold = v);
                        setState(() {});
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Nghiêng'),
                      selected: overlay.isItalic,
                      onSelected: (v) {
                        setDialogState(() => overlay.isItalic = v);
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Align(
                    alignment: Alignment.centerLeft, child: Text('Căn lề:')),
                const SizedBox(height: 8),
                ToggleButtons(
                  isSelected: [
                    overlay.textAlign == TextAlign.left,
                    overlay.textAlign == TextAlign.center,
                    overlay.textAlign == TextAlign.right,
                  ],
                  onPressed: (index) {
                    setDialogState(() {
                      overlay.textAlign = [
                        TextAlign.left,
                        TextAlign.center,
                        TextAlign.right
                      ][index];
                    });
                    setState(() {});
                  },
                  borderRadius: BorderRadius.circular(8),
                  children: const [
                    Icon(Icons.format_align_left),
                    Icon(Icons.format_align_center),
                    Icon(Icons.format_align_right),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Xong'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  // =========================================================================
  // LEGEND BOX
  // =========================================================================
  Widget _buildLegend() {
    return Positioned(
      left: _legendPos.dx,
      top: _legendPos.dy,
      child: GestureDetector(
        onPanUpdate: (details) => setState(() => _legendPos += details.delta),
        child: Transform.scale(
          scale: _legendScale,
          alignment: Alignment.topLeft,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
              ],
            ),
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 4),
                  _buildLegendCircle(Colors.blue, 'Starting point'),
                  const SizedBox(height: 8),
                  _buildLegendCircle(Colors.red, 'Ending point'),
                  const SizedBox(height: 8),
                  _buildLegendLine(colorOutgoing, 'Route'),
                  const SizedBox(height: 8),
                  _buildLegendLine(colorReturn, 'Route back'),
                  for (final mode in _legendTransportModes) ...[
                    const SizedBox(height: 8),
                    _buildLegendItem(
                        transportIconData(mode), _transportLegendLabel(mode)),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            _legendScale += details.delta.dx * 0.005;
                            if (_legendScale < 0.5) _legendScale = 0.5;
                            if (_legendScale > 2.0) _legendScale = 2.0;
                          });
                        },
                        child: const Icon(Icons.open_with,
                            size: 16, color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _transportLegendLabel(TransportMode mode) {
    switch (mode) {
      case TransportMode.plane:
        return 'Plane';
      case TransportMode.car:
        return 'Private Car';
      case TransportMode.motorcycle:
        return 'Motorcycle';
      case TransportMode.bus:
        return 'Shuttle bus';
      case TransportMode.train:
        return 'Train';
      case TransportMode.walking:
        return 'Walking';
      case TransportMode.none:
        return '';
    }
  }

  Widget _buildLegendItem(IconData icon, String label) {
    return Row(children: [
      Icon(icon, size: 18, color: Colors.grey.shade800),
      const SizedBox(width: 10),
      Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    ]);
  }

  Widget _buildLegendCircle(Color borderColor, String label) {
    return Row(children: [
      Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 3)),
      ),
      const SizedBox(width: 10),
      Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    ]);
  }

  Widget _buildLegendLine(Color color, String label) {
    return Row(children: [
      Container(
        width: 18,
        height: 3,
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 10),
      Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    ]);
  }

  // =========================================================================
  // MAP
  // =========================================================================
  Widget _buildMap() {
    return Container(
      key: _mapKey,
      color: const Color(0xFFE8F4FD),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: LatLng(15.4, 106.8),
          initialZoom: 5.1,
          minZoom: 3.6,
          maxZoom: 10,
          backgroundColor: const Color(0xFFE8F4FD),
        ),
        children: [
          PolygonLayer(
            polygons: _buildCountryPolygons(),
          ),
          PolygonLayer(
            polygons: _disputedIslandRings
                .map((ring) => Polygon(
                      points: ring,
                      color: const Color(0xFFFDE68A),
                      borderColor: const Color(0xFFEAB308),
                      borderStrokeWidth: 1.2,
                      isFilled: true,
                    ))
                .toList(),
          ),
          PolylineLayer(polylines: _buildRoutePolylines()),
          MarkerLayer(markers: _buildRouteLabelMarkers()),
          MarkerLayer(markers: _buildMapMarkers()),
        ],
      ),
    );
  }

  List<Polygon> _buildCountryPolygons() {
    final polygons = <Polygon>[];
    for (final country in _countryBoundaries) {
      final code = country.code;
      Color color = const Color(0xFFE7E5E4); // Default Grey
      Color borderColor = const Color(0xFFD6D3D1);
      double strokeWidth = 1.0;

      if (code == 'VNM') {
        color = const Color(0xFFFDE68A); // Yellow
        borderColor = const Color(0xFFEAB308);
        strokeWidth = 1.2;
      } else if (code == 'LAO') {
        color = const Color(0xFFBAE6FD); // Light Blue
        borderColor = const Color(0xFF38BDF8);
      } else if (code == 'KHM') {
        color = const Color(0xFFFBCFE8); // Light Pink
        borderColor = const Color(0xFFF472B6);
      }

      for (final ring in country.rings) {
        polygons.add(Polygon(
          points: ring,
          color: color,
          borderColor: borderColor,
          borderStrokeWidth: strokeWidth,
          isFilled: true,
        ));
      }
    }
    return polygons;
  }

  List<Marker> _buildMapMarkers() {
    final markers = <Marker>[];
    for (int i = 0; i < _routes.length; i++) {
      final seg = _routes[i];
      markers.add(_createCityMarker(
        waypoint: seg.startCity,
        position: seg.effectiveStartPosition,
        borderColor: seg.startColor,
        size: seg.markerSize,
        textSize: seg.markerTextSize,
        textPos: seg.startTextPos,
        showLabel: seg.showStartLabel,
        onDrag: (details) => _onCityMarkerDrag(details, i, true),
      ));
      markers.add(_createCityMarker(
        waypoint: seg.endCity,
        position: seg.effectiveEndPosition,
        borderColor: seg.endColor,
        size: seg.markerSize,
        textSize: seg.markerTextSize,
        textPos: seg.endTextPos,
        showLabel: seg.showEndLabel,
        onDrag: (details) => _onCityMarkerDrag(details, i, false),
      ));
    }
    return markers;
  }

  Marker _createCityMarker({
    required Waypoint waypoint,
    required LatLng position,
    required Color borderColor,
    required double size,
    required double textSize,
    required String textPos,
    required bool showLabel,
    required GestureDragUpdateCallback onDrag,
  }) {
    Widget textWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(waypoint.name,
            style: TextStyle(
                color: Colors.black,
                fontSize: textSize,
                fontWeight: FontWeight.w800,
                shadows: const [
                  Shadow(color: Colors.white, blurRadius: 4),
                  Shadow(color: Colors.white, blurRadius: 4)
                ])));

    // Find the route segment to get marker style
    final seg = _routes.firstWhere((r) => r.startCity.name == waypoint.name || r.endCity.name == waypoint.name, orElse: () => _routes.first);
    
    Widget iconWidget;
    if (seg.markerStyle == MarkerStyle.halfBlueRed) {
      // White circle with half blue (left) and half red (right) border
      iconWidget = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
          ],
        ),
        child: Stack(
          children: [
            // Left half - Blue border
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: size / 2,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(size / 2),
                    bottomLeft: Radius.circular(size / 2),
                  ),
                  border: Border(
                    left: BorderSide(color: Colors.blue, width: 4),
                    top: BorderSide(color: Colors.blue, width: 4),
                    bottom: BorderSide(color: Colors.blue, width: 4),
                  ),
                ),
              ),
            ),
            // Right half - Red border
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: size / 2,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(size / 2),
                    bottomRight: Radius.circular(size / 2),
                  ),
                  border: Border(
                    right: BorderSide(color: Colors.red, width: 4),
                    top: BorderSide(color: Colors.red, width: 4),
                    bottom: BorderSide(color: Colors.red, width: 4),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Original solid circle
      iconWidget = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 4),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
          ],
        ),
      );
    }

    return Marker(
        point: position,
        width: 150,
        height: 150,
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: onDrag,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (showLabel)
                  Positioned(
                    top: textPos == 'bottom'
                        ? 75 + (size / 2) + 2
                        : (textPos == 'left' || textPos == 'right' ? 0 : null),
                    bottom: textPos == 'top'
                        ? 75 + (size / 2) + 2
                        : (textPos == 'left' || textPos == 'right' ? 0 : null),
                    left: textPos == 'right'
                        ? 75 + (size / 2) + 2
                        : (textPos == 'top' || textPos == 'bottom' ? 0 : null),
                    right: textPos == 'left'
                        ? 75 + (size / 2) + 2
                        : (textPos == 'top' || textPos == 'bottom' ? 0 : null),
                    child: Center(child: textWidget),
                  ),
                iconWidget,
              ],
            ),
          ),
        ));
  }

  void _onCityMarkerDrag(
      DragUpdateDetails details, int segIndex, bool isStart) {
    final mapBox = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (mapBox == null) return;
    final localPos = mapBox.globalToLocal(details.globalPosition);
    try {
      final latLng =
          _mapController.camera.pointToLatLng(Point(localPos.dx, localPos.dy));
      setState(() {
        final seg = _routes[segIndex];
        if (isStart) {
          seg.customStartPosition = latLng;
        } else {
          seg.customEndPosition = latLng;
        }
      });
    } catch (_) {}
  }

  // =========================================================================
  // ROUTE POLYLINES
  // =========================================================================
  List<Polyline> _buildRoutePolylines() {
    if (_routes.isEmpty) return [];
    final lines = <Polyline>[];
    for (var seg in _routes) {
      final start = seg.effectiveStartPosition;
      final end = seg.effectiveEndPosition;

      lines.add(Polyline(
        points: _generateArc(start, end, -0.3, segments: 50),
        color: colorOutgoing,
        strokeWidth: 3,
        isDotted: seg.lineStyle == LineStyle.dashed,
      ));

      if (seg.hasReturnRoute) {
        lines.add(Polyline(
          points: _generateArc(start, end, 0.3, segments: 50),
          color: colorReturn,
          strokeWidth: 3,
          isDotted: seg.lineStyle == LineStyle.dashed,
        ));
      }
    }
    return lines;
  }

  // =========================================================================
  // ROUTE LABEL MARKERS
  // =========================================================================
  List<Marker> _buildRouteLabelMarkers() {
    final markers = <Marker>[];
    for (int i = 0; i < _routes.length; i++) {
      final seg = _routes[i];
      final hasLabel = seg.label != null && seg.label!.isNotEmpty;
      final hasIcon = seg.transportMode != TransportMode.none;
      if (!hasLabel && !hasIcon) continue;

      final start = seg.effectiveStartPosition;
      final end = seg.effectiveEndPosition;

      markers.add(_createTransparentLabelMarker(
          start, end, -0.3, seg, colorOutgoing, i));
    }
    return markers;
  }

  Marker _createTransparentLabelMarker(LatLng start, LatLng end,
      double curveScale, RouteSegment seg, Color color, int segIndex) {
    final t = seg.labelPosition;
    final pos = _bezierPoint(start, end, curveScale, t);

    final p0 = _bezierPoint(start, end, curveScale, (t - 0.01).clamp(0.0, 1.0));
    final p1 = _bezierPoint(start, end, curveScale, (t + 0.01).clamp(0.0, 1.0));
    final dx = p1.longitude - p0.longitude;
    final dy = p1.latitude - p0.latitude;

    double screenAngle = atan2(-dy, dx);
    bool flip = dx < 0;
    if (flip) screenAngle += pi;

    return Marker(
      point: pos,
      width: 160,
      height: 80,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => _onLabelDrag(details, segIndex, curveScale),
        child: Center(
          child: Transform.rotate(
            angle: screenAngle,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (seg.label != null && seg.label!.isNotEmpty)
                  Positioned(
                    top: seg.swapLabelIcon ? null : 44,
                    bottom: seg.swapLabelIcon ? 44 : null,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(seg.label!,
                          style: TextStyle(
                              fontSize: seg.labelSize,
                              fontWeight: seg.isLabelBold
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              fontStyle: seg.isLabelItalic
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              color: Colors.black,
                              shadows: const [
                                Shadow(color: Colors.white, blurRadius: 4),
                                Shadow(color: Colors.white, blurRadius: 4)
                              ])),
                    ),
                  ),
                if (seg.transportMode != TransportMode.none)
                  Positioned(
                    top: seg.swapLabelIcon ? 44 : null,
                    bottom: seg.swapLabelIcon ? null : 44,
                    left: 0,
                    right: 0,
                    child: Center(
                        child: Container(
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.white.withOpacity(0.8),
                                blurRadius: 8,
                                spreadRadius: 2)
                          ]),
                      child: Icon(transportIconData(seg.transportMode),
                          size: seg.iconSize, color: Colors.black),
                    )),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onLabelDrag(
      DragUpdateDetails details, int segIndex, double curveScale) {
    final mapBox = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (mapBox == null) return;
    final localPos = mapBox.globalToLocal(details.globalPosition);
    try {
      final latLng =
          _mapController.camera.pointToLatLng(Point(localPos.dx, localPos.dy));
      final start = _routes[segIndex].effectiveStartPosition;
      final end = _routes[segIndex].effectiveEndPosition;
      final newT = _findClosestT(start, end, curveScale, latLng);
      setState(() => _routes[segIndex].labelPosition = newT);
    } catch (_) {}
  }

  double _findClosestT(
      LatLng start, LatLng end, double curveScale, LatLng target) {
    double bestT = 0.5, bestDist = double.infinity;
    for (int i = 0; i <= 200; i++) {
      final t = i / 200.0;
      final pt = _bezierPoint(start, end, curveScale, t);
      final d = _distSq(pt, target);
      if (d < bestDist) {
        bestDist = d;
        bestT = t;
      }
    }
    return bestT.clamp(0.05, 0.95);
  }

  double _distSq(LatLng a, LatLng b) {
    final dlat = a.latitude - b.latitude;
    final dlng = a.longitude - b.longitude;
    return dlat * dlat + dlng * dlng;
  }

  // =========================================================================
  // BEZIER HELPERS
  // =========================================================================
  LatLng _bezierPoint(LatLng start, LatLng end, double curveScale, double t) {
    final dx = end.longitude - start.longitude;
    final dy = end.latitude - start.latitude;
    final distance = sqrt(dx * dx + dy * dy);
    if (distance < 1e-9) return start;
    final midLat = (start.latitude + end.latitude) / 2;
    final midLng = (start.longitude + end.longitude) / 2;

    final perpScale = distance * curveScale;
    final cLat = midLat + (-dx / distance) * perpScale;
    final cLng = midLng + (dy / distance) * perpScale;

    final omt = 1 - t;
    return LatLng(
      omt * omt * start.latitude + 2 * omt * t * cLat + t * t * end.latitude,
      omt * omt * start.longitude + 2 * omt * t * cLng + t * t * end.longitude,
    );
  }

  List<LatLng> _generateArc(LatLng start, LatLng end, double curveScale,
      {int segments = 50}) {
    return List.generate(segments + 1,
        (i) => _bezierPoint(start, end, curveScale, i / segments));
  }
}
