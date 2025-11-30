// lib/features/pets/screens/pets_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:harkai/core/managers/download_data_manager.dart';
import 'package:harkai/l10n/app_localizations.dart';

// Services
import 'package:harkai/core/services/location_service.dart';
import 'package:harkai/core/services/phone_service.dart';

// Utils & Managers
import 'package:harkai/features/home/utils/incidences.dart';
import 'package:harkai/features/home/utils/markers.dart';
import 'package:harkai/features/home/managers/marker_manager.dart';
import 'package:harkai/features/home/managers/map_location_manager.dart';
import 'package:harkai/features/home/managers/user_session_manager.dart';

// Widgets
import 'package:harkai/features/home/widgets/header.dart';
import 'package:harkai/features/home/widgets/map.dart';

// Modals & Screens
import 'package:harkai/features/home/modals/incident_description.dart';
import 'package:harkai/features/home/modals/incident_image.dart';
import 'package:harkai/features/home/screens/home.dart';
import 'package:harkai/features/incident_feed/screens/incident_screen.dart';

class PetsScreen extends StatefulWidget {
  const PetsScreen({super.key});

  @override
  State<PetsScreen> createState() => _PetsScreenState();
}

class _PetsScreenState extends State<PetsScreen> {
  final LocationService _locationService = LocationService();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  late final MarkerManager _markerManager;
  late final MapLocationManager _mapLocationManager;
  late final UserSessionManager _userSessionManager;
  final DownloadDataManager _downloadDataManager = DownloadDataManager();
  GoogleMapController? _mapController;
  AppLocalizations? _localizations;
  User? _currentUser;

