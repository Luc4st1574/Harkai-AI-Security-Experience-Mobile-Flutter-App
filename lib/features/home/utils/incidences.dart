// lib/features/home/utils/incidences.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'markers.dart';
import 'package:harkai/l10n/app_localizations.dart';
import 'package:harkai/features/home/utils/extensions.dart';

/// A data class to represent a heat point retrieved from Firestore.
class IncidenceData {
  final String id;
  final String userId;
  final double latitude;
  final double longitude;
  final MakerType type;
  final String description;
  final String? imageUrl;
  final Timestamp timestamp;
  final bool isVisible;
  final String? contactInfo;
  final String? district;
  final String? city;
  final String? country;
  double? distance;

  IncidenceData({
    required this.id,
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.description,
    this.imageUrl,
    required this.timestamp,
    required this.isVisible,
    this.contactInfo,
    this.district,
    this.city,
    this.country,
    this.distance,
  });

  factory IncidenceData.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    int typeIndex = 0;
    if (data['type'] is int) {
      typeIndex = data['type'];
    } else if (data['type'] is String) {
      typeIndex = int.tryParse(data['type']) ?? 0;
    }

    MakerType parsedType = MakerType.none;
    if (typeIndex >= 0 && typeIndex < MakerType.values.length) {
      parsedType = MakerType.values[typeIndex];
    }

    return IncidenceData(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      type: parsedType,
      description: data['description'] as String? ?? '',
      imageUrl: data['imageUrl'] as String?,
      timestamp: data['timestamp'] as Timestamp? ?? Timestamp.now(),
      isVisible: data['isVisible'] as bool? ?? true,
      contactInfo: data['contactInfo'] as String?,
      district: data['district'] as String?,
      city: data['city'] as String?,
      country: data['country'] as String?,
    );
  }

  @override
  String toString() {
    return 'IncidenceData(id: $id, type: ${type.name}, loc: $district, $country)';
  }
}

Marker createMarkerFromIncidence(
  IncidenceData incidence,
  AppLocalizations localizations, {
  Function(IncidenceData)? onImageMarkerTapped,
  BitmapDescriptor? petIcon,
}) {
  final MarkerInfo? incidentInfoForMarker =
      getMarkerInfo(incidence.type, localizations);

  return Marker(
    markerId: MarkerId(incidence.id),
    position: LatLng(incidence.latitude, incidence.longitude),
    icon: getMarkerBitmap(incidence.type, petIcon: petIcon),
    infoWindow: (incidence.imageUrl == null || incidence.imageUrl!.isEmpty)
        ? InfoWindow(
            title: incidentInfoForMarker?.title ??
                incidence.type.name.capitalizeAllWords(),
            snippet:
                incidence.description.isNotEmpty ? incidence.description : null,
          )
        : InfoWindow.noText,
    onTap: (incidence.imageUrl != null &&
            incidence.imageUrl!.isNotEmpty &&
            onImageMarkerTapped != null)
        ? () => onImageMarkerTapped(incidence)
        : null,
  );
}

Circle createCircleFromIncidence(
    IncidenceData incidence, AppLocalizations localizations) {
  final MarkerInfo? markerInfo = getMarkerInfo(incidence.type, localizations);
  final Color baseColor = markerInfo?.color ?? Colors.grey;

  return Circle(
    circleId: CircleId('circle_${incidence.id}'),
    center: LatLng(incidence.latitude, incidence.longitude),
    radius: 80,
    fillColor: baseColor.withAlpha((0.25 * 255).round()),
    strokeColor: baseColor.withAlpha((0.7 * 255).round()),
    strokeWidth: 1,
  );
}

String _normalizeCityNameForFirestoreQuery(String cityName) {
  if (cityName.isEmpty) return "";
  String withoutAccents = cityName
      .replaceAll('á', 'a')
      .replaceAll('Á', 'A')
      .replaceAll('é', 'e')
      .replaceAll('É', 'E')
      .replaceAll('í', 'i')
      .replaceAll('Í', 'I')
      .replaceAll('ó', 'o')
      .replaceAll('Ó', 'O')
      .replaceAll('ú', 'u')
      .replaceAll('Ú', 'U')
      .replaceAll('ü', 'u')
      .replaceAll('Ü', 'U')
      .replaceAll('ñ', 'n')
      .replaceAll('Ñ', 'N');
  String lowerCaseName = withoutAccents.toLowerCase();
  String normalized = lowerCaseName.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized;
}

class FirestoreService {
  final CollectionReference _heatPointsCollection =
      FirebaseFirestore.instance.collection('HeatPoints');
  final CollectionReference _numbersCollection =
      FirebaseFirestore.instance.collection('Numbers');
  final CollectionReference _incidentTypesCollection =
      FirebaseFirestore.instance.collection('incident_types');

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  FirestoreService();

