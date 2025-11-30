// lib/core/services/location_service.dart
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as perm_handler;
import 'package:flutter_google_maps_webservices/geocoding.dart' as g_geocoding;

class LocationResult<T> {
  final T? data;
  final bool success;
  final String? errorMessage;

  LocationResult({this.data, this.success = true, this.errorMessage});
}

/// Helper class to hold detailed address components
class AddressInfo {
  final String? district;
  final String? city;
  final String? country;
  final String displayText;

  AddressInfo({
    this.district,
    this.city,
    this.country,
    required this.displayText,
  });
}

/// Service class to handle all location-related operations.
class LocationService {
  late final g_geocoding.GoogleMapsGeocoding _googleGeocoding;

  /// Constructor for LocationService.
  LocationService() {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    assert(apiKey != null,
        'GOOGLE_MAPS_API_KEY not found in .env file. Please ensure it is set.');
    _googleGeocoding = g_geocoding.GoogleMapsGeocoding(apiKey: apiKey!);
    print("LocationService initialized.");
  }

  /// Checks if location services are enabled on the device.
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Requests foreground location permission.
  Future<bool> requestForegroundLocationPermission(
      {bool openSettingsOnError = false}) async {
    debugPrint("LocationService: Requesting foreground location permission...");

    while (true) {
      var status = await perm_handler.Permission.locationWhenInUse.status;
      debugPrint(
          "LocationService: Current foreground location permission status: $status");

      if (status.isGranted) {
        debugPrint(
            "LocationService: Foreground location permission already granted.");
        return true;
      }

      if (status.isPermanentlyDenied) {
        debugPrint(
            "LocationService: Foreground location permission permanently denied. Opening app settings...");
        if (openSettingsOnError) {
          await perm_handler.openAppSettings();
        }
        await Future.delayed(const Duration(seconds: 5));
        continue;
      }

      debugPrint(
          "LocationService: Requesting foreground location permission...");
      status = await perm_handler.Permission.locationWhenInUse.request();
      if (status.isGranted) {
        debugPrint(
            "LocationService: Foreground location permission granted after request.");
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Requests "Always Allow" background location permission.
  Future<bool> requestBackgroundLocationPermission(
      {bool openSettingsOnError = false}) async {
    debugPrint(
        "LocationService: Requesting 'Always' background location permission...");
    var status = await perm_handler.Permission.locationAlways.status;
    debugPrint(
        "LocationService: Current background location permission status: $status");

    if (status.isGranted) {
      debugPrint(
          "LocationService: 'Always' background location permission already granted.");
      return true;
    }

    status = await perm_handler.Permission.locationAlways.request();

    if (status.isGranted) {
      debugPrint(
          "LocationService: 'Always' background location permission granted.");
      return true;
    }

    if (status.isPermanentlyDenied && openSettingsOnError) {
      debugPrint(
          "LocationService: 'Always' background location permission permanently denied. Opening app settings...");
      await perm_handler.openAppSettings();
    }

    debugPrint(
        "LocationService: 'Always' background location permission denied or restricted.");
    return false;
  }

  /// Determines the current position of the device.
  Future<LocationResult<Position>> getInitialPosition() async {
    print("Attempting to retrieve initial position...");

    bool serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      print("Location services are disabled.");
      return LocationResult(
          success: false, errorMessage: 'Location services are disabled.');
    }

    bool permissionGranted =
        await requestForegroundLocationPermission(openSettingsOnError: true);
    if (!permissionGranted) {
      perm_handler.PermissionStatus status =
          await perm_handler.Permission.locationWhenInUse.status;
      String errorMessage = 'Location permission denied.';
      if (status.isPermanentlyDenied) {
        errorMessage =
            'Location permissions are permanently denied. Please enable them in app settings.';
      }
      print(errorMessage);
      return LocationResult(success: false, errorMessage: errorMessage);
    }

    try {
      print("Fetching current position...");
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
      print(
          "Initial Position - Latitude: ${position.latitude}, Longitude: ${position.longitude}");
      return LocationResult(data: position);
    } catch (e) {
      print('Error getting initial location: $e');
      return LocationResult(
          success: false,
          errorMessage: 'Failed to get location: ${e.toString()}');
    }
  }

  /// Provides a stream of position updates.
  Stream<Position> getPositionStream({
    LocationAccuracy accuracy = LocationAccuracy.low,
    int distanceFilter = 10,
  }) {
    print(
        "Setting up location updates stream with accuracy: $accuracy, distanceFilter: $distanceFilter");
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      ),
    );
  }

