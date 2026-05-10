import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class Waypoint {
  final String name;
  final LatLng position;
  const Waypoint({required this.name, required this.position});
}

enum LineStyle { solid, dashed }

enum TransportMode { none, plane, car, motorcycle, bus, train, walking }

IconData transportIconData(TransportMode mode) {
  switch (mode) {
    case TransportMode.plane:
      return Icons.flight;
    case TransportMode.car:
      return Icons.directions_car;
    case TransportMode.motorcycle:
      return Icons.two_wheeler;
    case TransportMode.bus:
      return Icons.directions_bus;
    case TransportMode.train:
      return Icons.train;
    case TransportMode.walking:
      return Icons.directions_walk;
    case TransportMode.none:
      return Icons.remove;
  }
}

class RouteSegment {
  final String id;
  final Waypoint startCity;
  final Waypoint endCity;
  
  LineStyle lineStyle;
  TransportMode transportMode;
  String? label;
  double labelPosition; // 0.0 – 1.0 on the bezier curve
  bool hasReturnRoute;
  double labelSize;
  double iconSize;
  bool isLabelBold;
  bool isLabelItalic;
  double markerSize;
  double markerTextSize;
  String startTextPos;
  String endTextPos;
  Color startColor;
  Color endColor;
  bool swapLabelIcon;
  bool showStartLabel;
  bool showEndLabel;

  RouteSegment({
    required this.id,
    required this.startCity,
    required this.endCity,
    this.lineStyle = LineStyle.solid,
    this.transportMode = TransportMode.none,
    this.label,
    this.labelPosition = 0.5,
    this.hasReturnRoute = false,
    this.labelSize = 13.0,
    this.iconSize = 18.0,
    this.isLabelBold = false,
    this.isLabelItalic = false,
    this.markerSize = 16.0,
    this.markerTextSize = 11.0,
    this.startTextPos = 'bottom',
    this.endTextPos = 'bottom',
    this.startColor = Colors.blue,
    this.endColor = Colors.red,
    this.swapLabelIcon = false,
    this.showStartLabel = true,
    this.showEndLabel = true,
  });
}