  /// Ensures the incident types collection exists.
  /// UPDATED: Checks if data exists first to avoid overwriting or recreation loops.
  Future<void> ensureIncidentTypesCollectionExists() async {
    try {
      // 1. Check if the collection is already populated.
      // We limit to 1 because we only need to know if ANY document exists.
      final QuerySnapshot snapshot =
          await _incidentTypesCollection.limit(1).get();

      // 2. If it's not empty, we assume it's initialized and exit immediately.
      if (snapshot.docs.isNotEmpty) {
        return;
      }

      // 3. Only proceed to create types if the collection is truly empty.
      for (var type in MakerType.values) {
        final String docId = type.index.toString();
        await _incidentTypesCollection.doc(docId).set({
          'id': type.index,
          'name': type.name,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Error creating incident types collection: $e");
    }
  }

  Future<bool> addIncidence({
    required MakerType type,
    required double latitude,
    required double longitude,
    String? description,
    String? imageUrl,
    String? contactInfo,
    String? district,
    String? city,
    String? country,
  }) async {
    if (type == MakerType.none) {
      return false;
    }
    final User? currentUser = _firebaseAuth.currentUser;
    if (currentUser == null) {
      return false;
    }
    try {
      await _heatPointsCollection.add({
        'userId': currentUser.uid,
        'latitude': latitude,
        'longitude': longitude,
        'type': type.index,
        'description': description ?? '',
        'imageUrl': imageUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'isVisible': true,
        'contactInfo': contactInfo,
        'district': district,
        'city': city,
        'country': country,
      });
      return true;
    } catch (e) {
      debugPrint('Error adding incidence: $e');
      return false;
    }
  }

  Stream<List<IncidenceData>> getIncidencesStream() {
    return _heatPointsCollection
        .where('isVisible', isEqualTo: true)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) {
            try {
              return IncidenceData.fromFirestore(doc);
            } catch (e) {
              return null;
            }
          })
          .whereType<IncidenceData>()
          .toList();
    }).handleError((error) {
      debugPrint('Error in getIncidencesStream: $error');
      return <IncidenceData>[];
    });
  }

  Stream<List<IncidenceData>> getIncidencesStreamByType(MakerType type) {
    if (type == MakerType.none) {
      return Stream.value([]);
    }
    return _heatPointsCollection
        .where('isVisible', isEqualTo: true)
        .where('type', isEqualTo: type.index)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) {
            try {
              return IncidenceData.fromFirestore(doc);
            } catch (e) {
              return null;
            }
          })
          .whereType<IncidenceData>()
          .toList();
    }).handleError((error) {
      return <IncidenceData>[];
    });
  }

  Future<Map<String, bool>> getIncidentsVisibility(
      List<String> incidentIds) async {
    if (incidentIds.isEmpty) return {};
    final Map<String, bool> visibilityMap = {};
    const batchSize = 30;
    for (var i = 0; i < incidentIds.length; i += batchSize) {
      final sublist = incidentIds.sublist(
          i,
          i + batchSize > incidentIds.length
              ? incidentIds.length
              : i + batchSize);
      if (sublist.isEmpty) continue;
      try {
        final querySnapshot = await _heatPointsCollection
            .where(FieldPath.documentId, whereIn: sublist)
            .get();
        for (final doc in querySnapshot.docs) {
          final data = doc.data() as Map<String, dynamic>?;
          visibilityMap[doc.id] = data?['isVisible'] ?? false;
        }
      } catch (e) {
        debugPrint('Error fetching batch: $e');
      }
    }
    return visibilityMap;
  }

  Future<int> markExpiredIncidencesAsInvisible(
      {Duration expiryDuration = const Duration(hours: 3)}) async {
    final DateTime now = DateTime.now();
    final Timestamp generalCutoffTimestamp =
        Timestamp.fromDate(now.subtract(expiryDuration));
    final Timestamp petExpiryTimestamp =
        Timestamp.fromDate(now.subtract(const Duration(days: 1)));
    int totalUpdatedCount = 0;
    try {
      QuerySnapshot querySnapshot = await _heatPointsCollection
          .where('isVisible', isEqualTo: true)
          .where('timestamp', isLessThan: generalCutoffTimestamp)
          .get();
      List<DocumentSnapshot> documentsToProcess = querySnapshot.docs.toList();
      WriteBatch batch = FirebaseFirestore.instance.batch();
      int currentBatchOperations = 0;
      for (var doc in documentsToProcess) {
        final Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        int typeId = -1;
        if (data['type'] is int) {
          typeId = data['type'];
        } else if (data['type'] is String) {
          final String typeString = data['type'];
          final typeEnum = MakerType.values.firstWhere(
              (e) => e.name == typeString,
              orElse: () => MakerType.none);
          typeId = typeEnum.index;
        }
        MakerType incidenceType = MakerType.none;
        if (typeId >= 0 && typeId < MakerType.values.length) {
          incidenceType = MakerType.values[typeId];
        }
        final Timestamp docTimestamp =
            data['timestamp'] as Timestamp? ?? Timestamp.now();
        if (incidenceType == MakerType.place) {
          continue;
        }
        bool shouldMarkInvisible = false;

        // UPDATED: Check for Event as well as Pet for 24h rule
        if (incidenceType == MakerType.pet ||
            incidenceType == MakerType.event) {
          if (docTimestamp.compareTo(petExpiryTimestamp) < 0) {
            shouldMarkInvisible = true;
          }
        } else {
          shouldMarkInvisible = true;
        }
        if (shouldMarkInvisible) {
          batch.update(doc.reference, {'isVisible': false});
          totalUpdatedCount++;
          currentBatchOperations++;
          if (currentBatchOperations >= 499) {
            await batch.commit();
            batch = FirebaseFirestore.instance.batch();
            currentBatchOperations = 0;
          }
        }
      }
      if (currentBatchOperations > 0) {
        await batch.commit();
      }
      return totalUpdatedCount;
    } catch (e) {
      return 0;
    }
  }

  Future<Map<String, String>?> getEmergencyNumbersForCity(
      String cityName) async {
    if (cityName.isEmpty) return null;
    String normalizedQueryCityName =
        _normalizeCityNameForFirestoreQuery(cityName);
    try {
      final QuerySnapshot querySnapshot = await _numbersCollection
          .where("City", isEqualTo: normalizedQueryCityName)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        final DocumentSnapshot cityNumbersDoc = querySnapshot.docs.first;
        final Map<String, dynamic> rawData =
            cityNumbersDoc.data() as Map<String, dynamic>;
        return rawData.map((key, value) => MapEntry(key, value.toString()));
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}
