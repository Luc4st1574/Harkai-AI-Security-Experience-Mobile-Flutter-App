// lib/features/events/screens/events_screen.dart
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

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
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

  bool _isAddingEvent = false;
  bool _isMapUpdating = false;

  // Fake loading state for the payment button
  bool _isFakeProcessing = false;

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
        .where((incidence) => incidence.type == MakerType.event)
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
          markerId: const MarkerId('target_location_pin_events'),
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
        .where((incidence) => incidence.type == MakerType.event)
        .map((incidence) =>
            createCircleFromIncidence(incidence, _localizations!))
        .toSet();
  }

  Future<void> _handleAddEventButtonPressed() async {
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
    setState(() => _isAddingEvent = true);

    // --- FAKE PAYMENT DIALOG (Updated for Events - 3 PEN) ---
    final paymentResult = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        // Local state for the dialog to show loading spinner
        return StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: const Color(0xFF001F3F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.0),
              side: const BorderSide(
                  color: Colors.green, width: 2), // Green border for events
            ),
            title: Text(
              // Assuming this localization method exists and takes a string argument
              _localizations!.paymentRequiredMessage('3.00'),
              style: const TextStyle(
                color: Colors.green, // Green text for events
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Para publicar un evento oficial en el mapa, se requiere una pequeña tarifa de servicio.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 25),

                // FAKE GOOGLE PAY BUTTON - WHITE STYLE
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isFakeProcessing
                        ? null
                        : () async {
                            // 1. Show loading in button
                            setStateDialog(() => _isFakeProcessing = true);

                            // 2. Mimic network delay (1.5 seconds)
                            await Future.delayed(
                                const Duration(milliseconds: 1500));

                            // 3. Close dialog with success (true)
                            if (context.mounted) {
                              Navigator.pop(context, true);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white, // White Background
                      foregroundColor: Colors.grey[200], // Ripple color
                      elevation: 2, // Slight shadow
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    child: _isFakeProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            // Black spinner for white background
                            child: CircularProgressIndicator(
                                color: Colors.black, strokeWidth: 2))
                        : Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center, // Center Content
                            children: [
                              // Your Logo Asset
                              Image.asset(
                                'assets/images/google_logo.png',
                                height: 24,
                                width: 24,
                              ),
                              const SizedBox(width: 8),
                              const Text("Pay",
                                  style: TextStyle(
                                      color: Colors.black, // Black Text
                                      fontWeight: FontWeight.w500,
                                      fontSize: 18)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
            actions: [
              if (!_isFakeProcessing)
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    "Cancelar",
                    style: TextStyle(color: Colors.green),
                  ),
                )
            ],
          );
        });
      },
    );

    // Reset processing flag for next time
    _isFakeProcessing = false;

    if (paymentResult == true) {
      if (!mounted) {
        setState(() => _isAddingEvent = false);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_localizations!.paymentSuccessfulMessage)),
      );

      // Proceed to the normal logic
      final result = await showIncidentVoiceDescriptionDialog(
        context: context,
        markerType: MakerType.event,
      );

      if (result != null) {
        final String? description = result['description'];
        final String? imageUrl = result['imageUrl'];
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
              makerType: MakerType.event,
              latitude: targetLat,
              longitude: targetLng,
              description: description,
              imageUrl: imageUrl,
              contactInfo: contactInfo,
              district: _mapLocationManager.currentDistrict,
              city: _mapLocationManager.currentCity,
              country: _mapLocationManager.currentCountry,
            );
          }
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_localizations!.paymentFailedMessage)),
        );
      }
    }

    if (mounted) setState(() => _isAddingEvent = false);
  }

  void _handleEventsFeedNavigation() {
    if (_currentUser == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IncidentScreen(
          incidentType: MakerType.event,
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
                            'mapDisplay_events_${initialMapCenter?.latitude}_${initialMapCenter?.longitude}'),
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
                      child: _isAddingEvent
                          ? const Center(child: CircularProgressIndicator())
                          : SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: Image.asset(
                                  'assets/images/events_icon.png',
                                  width: 24,
                                  height: 24,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  "Crear Evento", // Hardcoded Spanish text
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30.0),
                                  ),
                                  elevation: 5.0,
                                ),
                                onPressed: _handleAddEventButtonPressed,
                                onLongPress: _handleEventsFeedNavigation,
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
