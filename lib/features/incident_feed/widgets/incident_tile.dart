import 'package:flutter/material.dart';
import 'package:harkai/features/home/utils/incidences.dart';
import 'package:harkai/features/home/utils/markers.dart';
import 'package:harkai/l10n/app_localizations.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:harkai/core/services/phone_service.dart'; // Import PhoneService

class IncidentTile extends StatelessWidget {
  final IncidenceData incident;
  final double? distance; // in meters
  final VoidCallback onTap;
  final AppLocalizations localizations;
  final PhoneService phoneService;

  const IncidentTile({
    super.key,
    required this.incident,
    this.distance,
    required this.onTap,
    required this.localizations,
    required this.phoneService,
  });

  @override
  Widget build(BuildContext context) {
    final MarkerInfo? markerDetails =
        getMarkerInfo(incident.type, localizations);
    final Color iconAccentColor =
        markerDetails?.color ?? Colors.grey; // Color for the icon fallback
    final String iconPath =
        markerDetails?.iconPath ?? 'assets/images/alert.png';
    final DateFormat timeFormat =
        DateFormat('hh:mm a', localizations.localeName);
    final String incidentTime = timeFormat.format(incident.timestamp.toDate());

    // Logic to determine if phone button should be shown
    final bool showPhoneButton = incident.type == MakerType.pet ||
        incident.type == MakerType.event ||
        incident.type == MakerType.place;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD), // New background color for the tile
        borderRadius: BorderRadius.circular(12.0), // Existing border radius
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(
                (0.1 * 255).round()), // Shadow color: rgba(0,0,0,0.1)
            offset: const Offset(0, 2), // Shadow offset: 0 2px
            blurRadius: 6.0, // Shadow blur radius: 6px
          ),
        ],
      ),
      child: Material(
        // Material widget for InkWell splash and clipping
        color: Colors.transparent, // So Container's color shows through
        borderRadius: BorderRadius.circular(12.0),
        child: InkWell(
          onTap: onTap,
          borderRadius:
              BorderRadius.circular(12.0), // Match shape for splash effect
          child: Padding(
            // Reverted to 12.0 to keep height compact
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment
                  .center, // Vertically center items in the main row
              children: [
                // Left: Image or Icon
                SizedBox(
                  width: 60,
                  height: 60,
                  child: incident.imageUrl != null &&
                          incident.imageUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: Image.network(
                            incident.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildIconFallback(iconPath, iconAccentColor),
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      iconAccentColor),
                                  strokeWidth: 2.0,
                                ),
                              );
                            },
                          ),
                        )
                      : _buildIconFallback(iconPath, iconAccentColor),
                ),
                const SizedBox(width: 12),
                // Right: Description, Distance, Time OR Phone Button
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment
                        .center, // Vertically center text content
                    children: [
                      // Title (Description)
                      Text(
                        incident.description.isNotEmpty
                            ? incident.description
                            : (markerDetails?.title ??
                                localizations.incidentTileDefaultTitle),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15.0,
                          color: Colors
                              .black87, // Text color suitable for light blue background
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // Bottom Row: Distance ... [Time OR PhoneButton]
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (distance != null)
                            Text(
                              _formatDistance(distance!, localizations),
                              style: const TextStyle(
                                fontSize: 13.0,
                                color: Colors
                                    .black54, // Text color suitable for light blue
                              ),
                            ),

                          // Show Icon-only Phone Button OR Time
                          if (showPhoneButton)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  // UPDATED: Call the new method
                                  phoneService.makePhoneCallFromIncidentId(
                                      incidentId: incident.id,
                                      context: context);
                                },
                                child: Container(
                                  width: 32, // Fixed width for perfect circle
                                  height: 32, // Fixed height for perfect circle
                                  alignment:
                                      Alignment.center, // Center the icon
                                  decoration: BoxDecoration(
                                    color:
                                        iconAccentColor, // Use incident color
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.phone,
                                      color: Colors.white, size: 16 // Icon size
                                      ),
                                ),
                              ),
                            )
                          else
                            Text(
                              incidentTime,
                              style: const TextStyle(
                                fontSize: 13.0,
                                color: Colors
                                    .black54, // Text color suitable for light blue
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconFallback(String iconPath, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withAlpha((0.15 * 255)
            .round()), // Slightly more opaque for better visibility on light blue
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Image.asset(
          iconPath,
          color: color, // Icon itself can retain its original accent color
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.warning_amber_rounded, color: color, size: 30),
        ),
      ),
    );
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
}
