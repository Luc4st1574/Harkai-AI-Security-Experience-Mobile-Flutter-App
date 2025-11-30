// lib/features/home/modals/modules/ui_builders.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:harkai/l10n/app_localizations.dart';
import 'incident_state.dart'; // IMPORT THE STATE ENUM

class IncidentModalUiBuilders {
  // --- Input Controls ---

  static Widget buildMicInputControl({
    required BuildContext context,
    required AppLocalizations localizations,
    required bool canRecordAudio,
    required MediaInputState currentInputState,
    required Animation<double> micScaleAnimation,
    required Color accentColor,
    required VoidCallback onLongPressStart,
    required VoidCallback onLongPressEnd,
    required VoidCallback onTapHint,
  }) {
    return GestureDetector(
      onLongPressStart: canRecordAudio ? (_) => onLongPressStart() : null,
      onLongPressEnd: currentInputState == MediaInputState.recordingAudio
          ? (_) => onLongPressEnd()
          : null,
      onTap: () {
        if (canRecordAudio &&
            currentInputState != MediaInputState.recordingAudio) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  localizations.incidentModalButtonHoldToRecordReleaseToStop)));
        } else {
          onTapHint();
        }
      },
      child: ScaleTransition(
        scale: micScaleAnimation,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: canRecordAudio ? accentColor : Colors.grey.shade700,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3), // FIXED: withValues
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 1),
              )
            ],
          ),
          child: Icon(
            currentInputState == MediaInputState.recordingAudio
                ? Icons.stop_circle_outlined
                : Icons.mic,
            color: Colors.white,
            size: 40,
          ),
        ),
      ),
    );
  }

  static Widget buildCameraInputControl({
    required AppLocalizations localizations,
    required File? capturedImageFile,
    required Color accentColor,
    required VoidCallback onPressedCapture,
    required VoidCallback onPressedGallery,
    required bool showGalleryButton,
  }) {
    String cameraButtonLabel = capturedImageFile == null
        ? localizations.incidentModalButtonAddPicture
        : localizations.incidentModalButtonRetakePicture;
    String galleryButtonLabel = localizations.incidentModalButtonAddFromGallery;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Camera Button
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt, size: 40),
                  color: accentColor,
                  padding: const EdgeInsets.all(16),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        accentColor.withValues(alpha: 0.15), // FIXED
                    shape: const CircleBorder(),
                    side: BorderSide(
                        color: accentColor.withValues(alpha: 0.7), // FIXED
                        width: 1.5),
                    elevation: 2,
                  ),
                  onPressed: onPressedCapture,
                  tooltip: cameraButtonLabel,
                ),
                const SizedBox(height: 4),
                Text(
                  cameraButtonLabel,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            // Gallery Button
            if (showGalleryButton && capturedImageFile == null) ...[
              const SizedBox(width: 20),
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_library, size: 40),
                    color: accentColor,
                    padding: const EdgeInsets.all(16),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          accentColor.withValues(alpha: 0.15), // FIXED
                      shape: const CircleBorder(),
                      side: BorderSide(
                          color: accentColor.withValues(alpha: 0.7), // FIXED
                          width: 1.5),
                      elevation: 2,
                    ),
                    onPressed: onPressedGallery,
                    tooltip: galleryButtonLabel,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    galleryButtonLabel,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ]
          ],
        ),
      ],
    );
  }

  // --- Action Buttons ---
  static Widget buildActionButtons({
    required BuildContext context,
    required AppLocalizations localizations,
    required MediaInputState currentInputState,
    required Color accentColor,
    required bool isImageApprovedByGemini,
    required VoidCallback? onSendAudioToGemini,
    required VoidCallback? onConfirmAudioAndProceed,
    required VoidCallback? onRetryFullProcessAudio,
    required VoidCallback? onSubmitWithAudioOnlyAfterConfirmation,
    required VoidCallback? onSendImageToGemini,
    required VoidCallback? onRemoveImageAndGoBackToDecision,
    required VoidCallback? onSubmitWithAudioAndImage,
    required VoidCallback? onSubmitAudioOnlyFromImageAnalyzed,
    required VoidCallback? onClearImageDataAndSubmitAudioOnlyFromAnalyzed,
    required bool allowAudioOnlySubmit,
  }) {
    List<Widget> buttons = [];

    switch (currentInputState) {
      case MediaInputState.audioRecordedReadyToSend:
        buttons.add(ElevatedButton.icon(
          icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
          label: Text(localizations.incidentModalButtonSendAudioToHarki,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          onPressed: onSendAudioToGemini,
        ));
        break;
      case MediaInputState.audioDescriptionReadyForConfirmation:
        buttons.add(ElevatedButton.icon(
          icon: const Icon(Icons.check_circle_outline,
              color: Colors.white, size: 20),
          label: Text(localizations.incidentModalButtonConfirmAudioAndProceed,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          onPressed: onConfirmAudioAndProceed,
        ));
        buttons.add(const SizedBox(height: 10));
        buttons.add(TextButton(
            onPressed: onRetryFullProcessAudio,
            child: Text(localizations.incidentModalButtonRerecordAudio,
                style: TextStyle(color: accentColor))));
        break;
      case MediaInputState.displayingConfirmedAudio:
        if (allowAudioOnlySubmit) {
          buttons.add(ElevatedButton.icon(
            icon:
                const Icon(Icons.send_outlined, color: Colors.white, size: 20),
            label: Text(localizations.incidentModalButtonSubmitWithAudioOnly,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            onPressed: onSubmitWithAudioOnlyAfterConfirmation,
          ));
        }
        break;
      case MediaInputState.imagePreview:
        buttons.add(ElevatedButton.icon(
          icon:
              const Icon(Icons.science_outlined, color: Colors.white, size: 18),
          label: Text(localizations.incidentModalButtonAnalyzeImageWithHarki,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          onPressed: onSendImageToGemini,
        ));
        buttons.add(const SizedBox(height: 10));
        if (allowAudioOnlySubmit) {
          buttons.add(TextButton(
              onPressed: onRemoveImageAndGoBackToDecision,
              child: Text(
                  localizations.incidentModalButtonUseAudioOnlyRemoveImage,
                  style: TextStyle(color: Colors.grey.shade400))));
        } else {
          buttons.add(TextButton(
              onPressed: onRemoveImageAndGoBackToDecision,
              child: Text("Quitar imagen",
                  style: TextStyle(color: Colors.grey.shade400))));
        }
        break;
      case MediaInputState.imageAnalyzed:
        if (isImageApprovedByGemini) {
          buttons.add(ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline,
                color: Colors.white, size: 20),
            label: Text(
                localizations.incidentModalButtonSubmitWithAudioAndImage,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            onPressed: onSubmitWithAudioAndImage,
          ));
          buttons.add(const SizedBox(height: 10));
          if (allowAudioOnlySubmit) {
            buttons.add(TextButton(
                onPressed: onClearImageDataAndSubmitAudioOnlyFromAnalyzed,
                child: Text(
                    localizations.incidentModalButtonSubmitAudioOnlyInstead,
                    style: TextStyle(color: Colors.grey.shade400))));
          }
        } else {
          if (allowAudioOnlySubmit) {
            buttons.add(ElevatedButton.icon(
              icon: const Icon(Icons.send_outlined,
                  color: Colors.white, size: 20),
              label: Text(localizations.incidentModalButtonSubmitWithAudioOnly,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              onPressed: onSubmitAudioOnlyFromImageAnalyzed,
            ));
          } else {
            buttons.add(const Text("Por favor, suba una imagen válida.",
                style: TextStyle(color: Colors.redAccent)));
          }
        }
        break;
      default:
        break;
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: buttons);
  }

  // --- Indicators and Messages ---

  static Widget buildProcessingIndicator({
    required Color accentColor,
    required String userInstructionText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(accentColor)),
          const SizedBox(height: 15),
          Text(userInstructionText,
              style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.8)), // FIXED
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  static Widget buildErrorControls({
    required AppLocalizations localizations,
    required Color accentColor,
    required String userInstructionText,
    required VoidCallback onRetryFullProcess,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 15.0),
          child: Text(userInstructionText,
              style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.9)), // FIXED
              textAlign: TextAlign.center),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.refresh, color: Colors.white),
          label: Text(localizations.incidentModalButtonTryAgainFromStart,
              style: const TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              padding:
                  const EdgeInsets.symmetric(horizontal: 30, vertical: 12)),
          onPressed: onRetryFullProcess,
        ),
      ],
    );
  }

  // --- Media Display Areas ---

  static Widget buildConfirmedAudioArea({
    required AppLocalizations localizations,
    required bool shouldShow,
    required String confirmedAudioDescription,
    required Color accentColor,
  }) {
    if (!shouldShow || confirmedAudioDescription.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Column(
        children: [
          Text(localizations.incidentModalAudioConfirmedAudio,
              style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2), // FIXED
                borderRadius: BorderRadius.circular(5)),
            child: Text(confirmedAudioDescription,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 10),
          Divider(color: accentColor.withValues(alpha: 0.3)), // FIXED
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  static Widget buildImagePreviewArea({
    required AppLocalizations localizations,
    required bool shouldShow,
    required File? capturedImageFile,
    required MediaInputState currentInputState,
    required bool isImageApprovedByGemini,
    required String geminiImageAnalysisResultText,
    required Color accentColor,
    required VoidCallback onRemoveImage,
  }) {
    if (!shouldShow || capturedImageFile == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Column(
        children: [
          Text(localizations.incidentModalImageForIncident,
              style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
          const SizedBox(height: 5),
          Stack(
            alignment: Alignment.topRight,
            children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(capturedImageFile,
                      height: 120, fit: BoxFit.contain)),
              if (currentInputState == MediaInputState.imagePreview ||
                  currentInputState == MediaInputState.imageAnalyzed)
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Tooltip(
                    message: localizations.incidentModalImageRemoveTooltip,
                    child: InkWell(
                      onTap: onRemoveImage,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5), // FIXED
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cancel,
                            color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                )
            ],
          ),
          if (currentInputState == MediaInputState.imageAnalyzed)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                isImageApprovedByGemini
                    ? localizations.incidentModalImageHarkiLooksGood
                    : (geminiImageAnalysisResultText.isNotEmpty
                        ? localizations.incidentModalImageHarkiFeedback(
                            geminiImageAnalysisResultText)
                        : localizations
                            .incidentModalImageHarkiAnalysisComplete),
                style: TextStyle(
                    color: isImageApprovedByGemini
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 10),
          Divider(color: accentColor.withValues(alpha: 0.3)), // FIXED
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
