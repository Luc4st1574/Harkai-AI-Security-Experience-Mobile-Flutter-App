// lib/features/home/managers/marker_manager.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:harkai/core/managers/download_data_manager.dart';
import '../utils/incidences.dart';
import '../utils/markers.dart';
import '../modals/incident_description.dart';
import 'package:harkai/l10n/app_localizations.dart';
import 'package:harkai/features/home/utils/extensions.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MarkerManager {
  final FirestoreService _firestoreService;
  final VoidCallback _onStateChange;
  final DownloadDataManager _downloadDataManager;

  MakerType _selectedIncident = MakerType.none;
  MakerType get selectedIncident => _selectedIncident;

  List<IncidenceData> _incidencesData = [];
  List<IncidenceData> get incidences => _incidencesData;

  BitmapDescriptor? _petMarkerIcon;
  BitmapDescriptor? get petMarkerIcon => _petMarkerIcon;

  StreamSubscription<List<IncidenceData>>? _incidentsSubscription;
  Timer? _expiryCheckTimer;

  MarkerManager({
    required FirestoreService firestoreService,
    required VoidCallback onStateChange,
    required DownloadDataManager downloadDataManager,
  })  : _firestoreService = firestoreService,
        _onStateChange = onStateChange,
        _downloadDataManager = downloadDataManager;

  Future<void> initialize(AppLocalizations localizations) async {
    await _loadCustomMarkers();
    await _firestoreService.ensureIncidentTypesCollectionExists();
    await _downloadDataManager.cleanupInvisibleIncidentsFromCache();
    _setupIncidentListener(localizations);
    await _firestoreService.markExpiredIncidencesAsInvisible();
    _startPeriodicExpiryChecks();
  }

  Future<void> _loadCustomMarkers() async {
    try {
      final Uint8List markerIconBytes =
          await getBytesFromAsset('assets/images/brown_pin.png', 75);

      _petMarkerIcon = BitmapDescriptor.fromBytes(markerIconBytes);
      _onStateChange();
    } catch (e) {
      debugPrint('Error loading pet marker icon: $e');
    }
  }

  Future<Uint8List> getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
        targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  }

  void setActiveMaker(MakerType markerType) {
    if (_selectedIncident != markerType) {
      _selectedIncident = markerType;
      _onStateChange();
    }
  }

  void _setupIncidentListener(AppLocalizations localizations) {
    _incidentsSubscription = _firestoreService.getIncidencesStream().listen(
        (List<IncidenceData> incidences) {
      _incidencesData = incidences;
      _onStateChange();
    }, onError: (error) {
      _incidencesData = [];
      _onStateChange();
      debugPrint('MarkerManager: Error fetching incidents: $error');
    });
  }

  void _startPeriodicExpiryChecks(
      {Duration interval = const Duration(hours: 1)}) {
    _expiryCheckTimer?.cancel();
    _expiryCheckTimer = Timer.periodic(interval, (timer) async {
      await _firestoreService.markExpiredIncidencesAsInvisible();
    });
  }

  Future<void> addMarkerAndShowNotification({
    required BuildContext context,
    required MakerType makerType,
    required double latitude,
    required double longitude,
    String? description,
    String? imageUrl,
    String? contactInfo,
    String? district,
    String? city,
    String? country,
  }) async {
    final localizations = AppLocalizations.of(context)!;
    final success = await _firestoreService.addIncidence(
      type: makerType,
      latitude: latitude,
      longitude: longitude,
      description: description,
      imageUrl: imageUrl,
      contactInfo: contactInfo,
      district: district,
      city: city,
      country: country,
    );

    if (context.mounted) {
      final markerInfo = getMarkerInfo(makerType, localizations);
      final String markerTitle = markerInfo?.title ??
          makerType.name.toString().split('.').last.capitalizeAllWords();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? localizations.incidentReportedSuccess(markerTitle)
              : localizations.incidentReportFailed(markerTitle)),
        ),
      );

      if (success) {
        await _downloadDataManager.checkForNewIncidents();
      }
    }
  }

  Future<void> processIncidentReporting({
    required BuildContext context,
    required AppLocalizations localizations,
    required MakerType newMarkerToSelect,
    required double? targetLatitude,
    required double? targetLongitude,
    String? district,
    String? city,
    String? country,
  }) async {
    if (_selectedIncident == newMarkerToSelect) {
      _selectedIncident = MakerType.none;
      _onStateChange();
      return;
    }

    _selectedIncident = newMarkerToSelect;
    _onStateChange();

    if (targetLatitude != null && targetLongitude != null) {
      final result = await showIncidentVoiceDescriptionDialog(
        context: context,
        markerType: _selectedIncident,
      );

      if (result != null) {
        final String? description = result['description'];
        final String? imageUrl = result['imageUrl'];
        final String? contactInfo = result['contactInfo'];

        // --- CORRECCIÓN: Usar el tipo devuelto por el modal si existe ---
        MakerType typeToSave = _selectedIncident;
        if (result.containsKey('finalMarkerType') &&
            result['finalMarkerType'] is MakerType) {
          typeToSave = result['finalMarkerType'];
        }
        // ----------------------------------------------------------------

        if (description != null || imageUrl != null) {
          if (context.mounted) {
            await addMarkerAndShowNotification(
              context: context,
              makerType: typeToSave, // Usamos la variable local corregida
              latitude: targetLatitude,
              longitude: targetLongitude,
              description: description,
              imageUrl: imageUrl,
              contactInfo: contactInfo,
              district: district,
              city: city,
              country: country,
            );
          }
        } else {
          _selectedIncident = MakerType.none;
          _onStateChange();
        }
      } else {
        _selectedIncident = MakerType.none;
        _onStateChange();
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.targetLocationNotSet)),
        );
      }
      _selectedIncident = MakerType.none;
      _onStateChange();
    }
  }

  Future<void> processEmergencyReporting({
    required BuildContext context,
    required AppLocalizations localizations,
    required double? targetLatitude,
    required double? targetLongitude,
    String? district,
    String? city,
    String? country,
  }) async {
    _selectedIncident = MakerType.emergency;
    _onStateChange();

    if (targetLatitude != null && targetLongitude != null) {
      final result = await showIncidentVoiceDescriptionDialog(
        context: context,
        markerType: MakerType.emergency,
      );

      if (result != null) {
        final String? description = result['description'];
        final String? imageUrl = result['imageUrl'];

        // Para emergencias, también podríamos verificar si hubo cambio,
        // aunque es menos común cambiar desde emergencia a otra cosa.
        MakerType typeToSave = MakerType.emergency;
        if (result.containsKey('finalMarkerType') &&
            result['finalMarkerType'] is MakerType) {
          typeToSave = result['finalMarkerType'];
        }

        if (description != null || imageUrl != null) {
          if (context.mounted) {
            await addMarkerAndShowNotification(
              context: context,
              makerType: typeToSave,
              latitude: targetLatitude,
              longitude: targetLongitude,
              description:
                  description ?? localizations.incidentModalStatusError,
              imageUrl: imageUrl,
              district: district,
              city: city,
              country: country,
            );
          }
        } else {
          _selectedIncident = MakerType.none;
          _onStateChange();
        }
      } else {
        _selectedIncident = MakerType.none;
        _onStateChange();
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.emergencyReportLocationUnknown)),
        );
      }
      _selectedIncident = MakerType.none;
      _onStateChange();
    }
  }

  void resetSelectedMarkerToNone() {
    _selectedIncident = MakerType.none;
    _onStateChange();
  }

  void dispose() {
    _incidentsSubscription?.cancel();
    _expiryCheckTimer?.cancel();
  }
}
