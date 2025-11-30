// lib/features/incident_feed/screens/incident_screen.dart
import 'dart:async'; // Required for StreamSubscription
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:harkai/features/home/utils/incidences.dart';
import 'package:harkai/features/home/utils/markers.dart';
import 'package:harkai/features/home/widgets/header.dart';
import 'package:harkai/core/services/location_service.dart';
import 'package:harkai/features/home/screens/home.dart';
import 'package:harkai/l10n/app_localizations.dart';
// import 'package:pay/pay.dart'; // Commented out for fake button
import '../widgets/incident_tile.dart';
import '../widgets/map_view.dart';
import 'package:harkai/features/home/utils/extensions.dart';

class IncidentScreen extends StatefulWidget {
  final MakerType incidentType;
  final User? currentUser;
  // NEW: Accept current location text to show it instantly (Speed Optimization)
  final String? currentLocationText;

  const IncidentScreen({
    super.key,
    required this.incidentType,
    required this.currentUser,
    this.currentLocationText,
  });

  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final LocationService _locationService = LocationService();

  List<IncidenceData> _allFetchedIncidents = [];
  List<IncidenceData> _displayedIncidents = [];
  Position? _currentPosition;
  bool _isLoadingInitialData = true;
  String _error = '';

  // NEW: State variable for the header text
  late String _headerLocationText;

  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<List<IncidenceData>>? _incidentsStreamSubscription;

  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  // Fake loading state for donation
  bool _isFakeDonationProcessing = false;

  final TextEditingController _donationAmountController =
      TextEditingController();

  static const double _maxDistanceInMeters = 100000; // 100km

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    // Initialize header with passed text or default, so it's instant
    _headerLocationText = widget.currentLocationText ?? "Nearby Area";

