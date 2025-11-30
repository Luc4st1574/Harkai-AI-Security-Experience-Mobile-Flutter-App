import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:harkai/core/models/geofence_model.dart';
import 'package:harkai/core/managers/download_data_manager.dart';
import 'package:harkai/features/home/utils/incidences.dart';

// Define a type for the callback function for better readability.
typedef NotificationCallback = void Function(
    IncidenceData incident, double distance);

class GeofenceManager {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DownloadDataManager _downloadDataManager;
  final NotificationCallback onNotificationTrigger;

  List<GeofenceModel> _incidents = [];
  final Set<String> _activeGeofences = {};

  // NEW: Store the last known position to allow immediate checks when data arrives
  Position? _lastKnownPosition;

  GeofenceManager(this._downloadDataManager,
      {required this.onNotificationTrigger});

  Future<void> initialize() async {
    await _downloadDataManager.fetchAndCacheAllIncidents();
    _incidents = await _downloadDataManager.getCachedIncidents();
    debugPrint(
        "GeofenceManager initialized with ${_incidents.length} incidents from cache.");
  }

  /// Called by the Background Service when a new/modified incident comes from Firestore.
  void addOrUpdateIncident(GeofenceModel incident) {
    // 1. Handle visibility (remove if invisible)
    if (!incident.isVisible) {
      _incidents.removeWhere((i) => i.id == incident.id);
      _activeGeofences.remove(incident.id);
      debugPrint("GeofenceManager: Removed invisible incident: ${incident.id}");
      return;
    }

    // 2. Update the local list
    final index = _incidents.indexWhere((i) => i.id == incident.id);
    if (index != -1) {
      _incidents[index] = incident;
    } else {
      _incidents.add(incident);
    }
    debugPrint(
        "GeofenceManager: Incident list updated. Count: ${_incidents.length}");

    // 3. NEW: Check immediately if we should trigger a notification (don't wait for next GPS update)
    if (_lastKnownPosition != null) {
      _checkSingleIncident(incident, _lastKnownPosition!);
    }
  }

  void onLocationUpdate(Position position) {
    _lastKnownPosition = position; // Save for later use

    if (_incidents.isEmpty) return;

    // We clear the active list on every movement to re-evaluate ranges
    final Set<String> previouslyActiveGeofences = Set.from(_activeGeofences);
    _activeGeofences.clear();

    for (final geofence in _incidents) {
      if (!geofence.isVisible) continue;

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        geofence.latitude,
        geofence.longitude,
      );

      if (distance <= geofence.radius) {
        _activeGeofences.add(geofence.id);

        // Only notify if we weren't ALREADY active in this zone
        if (!previouslyActiveGeofences.contains(geofence.id)) {
          _onEnterGeofence(geofence, distance);
          onNotificationTrigger(_createIncidenceData(geofence), distance);
        }
      }
    }
  }

  // NEW: Helper to check just one incident against a position (used by real-time trigger)
  void _checkSingleIncident(GeofenceModel geofence, Position position) {
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      geofence.latitude,
      geofence.longitude,
    );

    if (distance <= geofence.radius) {
      // If we are already tracking this as active, don't spam notifications
      if (!_activeGeofences.contains(geofence.id)) {
        _activeGeofences.add(geofence.id);
        debugPrint(
            "GeofenceManager: IMMEDIATE TRIGGER for new incident ${geofence.id}");

        _onEnterGeofence(geofence, distance);
        onNotificationTrigger(_createIncidenceData(geofence), distance);
      }
    }
  }

  void _onEnterGeofence(GeofenceModel geofence, double distance) {
    debugPrint('Entering geofence: ${geofence.id} at distance: $distance');
    _writeGeofenceEvent('enter', geofence.id);
  }

  Future<void> _writeGeofenceEvent(String event, String geofenceId) async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _firestore.collection('geofence_events').add({
          'userId': user.uid,
          'geofenceId': geofenceId,
          'event': event,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Error writing geofence event: $e');
      }
    }
  }

  IncidenceData _createIncidenceData(GeofenceModel geofence) {
    return IncidenceData(
      id: geofence.id,
      latitude: geofence.latitude,
      longitude: geofence.longitude,
      type: geofence.type,
      description: geofence.description,
      timestamp: Timestamp.now(),
      isVisible: geofence.isVisible,
      userId: '',
    );
  }
}
