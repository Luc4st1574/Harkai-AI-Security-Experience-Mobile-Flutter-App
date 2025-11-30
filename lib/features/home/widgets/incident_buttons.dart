import 'package:flutter/material.dart';
import '../../home/utils/markers.dart';
import 'package:harkai/l10n/app_localizations.dart';

/// A widget that displays a grid of incident buttons.
class IncidentButtonsGridWidget extends StatelessWidget {
  final MakerType selectedIncident;
  final Function(MakerType) onIncidentButtonPressed;
  final Function(MakerType) onIncidentButtonLongPressed;

  const IncidentButtonsGridWidget({
    super.key,
    required this.selectedIncident,
    required this.onIncidentButtonPressed,
    required this.onIncidentButtonLongPressed,
  });

  @override
  Widget build(BuildContext context) {
    const double gridSpacing = 12.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Theft (Left) - Fire (Right)
          Row(
            children: [
              Expanded(
                child: _IndividualIncidentButton(
                  markerType: MakerType.theft,
                  isSelected: selectedIncident == MakerType.theft,
                  onPressed: () => onIncidentButtonPressed(MakerType.theft),
                  onLongPressed: () =>
                      onIncidentButtonLongPressed(MakerType.theft),
                ),
              ),
              const SizedBox(width: gridSpacing),
              Expanded(
                child: _IndividualIncidentButton(
                  markerType: MakerType.fire,
                  isSelected: selectedIncident == MakerType.fire,
                  onPressed: () => onIncidentButtonPressed(MakerType.fire),
                  onLongPressed: () =>
                      onIncidentButtonLongPressed(MakerType.fire),
                ),
              ),
            ],
          ),
          const SizedBox(height: gridSpacing),

          // Row 2: Emergency (Left) - Crash (Right)
          Row(
            children: [
              Expanded(
                child: _IndividualIncidentButton(
                  markerType: MakerType.emergency,
                  isSelected: selectedIncident == MakerType.emergency,
                  onPressed: () => onIncidentButtonPressed(MakerType.emergency),
                  onLongPressed: () =>
                      onIncidentButtonLongPressed(MakerType.emergency),
                ),
              ),
              const SizedBox(width: gridSpacing),
              Expanded(
                child: _IndividualIncidentButton(
                  markerType: MakerType.crash,
                  isSelected: selectedIncident == MakerType.crash,
                  onPressed: () => onIncidentButtonPressed(MakerType.crash),
                  onLongPressed: () =>
                      onIncidentButtonLongPressed(MakerType.crash),
                ),
              ),
            ],
          ),
          const SizedBox(height: gridSpacing),

          // Row 3: Pet (Full Width)
          Row(
            children: [
              Expanded(
                child: _IndividualIncidentButton(
                  markerType: MakerType.pet,
                  isSelected: selectedIncident == MakerType.pet,
                  onPressed: () => onIncidentButtonPressed(MakerType.pet),
                  onLongPressed: () =>
                      onIncidentButtonLongPressed(MakerType.pet),
                ),
              ),
            ],
          ),
          const SizedBox(height: gridSpacing),

          // Row 4: Event (Full Width)
          Row(
            children: [
              Expanded(
                child: _IndividualIncidentButton(
                  markerType: MakerType.event,
                  isSelected: selectedIncident == MakerType.event,
                  onPressed: () => onIncidentButtonPressed(MakerType.event),
                  onLongPressed: () =>
                      onIncidentButtonLongPressed(MakerType.event),
                ),
              ),
            ],
          ),
          const SizedBox(height: gridSpacing),

          // Row 5: Places (Full Width)
          Row(
            children: [
              Expanded(
                child: _IndividualIncidentButton(
                  markerType: MakerType.place,
                  isSelected: selectedIncident == MakerType.place,
                  onPressed: () => onIncidentButtonPressed(MakerType.place),
                  onLongPressed: () =>
                      onIncidentButtonLongPressed(MakerType.place),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IndividualIncidentButton extends StatelessWidget {
  final MakerType markerType;
  final bool isSelected;
  final VoidCallback onPressed;
  final VoidCallback? onLongPressed;

  const _IndividualIncidentButton({
    required this.markerType,
    required this.isSelected,
    required this.onPressed,
    this.onLongPressed,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final MarkerInfo? markerDetails = getMarkerInfo(markerType, localizations);
    String title = markerDetails?.title ?? 'Error';

    final Color buttonColor = markerDetails?.color ?? Colors.grey.shade700;
    final String iconPath =
        markerDetails?.iconPath ?? 'assets/images/alert.png';
    final AssetImage iconAsset = AssetImage(iconPath);
    const double iconSize = 20.0;
    const double fontSize = 13.0;
    const FontWeight fontWeight = FontWeight.bold;
    const double buttonElevation = 5.0;
    const EdgeInsets buttonPadding =
        EdgeInsets.symmetric(vertical: 14, horizontal: 10);

    return ElevatedButton(
      onPressed: onPressed,
      onLongPress: onLongPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonColor,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        padding: buttonPadding,
        elevation: isSelected ? buttonElevation + 2 : buttonElevation,
        side: isSelected
            ? const BorderSide(color: Colors.white, width: 2.0)
            : BorderSide.none,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image(
            image: iconAsset,
            height: iconSize,
            width: iconSize,
            color: Colors.white,
            errorBuilder: (context, error, stackTrace) {
              return Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: iconSize);
            },
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: fontWeight,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