    // No need to load Google Pay config for testing
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchTerm = _searchController.text;
          _processIncidentsUpdate(_allFetchedIncidents);
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_incidentsStreamSubscription == null &&
        _positionStreamSubscription == null) {
      _initializeScreenData();
    }
  }

  Future<void> _initializeScreenData() async {
    await _fetchInitialUserLocation();
    _listenToIncidents();
    _startListeningToLocationUpdates();
  }

  Future<void> _fetchInitialUserLocation() async {
    if (!mounted) return;
    setState(() {
      _isLoadingInitialData = true;
      _error = '';
    });
    try {
      final locationResult = await _locationService.getInitialPosition();
      if (!mounted) return;
      if (locationResult.success && locationResult.data != null) {
        _currentPosition = locationResult.data;
        // NEW: Fetch readable address immediately when position is found
        _updateHeaderAddress(_currentPosition!);
      } else {
        _currentPosition = null;
        _error = locationResult.errorMessage ??
            localizations.mapCurrentUserLocationNotAvailable;
      }
    } catch (e) {
      if (!mounted) return;
      _currentPosition = null;
      _error = localizations.mapErrorFetchingLocation(e.toString());
    }
  }

  // NEW: Helper to fetch address text (City, District)
  Future<void> _updateHeaderAddress(Position position) async {
    // If we already have a passed text and haven't moved far, we could skip this.
    // But fetching ensures it's accurate to the exact coordinates.
    try {
      final addressResult = await _locationService.getAddressFromCoordinates(
          position.latitude, position.longitude);

      if (mounted && addressResult.success && addressResult.data != null) {
        setState(() {
          _headerLocationText = addressResult.data!.displayText;
        });
      }
    } catch (e) {
      debugPrint("Error fetching address for header: $e");
    }
  }

  String _formatDistance(
      double distanceInMeters, AppLocalizations localizations) {
    if (distanceInMeters < 1000) {
      return localizations
          .incidentTileDistanceMeters(distanceInMeters.toStringAsFixed(0));
    } else {
      double distanceInKm = distanceInMeters / 1000;
      return localizations
          .incidentTileDistanceKm(distanceInKm.toStringAsFixed(1));
    }
  }

  // --- Helper Methods for "On Pop" Modal Logic ---

  List<String> _getSearchTerms(MakerType type) {
    switch (type) {
      case MakerType.pet:
        return ['vet'];
      case MakerType.emergency:
        // Excluded 'vet' terms here, but we also check explicitly below
        return ['hosp', 'clin', 'med', 'emerg', 'salud', 'health'];
      case MakerType.fire:
        return ['bomb', 'fire', 'estaci'];
      case MakerType.crash:
        return ['mec', 'tall', 'tow', 'grua', 'auto', 'carr'];
      case MakerType.theft:
        return ['comis', 'polic', 'estac'];
      default:
        return [];
    }
  }

  String _getModalTitle(MakerType type) {
    final isSpanish = localizations.localeName == 'es';
    switch (type) {
      case MakerType.pet:
        return localizations.nearbyVetsTitle;
      case MakerType.emergency:
        return isSpanish ? 'Hospitales Cercanos' : 'Nearby Hospitals';
      case MakerType.fire:
        return isSpanish ? 'Estaciones de Bomberos' : 'Fire Stations';
      case MakerType.crash:
        return isSpanish ? 'Mecánicos y Grúas' : 'Mechanics & Towing';
      case MakerType.theft:
        return isSpanish ? 'Comisarías Cercanas' : 'Nearby Police Stations';
      default:
        return localizations.placesIncidentFeedTitle;
    }
  }

  IconData _getModalIcon(MakerType type) {
    switch (type) {
      case MakerType.pet:
        return Icons.pets;
      case MakerType.emergency:
        return Icons.local_hospital;
      case MakerType.fire:
        return Icons.local_fire_department;
      case MakerType.crash:
        return Icons.car_repair;
      case MakerType.theft:
        return Icons.local_police;
      default:
        return Icons.place;
    }
  }

  Future<bool?> _showNearbyPlacesModal(
      List<IncidenceData> places, String title) async {
    final markerInfo = getMarkerInfo(widget.incidentType, localizations);
    final Color accentColor = markerInfo?.color ?? Colors.blueGrey;
    final IconData icon = _getModalIcon(widget.incidentType);

    return await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF011935),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
            side: BorderSide(color: accentColor, width: 2),
          ),
          title: Text(
            title,
            style: TextStyle(color: accentColor, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: places.length,
              itemBuilder: (context, index) {
                final place = places[index];
                return Card(
                  color: Colors.black.withOpacity(0.2),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: Icon(icon, color: accentColor, size: 28),
                    title: Text(place.description,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: place.distance != null
                        ? Text(
                            _formatDistance(place.distance!, localizations),
                            style: const TextStyle(color: Colors.white70),
                          )
                        : null,
                    onTap: () {
                      Navigator.of(dialogContext).pop(false);
                      _navigateToIncidentMap(place);
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(localizations.incidentImageModalCloseButton,
                    style: TextStyle(color: accentColor))),
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(localizations.exitScreenButton,
                    style: TextStyle(color: Colors.red.shade400))),
          ],
        );
      },
    );
  }

  // --- End Helper Methods ---

  void _listenToIncidents() {
    if (!mounted) return;
    _incidentsStreamSubscription?.cancel();

    if (_currentPosition == null ||
        (_isLoadingInitialData && _allFetchedIncidents.isEmpty)) {
      setState(() {
        _isLoadingInitialData = true;
      });
    }

    Stream<List<IncidenceData>> incidentsStream =
        _firestoreService.getIncidencesStream();

    _incidentsStreamSubscription = incidentsStream.listen(
      (incidents) {
        if (!mounted) return;
        _allFetchedIncidents = incidents;
        _processIncidentsUpdate(_allFetchedIncidents);
        setState(() {
          _isLoadingInitialData = false;
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _error = localizations.incidentReportFailed("incidents");
          _allFetchedIncidents = [];
          _displayedIncidents = [];
          _isLoadingInitialData = false;
        });
      },
    );
  }

  void _startListeningToLocationUpdates() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = _locationService.getPositionStream().listen(
      (Position newPosition) {
        if (mounted) {
          final bool positionChangedSignificantly = _currentPosition == null ||
              Geolocator.distanceBetween(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                    newPosition.latitude,
                    newPosition.longitude,
                  ) >
                  50;

          _currentPosition = newPosition;

          // NEW: Update address text if user moved significantly (e.g. > 100m)
          // Using a slightly larger threshold for address text to avoid flickering
          if (_currentPosition != null &&
              Geolocator.distanceBetween(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                    newPosition.latitude,
                    newPosition.longitude,
                  ) >
                  100) {
            _updateHeaderAddress(newPosition);
          }

          if (positionChangedSignificantly) {
            _processIncidentsUpdate(List.from(_allFetchedIncidents));
          }
        }
      },
      onError: (error) {
        debugPrint("Error in IncidentScreen location stream: $error");
        if (mounted) {
          setState(() {
            _error = localizations.mapErrorFetchingLocation(error.toString());
          });
        }
      },
    );
  }

  // Helper to remove accents for better matching (e.g., 'grúa' -> 'grua')
  String _removeDiacritics(String str) {
    return str
        .replaceAll(RegExp(r'[áÁ]'), 'a')
        .replaceAll(RegExp(r'[éÉ]'), 'e')
        .replaceAll(RegExp(r'[íÍ]'), 'i')
        .replaceAll(RegExp(r'[óÓ]'), 'o')
        .replaceAll(RegExp(r'[úÚüÜ]'), 'u')
        .replaceAll(RegExp(r'[ñÑ]'), 'n');
  }

  void _processIncidentsUpdate(List<IncidenceData> allIncidents) {
    if (!mounted) return;

    List<IncidenceData> filteredIncidents = allIncidents
        .where((incident) => incident.type == widget.incidentType)
        .toList();

    if (_currentPosition != null) {
      filteredIncidents.removeWhere((incident) {
        final distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          incident.latitude,
          incident.longitude,
        );
        incident.distance = distance;
        return distance > _maxDistanceInMeters;
      });
    } else {
      for (var incident in filteredIncidents) {
        incident.distance = null;
      }
    }

    if (_searchTerm.isNotEmpty) {
      final String normalizedSearchTerm =
          _removeDiacritics(_searchTerm.toLowerCase());

      filteredIncidents.removeWhere((incident) {
        final String normalizedDesc =
            _removeDiacritics(incident.description.toLowerCase());
        return !normalizedDesc.contains(normalizedSearchTerm);
      });
    }

    // UPDATED: Include Event in the 24-hour expiry check along with Pet
    if (widget.incidentType == MakerType.pet ||
        widget.incidentType == MakerType.event) {
      final now = DateTime.now();
      final twentyFourHoursAgo = now.subtract(const Duration(days: 1));
      filteredIncidents.removeWhere((incident) {
        return incident.timestamp.toDate().isBefore(twentyFourHoursAgo);
      });
    } else if (widget.incidentType != MakerType.place) {
      // Standard 3-hour expiry for other types, skipping Places
      final now = DateTime.now();
      final threeHoursAgo = now.subtract(const Duration(hours: 3));
      filteredIncidents.removeWhere((incident) {
        return incident.timestamp.toDate().isBefore(threeHoursAgo);
      });
    }

    if (_currentPosition != null) {
      filteredIncidents.sort((a, b) => (a.distance ?? double.maxFinite)
          .compareTo(b.distance ?? double.maxFinite));
    }

    bool listChanged = true;
    if (_displayedIncidents.length == filteredIncidents.length) {
      listChanged = false;
      for (int i = 0; i < _displayedIncidents.length; i++) {
        if (_displayedIncidents[i].id != filteredIncidents[i].id) {
          listChanged = true;
          break;
        }
      }
    }

    if (listChanged) {
      setState(() {
        _displayedIncidents = filteredIncidents;
      });
    }
  }

  void _navigateToIncidentMap(IncidenceData incident) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.05,
            vertical: screenHeight * 0.1,
          ),
          child: SizedBox(
            width: screenWidth * 0.9,
            height: screenHeight * 0.7,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(15.0),
                  child: IncidentMapViewContent(
                    incident: incident,
                    incidentTypeForExpiry: widget.incidentType,
                  ),
                ),
                Positioned(
                  top: 8.0,
                  left: 8.0,
                  child: Material(
                    color: Colors.black.withOpacity(0.6),
                    shape: const CircleBorder(),
                    elevation: 4.0,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20.0),
                      onTap: () => Navigator.of(dialogContext).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(6.0),
                        child: Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getScreenTitleText() {
    final markerInfo = getMarkerInfo(widget.incidentType, localizations);
    return localizations.incidentScreenTitle(
        markerInfo?.title ?? widget.incidentType.name.capitalizeAllWords());
  }

  void _showDonationModal() {
    final markerInfo = getMarkerInfo(widget.incidentType, localizations);
    final Color accentColor = markerInfo?.color ?? Colors.blueGrey;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        // Using StatefulBuilder to manage loading state inside the dialog
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              backgroundColor: const Color(0xFF011935),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
                side: BorderSide(color: accentColor, width: 2),
              ),
              title: Text(
                localizations.donationDialogTitle,
                style:
                    TextStyle(color: accentColor, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              content: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _donationAmountController,
                builder: (context, value, child) {
                  final amount =
                      value.text.trim().isEmpty ? "0.00" : value.text.trim();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        localizations.donationDialogContent(amount),
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _donationAmountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: localizations.donationAmountHint,
                          hintStyle:
                              TextStyle(color: Colors.white.withOpacity(0.7)),
                          prefixIcon:
                              Icon(Icons.attach_money, color: accentColor),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30.0),
                            borderSide:
                                BorderSide(color: accentColor.withOpacity(0.5)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30.0),
                            borderSide: BorderSide(color: accentColor),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // --- FAKE GOOGLE PAY BUTTON (White) ---
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isFakeDonationProcessing
                              ? null
                              : () async {
                                  // 1. Show loading spinner
                                  setStateModal(
                                      () => _isFakeDonationProcessing = true);

                                  // 2. Simulate network delay (1.5 seconds)
                                  await Future.delayed(
                                      const Duration(milliseconds: 1500));

                                  // 3. Success Logic
                                  if (context.mounted) {
                                    Navigator.pop(dialogContext); // Close Modal
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(localizations
                                              .donationSuccessMessage)),
                                    );
                                    _donationAmountController.clear();
                                  }

                                  // Reset state
                                  _isFakeDonationProcessing = false;
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white, // White background
                            foregroundColor: Colors.grey[200], // Ripple
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          child: _isFakeDonationProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  // Black spinner on white bg
                                  child: CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 2))
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
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
                  );
                },
              ),
              actions: [
                if (!_isFakeDonationProcessing)
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(
                      localizations.incidentImageModalCloseButton,
                      style: TextStyle(color: accentColor),
                    ),
                  )
              ],
            );
          },
        );
      },
    );
    // Reset flag just in case
    _isFakeDonationProcessing = false;
  }

  @override
  Widget build(BuildContext context) {
    final markerInfo = getMarkerInfo(widget.incidentType, localizations);
    final Color incidentColor = markerInfo?.color ?? Colors.blueGrey;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        final List<String> searchTerms = _getSearchTerms(widget.incidentType);

        if (searchTerms.isNotEmpty) {
          final nearbyPlaces = _allFetchedIncidents.where((incident) {
            if (incident.type != MakerType.place) return false;

            // UPDATED: Accent-proof check using _removeDiacritics
            final String normalizedDesc =
                _removeDiacritics(incident.description.toLowerCase());

            // 1. Must match at least one positive term (e.g. 'hospital')
            final bool matchesPositive = searchTerms.any((term) {
              final String normalizedTerm =
                  _removeDiacritics(term.toLowerCase());
              return normalizedDesc.contains(normalizedTerm);
            });

            if (!matchesPositive) return false;

            // 2. Specific exclusion: If Emergency, exclude 'vet'
            //    This ensures "Clinica Veterinaria" doesn't show up for "Clinica" search
            if (widget.incidentType == MakerType.emergency) {
              if (normalizedDesc.contains('vet') ||
                  normalizedDesc.contains('veterin')) {
                return false;
              }
            }

            return true;
          }).toList();

          if (_currentPosition != null) {
            for (var place in nearbyPlaces) {
              place.distance = Geolocator.distanceBetween(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                  place.latitude,
                  place.longitude);
            }
            nearbyPlaces.sort((a, b) => (a.distance ?? double.maxFinite)
                .compareTo(b.distance ?? double.maxFinite));
          }

          if (nearbyPlaces.isEmpty) {
            if (mounted) Navigator.of(context).pop();
            return;
          }

          final bool? shouldPop = await _showNearbyPlacesModal(
            nearbyPlaces,
            _getModalTitle(widget.incidentType),
          );

          if (shouldPop == true && mounted) {
            Navigator.of(context).pop();
          }
        } else {
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF001F3F),
        body: SafeArea(
          child: Column(
            children: [
              HomeHeaderWidget(
                currentUser: widget.currentUser,
                onLogoTap: () {
                  Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const Home()),
                      (Route<dynamic> route) => false);
                },
                isLongPressEnabled: false,
                // UPDATED: Now uses dynamic location text
                locationText: _headerLocationText,
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                child: Text(
                  _getScreenTitleText(),
                  style: const TextStyle(
                    color: Color(0xFF57D463),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: localizations.hintSearch,
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                    prefixIcon: Icon(Icons.search,
                        color: Colors.white.withOpacity(0.7)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30.0),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30.0),
                      borderSide: const BorderSide(color: Color(0xFF57D463)),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                    suffixIcon: _searchTerm.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear,
                                color: Colors.white.withOpacity(0.7)),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 10.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(25),
                        spreadRadius: 0,
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _buildBody(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.favorite, color: Colors.white),
                    label: Text(
                      localizations.donationButtonText,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: incidentColor,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30.0),
                      ),
                      elevation: 5.0,
                    ),
                    onPressed: _showDonationModal,
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoadingInitialData && _displayedIncidents.isEmpty) {
      return Center(
          child:
              CircularProgressIndicator(color: Theme.of(context).primaryColor));
    }
    if (_error.isNotEmpty && _displayedIncidents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_error,
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center),
        ),
      );
    }
    if (_displayedIncidents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _searchTerm.isNotEmpty
                ? localizations.searchNoResults + _searchTerm
                : localizations.incidentFeedNoIncidentsFound(
                    getMarkerInfo(widget.incidentType, localizations)?.title ??
                        widget.incidentType.name.capitalizeAllWords()),
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _displayedIncidents.length,
      itemBuilder: (context, index) {
        final incident = _displayedIncidents[index];
        return IncidentTile(
          incident: incident,
          distance: incident.distance,
          onTap: () => _navigateToIncidentMap(incident),
          localizations: localizations,
        );
      },
    );
  }

  @override
  void dispose() {
    _donationAmountController.dispose();
    _searchController.removeListener(() {});
    _searchController.dispose();
    _positionStreamSubscription?.cancel();
    _incidentsStreamSubscription?.cancel();
    super.dispose();
  }
}
