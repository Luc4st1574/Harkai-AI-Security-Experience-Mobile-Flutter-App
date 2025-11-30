import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:harkai/core/models/geofence_model.dart';
import 'package:harkai/features/home/utils/incidences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadDataManager {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();
  static const String _incidentCacheKey = 'incident_cache';

  Future<void> fetchAndCacheAllIncidents() async {
    try {
      final querySnapshot = await _firestore.collection('HeatPoints').get();

      final incidents = querySnapshot.docs
          .map((doc) => GeofenceModel.fromFirestore(doc))
          .toList();

      final prefs = await SharedPreferences.getInstance();
      final incidentsJson =
          jsonEncode(incidents.map((i) => i.toMap()).toList());
      await prefs.setString(_incidentCacheKey, incidentsJson);

      debugPrint('Downloaded and cached ${incidents.length} total incidents.');
    } catch (e) {
      debugPrint('Error fetching and caching all incidents: $e');
    }
  }

  /// Updates the cache with a single incident without re-downloading everything.
  /// Used by the background service when a real-time trigger fires.
  Future<void> updateCacheWith(GeofenceModel incident) async {
    try {
      final cachedIncidents = await getCachedIncidents();

      // Check if incident exists
      final index = cachedIncidents.indexWhere((i) => i.id == incident.id);

      if (index != -1) {
        // Update existing
        cachedIncidents[index] = incident;
      } else {
        // Add new
        cachedIncidents.add(incident);
      }

      // Save back to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final incidentsJson =
          jsonEncode(cachedIncidents.map((i) => i.toMap()).toList());
      await prefs.setString(_incidentCacheKey, incidentsJson);

      debugPrint("DownloadDataManager: Single incident cached: ${incident.id}");
    } catch (e) {
      debugPrint(
          "DownloadDataManager: Error updating cache with single incident: $e");
    }
  }

  Future<List<GeofenceModel>> getCachedIncidents() async {
    final prefs = await SharedPreferences.getInstance();
    final incidentsJson = prefs.getString(_incidentCacheKey);
    if (incidentsJson != null) {
      final List<dynamic> incidentList = jsonDecode(incidentsJson);
      return incidentList.map((map) => GeofenceModel.fromMap(map)).toList();
    }
    return [];
  }

  Future<void> cleanupInvisibleIncidentsFromCache() async {
    debugPrint("Starting cache cleanup of invisible incidents...");
    final cachedIncidents = await getCachedIncidents();
    if (cachedIncidents.isEmpty) {
      debugPrint("Cache is empty. No cleanup needed.");
      return;
    }

    final List<String> cachedIds = cachedIncidents.map((i) => i.id).toList();

    // Fetch the current visibility state of these incidents from Firestore.
    final visibleIncidentsMap =
        await _firestoreService.getIncidentsVisibility(cachedIds);

    final stillVisibleIncidents = cachedIncidents.where((incident) {
      return visibleIncidentsMap[incident.id] ?? false;
    }).toList();

    int removedCount = cachedIncidents.length - stillVisibleIncidents.length;

    if (removedCount > 0) {
      // Save the cleaned list back to the cache.
      final prefs = await SharedPreferences.getInstance();
      final cleanedJson =
          jsonEncode(stillVisibleIncidents.map((i) => i.toMap()).toList());
      await prefs.setString(_incidentCacheKey, cleanedJson);
      debugPrint(
          "Cache cleanup complete. Removed $removedCount invisible incidents.");
    } else {
      debugPrint("Cache cleanup complete. No incidents needed to be removed.");
    }
  }

  Future<void> checkForNewIncidents() async {
    await fetchAndCacheAllIncidents();
  }
}
