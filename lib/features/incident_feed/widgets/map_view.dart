// lib/features/incident_feed/widgets/map_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_google_maps_webservices/directions.dart'
    as gm_directions;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:harkai/features/home/utils/incidences.dart';
import 'package:harkai/features/home/utils/markers.dart';
import 'package:harkai/l10n/app_localizations.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:harkai/core/services/location_service.dart';
import 'package:geolocator/geolocator.dart';

class IncidentMapViewContent extends StatefulWidget {
  final IncidenceData incident;
  final MakerType incidentTypeForExpiry;

  const IncidentMapViewContent({
    super.key,
    required this.incident,
    required this.incidentTypeForExpiry,
  });

  @override
  State<IncidentMapViewContent> createState() => _IncidentMapViewContentState();
}

class _IncidentMapViewContentState extends State<IncidentMapViewContent> {
  // If .env fails, you can paste the key here as a fallback
  final String hardCodedKey = "";

  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  Set<Polyline> _polylines = {};
  bool _isIncidentVisible = true;
  Position? _currentUserPosition;

  AppLocalizations? _localizations;
  bool _dependenciesInitialized = false;
  final LocationService _locationService = LocationService();

  @override
  void initState() {
    super.initState();
    _checkIncidentVisibility();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_dependenciesInitialized) {
      _localizations = AppLocalizations.of(context)!;
      if (_isIncidentVisible) {
        _prepareMapElements();
        _fetchCurrentUserLocationAndRoute();
      }
      _dependenciesInitialized = true;
    }
  }

  void _checkIncidentVisibility() {
    if (widget.incidentTypeForExpiry == MakerType.place) {
      if (mounted) setState(() => _isIncidentVisible = true);
      return;
    }

    final now = DateTime.now();
    bool shouldBeVisible = true;

    if (widget.incidentTypeForExpiry == MakerType.pet ||
        widget.incidentTypeForExpiry == MakerType.event) {
      final twentyFourHoursAgo = now.subtract(const Duration(days: 1));
      if (widget.incident.timestamp.toDate().isBefore(twentyFourHoursAgo)) {
        shouldBeVisible = false;
      }
    } else {
      final threeHoursAgo = now.subtract(const Duration(hours: 3));
      if (widget.incident.timestamp.toDate().isBefore(threeHoursAgo)) {
        shouldBeVisible = false;
      }
    }

    if (mounted && _isIncidentVisible != shouldBeVisible) {
      setState(() => _isIncidentVisible = shouldBeVisible);
    }
  }

  void _prepareMapElements() {
    if (_localizations == null) return;
    final marker = createMarkerFromIncidence(widget.incident, _localizations!);
    final circle = createCircleFromIncidence(widget.incident, _localizations!);
    if (mounted) {
      setState(() {
        _markers = {marker};
        _circles = {circle};
      });
    }
  }

  Future<void> _fetchCurrentUserLocationAndRoute() async {
    // -------------------------------------------------------------
    // OPTIMIZATION: Check Last Known Position First (Instant)
    // -------------------------------------------------------------
    try {
      final lastKnownPosition = await Geolocator.getLastKnownPosition();
      if (lastKnownPosition != null) {
        if (mounted) {
          setState(() {
            _currentUserPosition = lastKnownPosition;
          });
          debugPrint("📍 MapView: Using Last Known Position (Fast).");
          _fetchAndDrawRoute(); // Draw route immediately
        }
        return; // Exit early to avoid waiting for fresh GPS
      }
    } catch (e) {
      debugPrint("⚠️ MapView: Could not get cached location: $e");
    }

    // Fallback: If no cached location, fetch fresh (slower)
    debugPrint("⏳ MapView: Fetching fresh GPS location...");
    final locationResult = await _locationService.getInitialPosition();

    if (locationResult.success && locationResult.data != null) {
      if (mounted) {
        setState(() {
          _currentUserPosition = locationResult.data;
        });
        debugPrint("📍 MapView: Fresh User location found.");
        _fetchAndDrawRoute();
      }
    } else {
      debugPrint(
          "❌ MapView: Could not get user's current location: ${locationResult.errorMessage}");
    }
  }

  Future<void> _fetchAndDrawRoute() async {
    if (_currentUserPosition == null) return;

    // Use 'GOOGLE_MAPS_API_KEY' to match your .env file
    String activeKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";

    if (activeKey.isEmpty) {
      activeKey = hardCodedKey;
    }

    if (activeKey.isEmpty) {
      debugPrint(
          "❌ MapView: API Key missing. Ensure GOOGLE_MAPS_API_KEY is in .env");
      return;
    }

    final gm_directions.GoogleMapsDirections directions =
        gm_directions.GoogleMapsDirections(apiKey: activeKey);

    final gm_directions.Location origin = gm_directions.Location(
        lat: _currentUserPosition!.latitude,
        lng: _currentUserPosition!.longitude);
    final gm_directions.Location destination = gm_directions.Location(
        lat: widget.incident.latitude, lng: widget.incident.longitude);

    try {
      debugPrint("⏳ MapView: Requesting directions...");
      gm_directions.DirectionsResponse response = await directions.directions(
        origin,
        destination,
        travelMode: gm_directions.TravelMode.driving,
      );

      if (response.isOkay && response.routes.isNotEmpty) {
        final gm_directions.Route route = response.routes.first;

        if (route.overviewPolyline.points.isNotEmpty) {
          // Decode Polyline (Static method in v3.1.0+)
          List<PointLatLng> decodedResult =
              PolylinePoints.decodePolyline(route.overviewPolyline.points);

          List<LatLng> polylineCoordinates = [];
          if (decodedResult.isNotEmpty) {
            for (var point in decodedResult) {
              polylineCoordinates.add(LatLng(point.latitude, point.longitude));
            }
          }

          if (polylineCoordinates.isNotEmpty) {
            final MarkerInfo? markerInfo =
                getMarkerInfo(widget.incident.type, _localizations!);
            final Color routeColor = markerInfo?.color ?? Colors.blueAccent;

            // Use withValues for new Flutter versions
            final Color colorWithAlpha = routeColor.withValues(alpha: 0.8);

            final Polyline polyline = Polyline(
              polylineId: const PolylineId('routeToIncident'),
              color: colorWithAlpha,
              width: 5,
              points: polylineCoordinates,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
              geodesic: true,
            );

            if (mounted) {
              setState(() {
                _polylines = {polyline};
              });
              debugPrint("✅ MapView: Polyline drawn successfully.");
            }
          }
        }
      } else {
        debugPrint(
            "❌ MapView: Directions API Error: ${response.errorMessage ?? response.status}");
      }
    } catch (e) {
      debugPrint("❌ MapView: Exception: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    _localizations ??= AppLocalizations.of(context)!;
    if (_localizations == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isIncidentVisible) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _localizations!.incidentMapViewIncidentExpired,
            style: const TextStyle(fontSize: 18, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return GoogleMap(
      mapType: MapType.normal,
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.incident.latitude, widget.incident.longitude),
        zoom: 14,
      ),
      markers: _markers,
      circles: _circles,
      polylines: _polylines,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: true,
    );
  }
}
