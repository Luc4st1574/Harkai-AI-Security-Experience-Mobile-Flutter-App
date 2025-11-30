// lib/features/home/managers/map_location_manager.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/services/location_service.dart';
import '../modals/enlarged_map.dart';
import 'package:harkai/l10n/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart' as perm_handler;

typedef AlwaysOnLocationPromptCallback = Future<bool> Function(
    BuildContext context, AppLocalizations localizations);

class MapLocationManager {
  final LocationService _locationService;
  final VoidCallback _onStateChange;
  final GoogleMapController? Function() _getMapController;
  final Function(GoogleMapController) _setMapController;
  final AlwaysOnLocationPromptCallback? onShowAlwaysOnLocationPrompt;

  static const String _initialStateKey = 'harkai_initial_loading';
  // Stores the detailed address info instead of just a string
  AddressInfo? _currentAddressInfo;
  // Used for status messages (errors, loading) if _currentAddressInfo is null
  String _statusMessage = _initialStateKey;
  bool _isErrorOrStatus = true;

  double? _latitude;
  double? _longitude;
  double? _targetLatitude;
  double? _targetLongitude;

  double? _lastGeocodedLatitude;
  double? _lastGeocodedLongitude;
  static const double _addressUpdateDistanceThreshold = 500.0;
  static const double maxMarkerMoveDistance = 300.0;

  StreamSubscription<geolocator.Position>? _positionStreamSubscription;
  BitmapDescriptor? _targetPinDot;

  double? get latitude => _latitude;
  double? get longitude => _longitude;
  double? get targetLatitude => _targetLatitude;
  double? get targetLongitude => _targetLongitude;
  BitmapDescriptor? get targetPinDot => _targetPinDot;
  LatLng? get initialCameraPosition =>
      _targetLatitude != null && _targetLongitude != null
          ? LatLng(_targetLatitude!, _targetLongitude!)
          : (_latitude != null && _longitude != null
              ? LatLng(_latitude!, _longitude!)
              : null);

  String? get currentCityName {
    return _currentAddressInfo?.city ??
        _currentAddressInfo?.displayText.split(',').first.trim();
  }

  // --- NEW GETTERS for detailed location info ---
  String? get currentDistrict => _currentAddressInfo?.district;
  String? get currentCity => _currentAddressInfo?.city;
  String? get currentCountry => _currentAddressInfo?.country;

  MapLocationManager({
    required LocationService locationService,
    required VoidCallback onStateChange,
    required GoogleMapController? Function() getMapController,
    required Function(GoogleMapController) setMapController,
    this.onShowAlwaysOnLocationPrompt,
  })  : _locationService = locationService,
        _onStateChange = onStateChange,
        _getMapController = getMapController,
        _setMapController = setMapController;

  String getLocalizedLocationText(AppLocalizations localizations) {
    if (_statusMessage == _initialStateKey && _currentAddressInfo == null) {
      return localizations.mapinitialFetchingLocation;
    }

    if (_isErrorOrStatus) {
      switch (_statusMessage) {
        case 'loading':
          return localizations.mapLoadingLocation;
        case 'fetching':
          return localizations.mapFetchingLocation;
        default:
          if (_statusMessage == localizations.mapinitialFetchingLocation)
            return localizations.mapinitialFetchingLocation;
          if (_statusMessage == localizations.mapCouldNotFetchAddress)
            return localizations.mapCouldNotFetchAddress;
          if (_statusMessage == localizations.mapFailedToGetInitialLocation)
            return localizations.mapFailedToGetInitialLocation;
          if (_statusMessage == localizations.mapLocationServicesDisabled)
            return localizations.mapLocationServicesDisabled;
          if (_statusMessage == localizations.mapLocationPermissionDenied)
            return localizations.mapLocationPermissionDenied;

          if (_statusMessage.startsWith("Error:") ||
              _statusMessage.startsWith("Failed:")) {
            return _statusMessage;
          }
          return localizations.mapCouldNotFetchAddress;
      }
    }

    // Use the display text from the AddressInfo
    return localizations.mapYouAreIn(_currentAddressInfo?.displayText ??
        localizations.mapCouldNotFetchAddress);
  }