  bool _isAddingPet = false;
  bool _isMapUpdating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_localizations == null) {
      _localizations = AppLocalizations.of(context)!;

      _userSessionManager = UserSessionManager(
        firebaseAuthInstance: _firebaseAuth,
        phoneService: PhoneService(),
        onAuthChangedCallback: (User? user) {
          if (mounted) setState(() => _currentUser = user);
        },
      );

      _mapLocationManager = MapLocationManager(
        locationService: _locationService,
        onStateChange: () async {
          if (!mounted || _isMapUpdating) return;
          _isMapUpdating = true;
          await Future.delayed(const Duration(milliseconds: 32));
          if (mounted) setState(() {});
          _isMapUpdating = false;
        },
        getMapController: () => _mapController,
        setMapController: (controller) {
          if (mounted && _mapController != controller) {
            _mapController = controller;
          }
        },
      );

      _markerManager = MarkerManager(
        firestoreService: _firestoreService,
        onStateChange: () {
          if (mounted) setState(() {});
        },
        downloadDataManager: _downloadDataManager,
      );

      _initializeScreenData();
    }
  }

  Future<void> _initializeScreenData() async {
    if (_localizations == null) return;
    _userSessionManager.initialize();
    await _mapLocationManager.initializeManager(context, _localizations!);
    await _markerManager.initialize(_localizations!);
  }

  @override
  void dispose() {
    _userSessionManager.dispose();
    _mapLocationManager.dispose();
    _markerManager.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Set<Marker> _getDisplayMarkers() {
    if (_localizations == null) return {};
    Set<Marker> displayMarkers = _markerManager.incidences
        .where((incidence) => incidence.type == MakerType.pet)
        .map((incidence) => createMarkerFromIncidence(
              incidence,
              _localizations!,
              onImageMarkerTapped: (tappedIncidence) {
                showDialog(
                  context: context,
                  builder: (_) =>
                      IncidentImageDisplayModal(incidence: tappedIncidence),
                );
              },
            ))
        .toSet();

    final targetLat = _mapLocationManager.targetLatitude;
    final targetLng = _mapLocationManager.targetLongitude;
    final targetPin = _mapLocationManager.targetPinDot;

    if (targetLat != null && targetLng != null && targetPin != null) {
      displayMarkers.add(
        Marker(
          markerId: const MarkerId('target_location_pin_pets'),
          position: LatLng(targetLat, targetLng),
          icon: targetPin,
          anchor: const Offset(0.5, 0.4),
        ),
      );
    }
    return displayMarkers;
  }

  Set<Circle> _getCirclesForDisplay() {
    if (_localizations == null) return {};
    return _markerManager.incidences
        .where((incidence) => incidence.type == MakerType.pet)
        .map((incidence) =>
            createCircleFromIncidence(incidence, _localizations!))
        .toSet();
  }

  Future<void> _handleAddPetButtonPressed() async {
    if (_localizations == null || _currentUser == null) return;

    final targetLat = _mapLocationManager.targetLatitude;
    final targetLng = _mapLocationManager.targetLongitude;

    if (targetLat == null || targetLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_localizations!.targetLocationNotSet)),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isAddingPet = true);

    // Proceed directly to logic (No payment for Pets)
    final result = await showIncidentVoiceDescriptionDialog(
      context: context,
      markerType: MakerType.pet,
    );

    if (result != null) {
      final String? description = result['description'];
      final String? imageUrl = result['imageUrl'];
      // Extract contact info
      final String? contactInfo = result['contactInfo'];

      if (imageUrl == null || imageUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_localizations!.photoRequiredMessage)),
          );
        }
      } else if (description != null) {
        if (mounted) {
          await _markerManager.addMarkerAndShowNotification(
            context: context,
            makerType: MakerType.pet,
            latitude: targetLat,
            longitude: targetLng,
            description: description,
            imageUrl: imageUrl,
            // PASSING ALL DB FIELDS CORRECTLY:
            contactInfo: contactInfo,
            district: _mapLocationManager.currentDistrict,
            city: _mapLocationManager.currentCity,
            country: _mapLocationManager.currentCountry,
          );
        }
      }
    }

    if (mounted) setState(() => _isAddingPet = false);
  }

  void _handlePetsFeedNavigation() {
    if (_currentUser == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IncidentScreen(
          incidentType: MakerType.pet,
          currentUser: _currentUser,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _localizations ??= AppLocalizations.of(context)!;
    if (_localizations == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final LatLng? initialMapCenter = _mapLocationManager.initialCameraPosition;

    return Scaffold(
      backgroundColor: const Color(0xFF001F3F),
      body: SafeArea(
        child: Column(
          children: [
            HomeHeaderWidget(
              currentUser: _currentUser,
              onLogoTap: () {
                Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const Home()),
                    (Route<dynamic> route) => false);
              },
              isLongPressEnabled: true,
              locationText:
                  _mapLocationManager.getLocalizedLocationText(_localizations!),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha((0.1 * 255).toInt()),
                      spreadRadius: 0,
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 16.0),
                    Expanded(
                      child: MapDisplayWidget(
                        key: ValueKey(
                            'mapDisplay_pets_${initialMapCenter?.latitude}_${initialMapCenter?.longitude}'),
                        initialLatitude: initialMapCenter?.latitude,
                        initialLongitude: initialMapCenter?.longitude,
                        markers: _getDisplayMarkers(),
                        circles: _getCirclesForDisplay(),
                        selectedMarker: MakerType.none,
                        onMapTappedWithMarker: (LatLng position) {
                          _mapLocationManager.handleMapTapped(position, context,
                              isDistanceCheckEnabled: false);
                        },
                        onMapCreated: _mapLocationManager.onMapCreated,
                        onResetTargetPressed: () => _mapLocationManager
                            .resetTargetToUserLocation(context),
                        onCameraMove: _mapLocationManager.handleCameraMove,
                        onMapLongPressed: (cameraPosition) =>
                            _mapLocationManager.handleMapLongPressed(
                          context: context,
                          currentCameraPosition: cameraPosition,
                          markersForBigMap: _getDisplayMarkers(),
                          circlesForBigMap: _getCirclesForDisplay(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 16.0, horizontal: 20.0),
                      child: _isAddingPet
                          ? const Center(child: CircularProgressIndicator())
                          : SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: Image.asset(
                                  'assets/images/dog.png',
                                  width: 24,
                                  height: 24,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  "Reportar Mascota", // Hardcoded Spanish text
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.brown,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30.0),
                                  ),
                                  elevation: 5.0,
                                ),
                                onPressed: _handleAddPetButtonPressed,
                                onLongPress: _handlePetsFeedNavigation,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
