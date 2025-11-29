import 'package:google_maps_flutter/google_maps_flutter.dart'
    show BitmapDescriptor;
import 'package:flutter/material.dart';
import 'package:harkai/l10n/app_localizations.dart';

/// Enum representing the different types of alerts the user can create or see.
enum MakerType {
  fire,
  crash,
  theft,
  pet,
  emergency,
  place,
  event, // Added Event type
  none,
}

/// Class holding display information and emergency contact details for each alert type.
class MarkerInfo {
  final String title;
  final String emergencyNumber;
  final String agent;
  final Color? color;
  final String? iconPath;

  /// Constructor for MarkerInfo.
  MarkerInfo({
    required this.title,
    required this.emergencyNumber,
    required this.agent,
    this.color,
    this.iconPath,
  });
}

// Function that returns a localized map of MarkerInfo
Map<MakerType, MarkerInfo> getLocalizedMarkerInfoMap(
    AppLocalizations localizations) {
  return {
    MakerType.fire: MarkerInfo(
      title: localizations.homeFireAlertButtonTitle,
      emergencyNumber: '(044) 226495',
      agent: localizations.agentFirefighters,
      color: Colors.orange,
      iconPath: 'assets/images/fire.png',
    ),
    MakerType.crash: MarkerInfo(
      title: localizations.homeCrashAlertButtonTitle,
      emergencyNumber: '(044) 484242',
      agent: localizations.agentSerenazgo,
      color: Colors.blue,
      iconPath: 'assets/images/car.png',
    ),
    MakerType.theft: MarkerInfo(
      title: localizations.homeTheftAlertButtonTitle,
      emergencyNumber: '(044) 250664',
      agent: localizations.agentPolice,
      color: Colors.purple,
      iconPath: 'assets/images/theft.png',
    ),
    MakerType.pet: MarkerInfo(
      title: localizations.homePetAlertButtonTitle,
      emergencyNumber: '913684363',
      agent: localizations.agentShelter,
      color: Colors.brown,
      iconPath: 'assets/images/dog.png',
    ),
    MakerType.emergency: MarkerInfo(
        title: localizations.homeCallEmergenciesButton,
        emergencyNumber: '911',
        agent: localizations.agentEmergencies,
        color: Colors.red.shade900,
        iconPath: 'assets/images/alert.png'),
    MakerType.place: MarkerInfo(
      title: localizations.addPlaceButtonTitle,
      emergencyNumber: '',
      agent: localizations.placeMarkerName,
      color: Colors.yellow.shade700,
      iconPath: 'assets/images/place_icon.png',
    ),
    MakerType.event: MarkerInfo(
      title: 'Eventos', // Using string literal as placeholder
      emergencyNumber: '',
      agent: 'Organizer',
      color: Colors.green, // Green color as requested
      iconPath: 'assets/images/events_icon.png',
    ),
  };
}

/// Utility function to safely get [MarkerInfo] using AppLocalizations.
MarkerInfo? getMarkerInfo(MakerType type, AppLocalizations localizations) {
  if (type == MakerType.none) return null;
  return getLocalizedMarkerInfoMap(localizations)[type];
}

/// Utility functions related to map display and operations.
BitmapDescriptor getMarkerBitmap(MakerType type, {BitmapDescriptor? petIcon}) {
  switch (type) {
    case MakerType.fire:
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    case MakerType.crash:
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    case MakerType.theft:
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
    case MakerType.pet:
      return petIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueMagenta);
    case MakerType.emergency:
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    case MakerType.place:
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    case MakerType.event:
      return BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueGreen); // Green for events
    case MakerType.none:
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
  }
}

/// Gets the localized service name for the call button based on the selected alert.
String getCallButtonEmergencyNumber(
    MakerType selectedAlert, AppLocalizations localizations) {
  final MarkerInfo? alertInfo;
  if (selectedAlert == MakerType.none || selectedAlert == MakerType.emergency) {
    alertInfo = getMarkerInfo(MakerType.emergency, localizations);
  } else {
    alertInfo = getMarkerInfo(selectedAlert, localizations);
  }
  return alertInfo?.emergencyNumber ?? '911';
}

String getCallButtonServiceName(
    MakerType selectedAlert, AppLocalizations localizations) {
  final MarkerInfo? alertInfo;
  if (selectedAlert == MakerType.none) {
    alertInfo = getMarkerInfo(MakerType.emergency, localizations);
    return localizations.homeCallAgentButton(
        alertInfo?.agent ?? localizations.agentEmergencies);
  }

  alertInfo = getMarkerInfo(selectedAlert, localizations);
  return localizations
      .homeCallAgentButton(alertInfo?.agent ?? localizations.agentEmergencies);
}