  Future<void> initializeManager(
      BuildContext context, AppLocalizations localizations) async {
    await _loadCustomTargetIcon();

    bool foregroundPermissionGranted = await _locationService
        .requestForegroundLocationPermission(openSettingsOnError: true);
    if (!foregroundPermissionGranted) {
      _statusMessage = localizations.mapLocationPermissionDenied;
      _isErrorOrStatus = true;
      _onStateChange();
      debugPrint(
          "MapLocationManager: Foreground location permission denied. Cannot proceed with map.");
      return;
    }

    var backgroundStatus = await perm_handler.Permission.locationAlways.status;
    if (backgroundStatus != perm_handler.PermissionStatus.granted &&
        backgroundStatus != perm_handler.PermissionStatus.permanentlyDenied) {
      if (onShowAlwaysOnLocationPrompt != null) {
        bool userAcceptedExplanation =
            await onShowAlwaysOnLocationPrompt!(context, localizations);

        if (userAcceptedExplanation) {
          await _locationService.requestBackgroundLocationPermission(
              openSettingsOnError: true);
        }
      }
    }

    await _fetchInitialLocationAndAddress(localizations);
    _setupLocationUpdatesListener(localizations);
  }

  Future<void> _loadCustomTargetIcon() async {
    try {
      _targetPinDot = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(15, 15)),
        'assets/images/tap_position_marker.png',
      );
    } catch (e) {
      debugPrint('Error loading custom target icon: $e');
      _targetPinDot =
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
    }
    _onStateChange();
  }

  Future<void> _fetchInitialLocationAndAddress(AppLocalizations localizations,
      {bool isUpdate = false}) async {
    if (!isUpdate) {
      _statusMessage = localizations.mapinitialFetchingLocation;
      _isErrorOrStatus = true;
      _onStateChange();

      final initialPosResult = await _locationService.getInitialPosition();

      if (initialPosResult.success && initialPosResult.data != null) {
        _latitude = initialPosResult.data!.latitude;
        _longitude = initialPosResult.data!.longitude;
        _targetLatitude = _latitude;
        _targetLongitude = _longitude;

        final addressResult = await _locationService.getAddressFromCoordinates(
            _latitude!, _longitude!);

        if (addressResult.success && addressResult.data != null) {
          _currentAddressInfo = addressResult.data;
          _isErrorOrStatus = false;
          _lastGeocodedLatitude = _latitude;
          _lastGeocodedLongitude = _longitude;
        } else {
          _statusMessage = localizations.mapCouldNotFetchAddress;
          _isErrorOrStatus = true;
          debugPrint(
              "getAddressFromCoordinates failed initially: ${addressResult.errorMessage}");
        }
        _animateMapToTarget(zoom: 16.0);
      } else {
        _statusMessage = initialPosResult.errorMessage ??
            localizations.mapFailedToGetInitialLocation;
        _isErrorOrStatus = true;
        debugPrint(
            "getInitialPosition failed: ${initialPosResult.errorMessage}");
      }
      _onStateChange();
      return;
    }

    if (_latitude != null && _longitude != null) {
      final addressResult = await _locationService.getAddressFromCoordinates(
          _latitude!, _longitude!);
      if (addressResult.success && addressResult.data != null) {
        _currentAddressInfo = addressResult.data;
        _isErrorOrStatus = false;
        _lastGeocodedLatitude = _latitude;
        _lastGeocodedLongitude = _longitude;
      } else {
        debugPrint(
            "getAddressFromCoordinates failed during background update: ${addressResult.errorMessage}");
      }
    }
    _onStateChange();
  }

  void _setupLocationUpdatesListener(AppLocalizations localizations) async {
    bool serviceEnabled = await _locationService.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _statusMessage = localizations.mapLocationServicesDisabled;
      _isErrorOrStatus = true;
      _latitude = null;
      _longitude = null;
      _onStateChange();
      return;
    }
    bool permGranted =
        await _locationService.requestForegroundLocationPermission();
    if (!permGranted) {
      _statusMessage = localizations.mapLocationPermissionDenied;
      _isErrorOrStatus = true;
      _latitude = null;
      _longitude = null;
      _onStateChange();
      return;
    }

    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = _locationService.getPositionStream().listen(
        (geolocator.Position position) async {
      _latitude = position.latitude;
      _longitude = position.longitude;

      bool shouldUpdateAddress = false;
      if (_lastGeocodedLatitude == null || _lastGeocodedLongitude == null) {
        shouldUpdateAddress = true;
      } else {
        double distanceMoved = geolocator.Geolocator.distanceBetween(
          _lastGeocodedLatitude!,
          _lastGeocodedLongitude!,
          position.latitude,
          position.longitude,
        );
        if (distanceMoved > _addressUpdateDistanceThreshold) {
          shouldUpdateAddress = true;
        }
      }

      if (shouldUpdateAddress) {
        debugPrint(
            "MapLocationManager: User moved significantly. Re-fetching address...");
        await _fetchInitialLocationAndAddress(localizations, isUpdate: true);
      } else {
        _onStateChange();
      }
    }, onError: (error) {
      _latitude = null;
      _longitude = null;
      debugPrint("Error in location stream: $error");
      _onStateChange();
    });
  }

  void _animateMapToTarget({double zoom = 16.0}) {
    if (_targetLatitude != null && _targetLongitude != null) {
      final currentMapController = _getMapController();
      currentMapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
            LatLng(_targetLatitude!, _targetLongitude!), zoom),
      );
    }
  }

  void onMapCreated(GoogleMapController controller) {
    _setMapController(controller);
    if (_targetLatitude != null && _targetLongitude != null) {
      _animateMapToTarget(zoom: 16.0);
    } else if (_latitude != null && _longitude != null) {
      final currentMapController = _getMapController();
      currentMapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(_latitude!, _longitude!), 16.0),
      );
    }
  }

  void handleMapTapped(LatLng position, BuildContext context,
      {bool isDistanceCheckEnabled = true}) {
    if (isDistanceCheckEnabled && _latitude != null && _longitude != null) {
      final distance = geolocator.Geolocator.distanceBetween(
        _latitude!,
        _longitude!,
        position.latitude,
        position.longitude,
      );

      if (distance > maxMarkerMoveDistance) {
        final localizations = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.mapMarkerTooFar),
          ),
        );
        return;
      }
    }

    _targetLatitude = position.latitude;
    _targetLongitude = position.longitude;
    _onStateChange();
    _animateMapToTarget();
  }

  void handleCameraMove(CameraPosition position) {}

  Future<void> handleMapLongPressed({
    required BuildContext context,
    required CameraPosition currentCameraPosition,
    required Set<Marker> markersForBigMap,
    required Set<Circle> circlesForBigMap,
  }) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
          child: SizedBox(
            width: screenWidth * 0.85,
            height: screenHeight * 0.65,
            child: EnlargedMapModal(
              initialLatitude: currentCameraPosition.target.latitude,
              initialLongitude: currentCameraPosition.target.longitude,
              markers: markersForBigMap,
              circles: circlesForBigMap,
              currentZoom: currentCameraPosition.zoom,
            ),
          ),
        );
      },
    );
  }

  Future<void> resetTargetToUserLocation(BuildContext context) async {
    final localizations = AppLocalizations.of(context)!;
    if (_latitude != null && _longitude != null) {
      _targetLatitude = _latitude;
      _targetLongitude = _longitude;
      await _fetchInitialLocationAndAddress(localizations, isUpdate: true);
      _animateMapToTarget(zoom: 16.0);
    } else {
      if (ScaffoldMessenger.of(context).mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(localizations.mapCurrentUserLocationNotAvailable)),
        );
      }
      await _fetchInitialLocationAndAddress(localizations);
    }
  }

  void dispose() {
    _positionStreamSubscription?.cancel();
    debugPrint("MapLocationManager disposed and position stream cancelled.");
  }
}