  /// Fetches a human-readable address info from geographic coordinates.
  Future<LocationResult<AddressInfo>> getAddressFromCoordinates(
      double latitude, double longitude) async {
    print("Fetching address for Latitude: $latitude, Longitude: $longitude");
    try {
      final response = await _googleGeocoding.searchByLocation(
        g_geocoding.Location(lat: latitude, lng: longitude),
      );

      if (response.status != "OK") {
        print(
            "Error from Geocoding API: ${response.status} - ${response.errorMessage}");
        return LocationResult(
            success: false,
            errorMessage: response.errorMessage ??
                "Failed to fetch address (API status not OK)");
      }

      if (response.results.isEmpty) {
        print("No address results found for the given coordinates.");
        return LocationResult(
            data: AddressInfo(
                displayText:
                    'Location: ${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)} (No address found)'));
      }

      final place = response.results.first;

      String? sublocality;
      String? locality;
      String? neighborhood;
      String? administrativeAreaLevel1;
      String? administrativeAreaLevel2;
      String? country;

      for (var component in place.addressComponents) {
        final types = component.types;
        if (types.contains("sublocality") ||
            types.contains("sublocality_level_1")) {
          sublocality = component.longName;
        }
        if (types.contains("neighborhood")) {
          neighborhood = component.longName;
        }
        if (types.contains("locality")) {
          locality = component.longName;
        }
        if (types.contains("administrative_area_level_1")) {
          administrativeAreaLevel1 = component.longName;
        }
        if (types.contains("administrative_area_level_2")) {
          administrativeAreaLevel2 = component.longName;
        }
        if (types.contains("country")) {
          country = component.longName;
        }
      }

      // --- LOGIC UPDATE: PRIORITY CHANGE ---

      // 1. DISTRICT: Prioritize 'locality' because in Lima, district names (La Molina, Miraflores) are in 'locality'.
      // If 'locality' is missing, fallback to 'sublocality' or 'neighborhood'.
      String? district = locality ?? sublocality ?? neighborhood;

      // 2. CITY: Prioritize Admin Area 1 (Region) or 2 (Province) to capture "Lima".
      // We do NOT check 'locality' here because we just assigned it to District.
      String? city = administrativeAreaLevel1 ?? administrativeAreaLevel2;

      // 3. Cleanup City Name
      if (city != null) {
        city = city
            .replaceAll(
                RegExp(r'\s*(Region|Province|Provincia|Departamento|de)\s*',
                    caseSensitive: false),
                ' ')
            .trim();
      }

      // 4. Safety Check: If City ended up being the same as District (rare edge case), clear City
      // so we don't save "La Molina" as both District and City.
      if (city != null &&
          district != null &&
          city.toLowerCase() == district.toLowerCase()) {
        // If they match, it likely means we are in a non-capital region where city=district.
        // But for Lima context, we want City to be "Lima".
        // If we strictly want to avoid "La Molina" as city, we might leave it null or look for admin2.
        if (administrativeAreaLevel2 != null &&
            administrativeAreaLevel2 != city) {
          city = administrativeAreaLevel2
              .replaceAll(
                  RegExp(r'\s*(Province|Provincia)\s*', caseSensitive: false),
                  ' ')
              .trim();
        }
      }

      print(
          "Parsed Location - District: $district, City: $city, Country: $country");

      // 5. Header Display Logic (Unchanged, prioritizes District)
      String displayText;
      if (district != null && country != null) {
        displayText = '$district, $country';
      } else if (city != null && country != null) {
        displayText = '$city, $country';
      } else if (district != null) {
        displayText = district;
      } else {
        displayText =
            city ?? country ?? place.formattedAddress ?? "Unknown Location";
      }

      return LocationResult(
        data: AddressInfo(
          district: district,
          city: city,
          country: country,
          displayText: displayText,
        ),
      );
    } catch (e) {
      print('Geocoding error: $e');
      return LocationResult(
          success: false, errorMessage: 'Geocoding error: ${e.toString()}');
    }
  }
}
