// lib/features/home/modals/modules/incident_status_helper.dart

import 'package:harkai/l10n/app_localizations.dart';
import 'incident_state.dart'; // IMPORT THE STATE ENUM
import 'package:harkai/features/home/utils/extensions.dart';
import 'package:harkai/features/home/utils/markers.dart';

class IncidentStatusHelper {
  static String getStatusText({
    required MediaInputState state,
    required MakerType markerType,
    required AppLocalizations localizations,
    required bool isImageMandatory,
  }) {
    final markerDetails = getMarkerInfo(markerType, localizations);
    final incidentName =
        markerDetails?.title ?? markerType.name.capitalizeAllWords();

    if (state == MediaInputState.error) {
      return localizations.incidentModalStatusError;
    }

    switch (state) {
      case MediaInputState.contactInfoInput:
        return "Información de Contacto";
      case MediaInputState.idle:
        return localizations.incidentModalStep1ReportAudioTitle(incidentName);
      case MediaInputState.textInput:
        return localizations.incidentModalReportTextTitle(incidentName);
      case MediaInputState.recordingAudio:
        return localizations.incidentModalStatusRecordingAudio;
      case MediaInputState.audioRecordedReadyToSend:
        return localizations.incidentModalStatusAudioRecorded;
      case MediaInputState.sendingAudioToGemini:
        return localizations.incidentModalStatusSendingAudioToHarki;
      case MediaInputState.audioDescriptionReadyForConfirmation:
        return localizations.incidentModalStatusConfirmAudioDescription;
      case MediaInputState.displayingConfirmedAudio:
        return isImageMandatory
            ? "Paso 2: Foto Obligatoria"
            : "Paso 2: Añadir Imagen (Opcional)";
      case MediaInputState.awaitingImageCapture:
        return localizations.incidentModalStatusCapturingImage;
      case MediaInputState.imagePreview:
        return localizations.incidentModalStatusImagePreview;
      case MediaInputState.sendingImageToGemini:
        return localizations.incidentModalStatusSendingImageToHarki;
      case MediaInputState.imageAnalyzed:
        return localizations.incidentModalStatusImageAnalyzed;
      case MediaInputState.uploadingMedia:
        return localizations.incidentModalStatusSubmittingIncident;
      default:
        return "";
    }
  }

  static String getInstructionText({
    required MediaInputState state,
    required MakerType markerType,
    required AppLocalizations localizations,
    required bool hasMicPermission,
    required String geminiAudioText,
    required String geminiImageText,
    required bool isImageApproved,
    required bool isImageMandatory,
  }) {
    final markerDetails = getMarkerInfo(markerType, localizations);
    final incidentName =
        markerDetails?.title ?? markerType.name.capitalizeAllWords();

    if (state == MediaInputState.error) {
      return geminiAudioText.isNotEmpty
          ? geminiAudioText
          : "An error occurred.";
    }

    switch (state) {
      case MediaInputState.contactInfoInput:
        return "Por favor, ingrese un número de teléfono para contactarlo si es necesario.";
      case MediaInputState.idle:
        if (!hasMicPermission)
          return localizations.incidentModalInstructionMicPermissionNeeded;
        return localizations.incidentModalInstructionHoldMic;
      case MediaInputState.textInput:
        return localizations.incidentModalInstructionEnterText;
      case MediaInputState.recordingAudio:
        return localizations.incidentModalInstructionReleaseMic;
      case MediaInputState.audioRecordedReadyToSend:
        return localizations.incidentModalInstructionSendAudioToHarki;
      case MediaInputState.sendingAudioToGemini:
        return localizations.incidentModalInstructionPleaseWait;
      case MediaInputState.audioDescriptionReadyForConfirmation:
        return localizations
            .incidentModalInstructionConfirmAudio(geminiAudioText);
      case MediaInputState.displayingConfirmedAudio:
        return isImageMandatory
            ? "Para este tipo de incidente ($incidentName), ES OBLIGATORIO adjuntar una evidencia visual antes de enviar."
            : "Puede adjuntar una imagen como evidencia adicional, o enviar el reporte solo con el audio confirmado.";
      case MediaInputState.awaitingImageCapture:
        return localizations.incidentModalInstructionUseCamera;
      case MediaInputState.imagePreview:
        return localizations.incidentModalInstructionAnalyzeRetakeRemoveImage;
      case MediaInputState.sendingImageToGemini:
        return localizations.incidentModalInstructionPleaseWait;
      case MediaInputState.imageAnalyzed:
        String imageAnalysisFeedback = geminiImageText.isNotEmpty
            ? geminiImageText
            : localizations.incidentModalImageHarkiAnalysisComplete;
        if (isImageApproved) {
          return "${localizations.incidentModalImageHarkiLooksGood}\n${localizations.incidentModalInstructionImageApproved.split('\n').sublist(1).join('\n')}";
        } else {
          return "${localizations.incidentModalImageHarkiFeedback(imageAnalysisFeedback)}\n${localizations.incidentModalInstructionImageFeedback("").split('\n').sublist(1).join('\n')}";
        }
      case MediaInputState.uploadingMedia:
        return localizations.incidentModalInstructionUploadingMedia;
      default:
        return "";
    }
  }
}
