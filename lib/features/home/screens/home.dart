// lib/features/home/screens/home.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:harkai/core/managers/download_data_manager.dart';
import 'package:harkai/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../onboarding/screens/onboarding_tutorial.dart';

// Services
import '../../../core/services/location_service.dart';
import '../../../core/services/phone_service.dart';
import '../../../core/services/speech_service.dart';
import '../../../core/services/notification_service.dart';

// Utils
import '../utils/incidences.dart';
import '../utils/markers.dart';

// Widgets
import '../widgets/header.dart';
import '../widgets/map.dart';
import '../widgets/incident_buttons.dart';
import '../widgets/bottom_butons.dart';
import '../modals/incident_image.dart';
import 'package:harkai/features/incident_feed/screens/incident_screen.dart';

// Screens
import '../../places/screens/places_screen.dart';
import '../../pets/screens/pets_screen.dart'; // NEW IMPORT
import '../../events/screens/events_screen.dart'; // NEW IMPORT

// Managers
import '../managers/marker_manager.dart';
import '../managers/map_location_manager.dart';
import '../managers/user_session_manager.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final LocationService _locationService = LocationService();
  final FirestoreService _firestoreService = FirestoreService();
  final PhoneService _phoneService = PhoneService();
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final SpeechPermissionService _speechPermissionService =
      SpeechPermissionService();
  final NotificationService _notificationService = NotificationService();
  final DownloadDataManager _downloadDataManager = DownloadDataManager();
  late final MarkerManager _dataEventManager;
  late final MapLocationManager _mapLocationManager;
  late final UserSessionManager _userSessionManager;

  GoogleMapController? _mapController;
  AppLocalizations? _localizations;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_localizations == null) {
      _localizations = AppLocalizations.of(context)!;

      _userSessionManager = UserSessionManager(
        firebaseAuthInstance: _firebaseAuth,
        phoneService: _phoneService,
        onAuthChangedCallback: (User? user) {
          if (mounted) setState(() {});
        },
      );

      _mapLocationManager = MapLocationManager(
        locationService: _locationService,
        onStateChange: () {
          if (mounted) setState(() {});
        },
        getMapController: () => _mapController,
        setMapController: (controller) {
          if (mounted) {
            if (_mapController != controller) {
              _mapController = controller;
            }
          }
        },
        onShowAlwaysOnLocationPrompt: _showAlwaysOnLocationExplanationModal,
      );

      _dataEventManager = MarkerManager(
        firestoreService: _firestoreService,
        onStateChange: () {
          if (mounted) setState(() {});
        },
        downloadDataManager: _downloadDataManager,
      );

      _initializeAndCheckOnboarding();
    }
  }

  Future<void> _initializeAndCheckOnboarding() async {
    await _initializeScreenData();
    await _checkFirstLaunch();
  }

  Future<void> _initializeScreenData() async {
    if (_localizations == null) return;
    _userSessionManager.initialize();
    await _dataEventManager.initialize(_localizations!);
  }

  Future<void> _requestInitialPermissions() async {
    if (_localizations == null) return;
    await _mapLocationManager.initializeManager(context, _localizations!);
    bool speechReady = await _speechPermissionService
        .ensurePermissionsAndInitializeService(openSettingsOnError: true);
    await _notificationService.requestNotificationPermission(
        openSettingsOnError: true);
    debugPrint("Home: Speech service ready after onboarding: $speechReady");
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = prefs.getBool('is_first_launch') ?? true;

    if (isFirstLaunch) {
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) => const OnboardingTutorial(),
        );
        await prefs.setBool('is_first_launch', false);
        await _requestInitialPermissions();
      }
    } else {
      await _requestInitialPermissions();
    }
  }

  Future<bool> _showAlwaysOnLocationExplanationModal(
      BuildContext context, AppLocalizations localizations) async {
    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF001F3F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
            side: const BorderSide(color: Color(0xFF57D463), width: 2),
          ),
          title: Text(
            localizations.onboardingAlwaysOnLocationPromptTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF57D463),
            ),
          ),
          content: Text(
            localizations.onboardingAlwaysOnLocationPromptDescription,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.white70,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(
                localizations.onboardingAlwaysOnLocationPromptButton,
                style: const TextStyle(
                  color: Color(0xFF57D463),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  @override
  void dispose() {
    _userSessionManager.dispose();
    _mapLocationManager.dispose();
    _dataEventManager.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Set<Marker> _prepareMapMarkers() {
    if (_localizations == null) return {};
    return _dataEventManager.incidences
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
              petIcon: _dataEventManager.petMarkerIcon,
            ))
        .toSet();
  }

  Set<Marker> _getDisplayMarkers() {
    Set<Marker> displayMarkers = _prepareMapMarkers();
    final targetLat = _mapLocationManager.targetLatitude;
    final targetLng = _mapLocationManager.targetLongitude;
    final targetPin = _mapLocationManager.targetPinDot;

    if (targetLat != null && targetLng != null && targetPin != null) {
      displayMarkers.add(
        Marker(
          markerId: const MarkerId('target_location_pin'),
          position: LatLng(targetLat, targetLng),
          icon: targetPin,
          anchor: const Offset(0.5, 0.4),
        ),
      );
    }
    return displayMarkers;
  }

  Set<Marker> _getMarkersForBigMapModal() {
    if (_localizations == null) return {};
    Set<Marker> markers = _dataEventManager.incidences
        .map((incidence) => createMarkerFromIncidence(
              incidence,
              _localizations!,
              petIcon: _dataEventManager.petMarkerIcon,
            ))
        .toSet();

    final targetLat = _mapLocationManager.targetLatitude;
    final targetLng = _mapLocationManager.targetLongitude;
    final targetPin = _mapLocationManager.targetPinDot;

    if (targetLat != null && targetLng != null && targetPin != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('target_location_pin_big_map'),
          position: LatLng(targetLat, targetLng),
          icon: targetPin,
          infoWindow: InfoWindow(title: _localizations!.targetLocationNotSet),
          anchor: const Offset(0.5, 0.4),
        ),
      );
    }
    return markers;
  }

  Set<Circle> _getCirclesForDisplay() {
    if (_localizations == null) return {};
    return _dataEventManager.incidences
        .map((incidence) =>
            createCircleFromIncidence(incidence, _localizations!))
        .toSet();
  }

  Set<Circle> _getCirclesForBigMapModal() {
    if (_localizations == null) return {};
    return _dataEventManager.incidences
        .map((incidence) =>
            createCircleFromIncidence(incidence, _localizations!))
        .toSet();
  }

  // UPDATED: Now handles navigation for Places, Pets, and Events
  Future<void> _handleIncidentButtonPressed(MakerType markerType) async {
    if (!mounted || _localizations == null) return;

    // --- NAVIGATION TO SUB-SCREENS ---
    if (markerType == MakerType.place) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PlacesScreen()),
      );
      return;
    }

    if (markerType == MakerType.pet) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PetsScreen()),
      );
      return;
    }

    if (markerType == MakerType.event) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const EventsScreen()),
      );
      return;
    }
    // --------------------------------

    if (markerType == MakerType.emergency) {
      await _handleEmergencyButtonPressed();
      return;
    }

    // Standard incidents (Theft, Fire, Crash, etc.)
    await _dataEventManager.processIncidentReporting(
      context: context,
      localizations: _localizations!,
      newMarkerToSelect: markerType,
      targetLatitude: _mapLocationManager.targetLatitude,
      targetLongitude: _mapLocationManager.targetLongitude,
      district: _mapLocationManager.currentDistrict,
      city: _mapLocationManager.currentCity,
      country: _mapLocationManager.currentCountry,
    );
  }

  void _handleIncidentButtonLongPressed(MakerType markerType) {
    if (!mounted ||
        _userSessionManager.currentUser == null ||
        _localizations == null) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IncidentScreen(
          incidentType: markerType,
          currentUser: _userSessionManager.currentUser,
        ),
      ),
    );
  }

  Future<void> _handleEmergencyButtonPressed() async {
    if (!mounted || _localizations == null) return;
    await _dataEventManager.processEmergencyReporting(
      context: context,
      localizations: _localizations!,
      targetLatitude: _mapLocationManager.targetLatitude,
      targetLongitude: _mapLocationManager.targetLongitude,
      district: _mapLocationManager.currentDistrict,
      city: _mapLocationManager.currentCity,
      country: _mapLocationManager.currentCountry,
    );
  }

  @override
  Widget build(BuildContext context) {
    _localizations ??= AppLocalizations.of(context)!;
    if (_localizations == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final String? currentCity = _mapLocationManager.currentCityName;
    final LatLng? initialMapCenter = _mapLocationManager.initialCameraPosition;

    if (initialMapCenter == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF001F3F),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF57D463)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF001F3F),
      body: Stack(
        children: [
          // 1. Full Screen Map Layer
          Positioned.fill(
            child: MapDisplayWidget(
              key: ValueKey(
                  'mapDisplay_${initialMapCenter.latitude}_${initialMapCenter.longitude}'),
              initialLatitude: initialMapCenter.latitude,
              initialLongitude: initialMapCenter.longitude,
              markers: _getDisplayMarkers(),
              circles: _getCirclesForDisplay(),
              selectedMarker: _dataEventManager.selectedIncident,
              isFullScreen: true,
              onMapTappedWithMarker: (LatLng position) {
                _mapLocationManager.handleMapTapped(position, context,
                    isDistanceCheckEnabled: true);
              },
              onMapLongPressed: (cameraPosition) {
                _mapLocationManager.handleMapLongPressed(
                  context: context,
                  currentCameraPosition: cameraPosition,
                  markersForBigMap: _getMarkersForBigMapModal(),
                  circlesForBigMap: _getCirclesForBigMapModal(),
                );
              },
              onMapCreated: _mapLocationManager.onMapCreated,
              onResetTargetPressed: () {
                _mapLocationManager.resetTargetToUserLocation(context);
              },
              onCameraMove: _mapLocationManager.handleCameraMove,
            ),
          ),

          // 2. Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: HomeHeaderWidget(
                currentUser: _userSessionManager.currentUser,
                isLongPressEnabled: true,
                locationText: _mapLocationManager
                    .getLocalizedLocationText(_localizations!),
              ),
            ),
          ),

          // 3. Sliding Bottom Sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: DraggableScrollableSheet(
              initialChildSize: 0.10,
              minChildSize: 0.10,
              maxChildSize: 0.6,
              expand: false,
              snap: true,
              builder:
                  (BuildContext context, ScrollController scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24.0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        spreadRadius: 2,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24.0)),
                    child: CustomScrollView(
                      controller: scrollController,
                      physics: const ClampingScrollPhysics(),
                      shrinkWrap: true,
                      slivers: [
                        SliverAppBar(
                          backgroundColor: Colors.white,
                          automaticallyImplyLeading: false,
                          elevation: 0,
                          pinned: true,
                          toolbarHeight: 16,
                          flexibleSpace: Center(
                            child: Container(
                              margin: const EdgeInsets.only(top: 6),
                              width: 50,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IncidentButtonsGridWidget(
                                  selectedIncident:
                                      _dataEventManager.selectedIncident,
                                  onIncidentButtonPressed: (MakerType type) {
                                    _handleIncidentButtonPressed(type);
                                  },
                                  onIncidentButtonLongPressed:
                                      (MakerType type) {
                                    _handleIncidentButtonLongPressed(type);
                                  },
                                ),
                                const SizedBox(height: 10),
                                BottomActionButtonsWidget(
                                  currentServiceName: getCallButtonServiceName(
                                      _dataEventManager.selectedIncident,
                                      _localizations!),
                                  onPhonePressed: () {
                                    if (!mounted || _localizations == null)
                                      return;
                                    _userSessionManager.makePhoneCall(
                                      context: context,
                                      localizations: _localizations!,
                                      selectedIncident:
                                          _dataEventManager.selectedIncident,
                                      cityName: currentCity,
                                      firestoreService: _firestoreService,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
