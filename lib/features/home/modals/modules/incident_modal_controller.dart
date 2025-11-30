// lib/features/home/modals/modules/incident_modal_controller.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

import 'media_services.dart';
import 'media_handler.dart';
import 'incident_state.dart';
import 'package:harkai/core/services/storage_service.dart';
import 'package:harkai/features/home/utils/extensions.dart';
import 'package:harkai/features/home/utils/markers.dart';

class IncidentModalController extends ChangeNotifier {
  // --- Dependencies ---
  final IncidentMediaServices _mediaServices = IncidentMediaServices();
  final DeviceMediaHandler _deviceMediaHandler = DeviceMediaHandler();
  final StorageService _storageService = StorageService();
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // --- State Variables ---
  MediaInputState currentInputState = MediaInputState.idle;

  // ESTE ES EL TIPO REAL ACTUALMENTE SELECCIONADO
  MakerType currentMarkerType;

  // NUEVO: Almacena la sugerencia de la IA si hay mismatch
  MakerType? pendingSuggestedType;

  String? recordedAudioPath;
  String geminiAudioProcessedText = '';
  String confirmedAudioDescription = '';
  File? capturedImageFile;
  String geminiImageAnalysisResultText = '';
  bool isImageApprovedByGemini = false;
  String? uploadedImageUrl;

  bool hasMicPermission = false;

  final TextEditingController textEditingController = TextEditingController();
  final TextEditingController contactInfoController = TextEditingController();

  IncidentModalController({required this.currentMarkerType});

  // --- Initialization ---
  Future<void> initialize() async {
    var micStatus = await _mediaServices.getMicrophonePermissionStatus();
    hasMicPermission = micStatus.isGranted;

    if (!hasMicPermission) {
      hasMicPermission = await _mediaServices.requestMicrophonePermission(
          openSettingsOnError: true);
    }

    try {
      _mediaServices.initializeGeminiModel();
    } catch (e) {
      setErrorState("Error initializing AI: $e");
      return;
    }

    if (needsContactInfo()) {
      currentInputState = MediaInputState.contactInfoInput;
    } else {
      currentInputState = MediaInputState.idle;
    }
    notifyListeners();
  }

  // --- Helpers ---
  bool needsContactInfo() {
    return currentMarkerType == MakerType.pet ||
        currentMarkerType == MakerType.event ||
        currentMarkerType == MakerType.place;
  }

  bool isImageMandatory() {
    return currentMarkerType == MakerType.pet ||
        currentMarkerType == MakerType.event ||
        currentMarkerType == MakerType.place;
  }

  void setErrorState(String message) {
    currentInputState = MediaInputState.error;
    geminiAudioProcessedText = message;
    notifyListeners();
  }

  // --- Actions ---

  // Método para cambiar el tipo manualmente o por IA
  void changeIncidentType(MakerType newType) {
    if (currentMarkerType != newType) {
      currentMarkerType = newType;
      pendingSuggestedType = null; // Limpiar sugerencias pendientes
      notifyListeners();
    }
  }

  // Método para aplicar la sugerencia de la IA
  void applySuggestedChange() {
    if (pendingSuggestedType != null) {
      changeIncidentType(pendingSuggestedType!);
      geminiAudioProcessedText = ""; // Limpiar error
      currentInputState =
          MediaInputState.idle; // Volver a empezar con el nuevo tipo
      notifyListeners();
    }
  }

  void submitContactInfo() {
    currentInputState = MediaInputState.idle;
    notifyListeners();
  }

  Future<bool> startRecording() async {
    _clearAllMediaData(updateState: false);
    if (!hasMicPermission) return false;

    recordedAudioPath = await _deviceMediaHandler.getTemporaryFilePath("m4a");
    const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 48000);

    final successPath = await _deviceMediaHandler.startRecording(
        filePath: recordedAudioPath!, config: config);

    if (successPath != null) {
      recordedAudioPath = successPath;
      currentInputState = MediaInputState.recordingAudio;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> stopRecording() async {
    final path = await _deviceMediaHandler.stopRecording();
    if (path != null) {
      recordedAudioPath = path;
      currentInputState = MediaInputState.audioRecordedReadyToSend;
    } else {
      recordedAudioPath = null;
      currentInputState = MediaInputState.idle;
    }
    notifyListeners();
  }

  Future<void> sendAudioToGemini() async {
    if (recordedAudioPath == null) return;
    currentInputState = MediaInputState.sendingAudioToGemini;
    notifyListeners();

    try {
      final audioFile = File(recordedAudioPath!);
      final Uint8List audioBytes = await audioFile.readAsBytes();
      final String incidentTypeName = currentMarkerType.name.split('.').last;

      final text = await _mediaServices.analyzeAudioWithGemini(
        audioBytes: audioBytes,
        audioMimeType: "audio/mp4",
        incidentTypeName: incidentTypeName,
      );
      _processGeminiResponse(text);
    } catch (e) {
      setErrorState(e.toString());
    }
  }

  Future<void> sendTextToGemini() async {
    if (textEditingController.text.isEmpty) return;
    currentInputState = MediaInputState.sendingAudioToGemini;
    notifyListeners();

    try {
      final incidentTypeName = currentMarkerType.name.split('.').last;
      final response = await _mediaServices.analyzeTextWithGemini(
        text: textEditingController.text,
        incidentTypeName: incidentTypeName,
      );
      _processGeminiResponse(response);
    } catch (e) {
      setErrorState(e.toString());
    }
  }

  // Lógica principal de procesamiento de respuesta
  void _processGeminiResponse(String? text) {
    pendingSuggestedType = null; // Reset

    if (text != null && text.isNotEmpty) {
      if (text.startsWith("MATCH:")) {
        geminiAudioProcessedText = text.substring("MATCH:".length).trim();
        currentInputState =
            MediaInputState.audioDescriptionReadyForConfirmation;
        notifyListeners();
      } else if (text.startsWith("MISMATCH:")) {
        // AUTOMATIZACIÓN: Extraer el tipo sugerido
        String suggestedTypeStr = text.substring("MISMATCH:".length).trim();
        // Limpiar puntuación extra
        suggestedTypeStr = suggestedTypeStr.replaceAll(RegExp(r'[^\w\s]'), '');

        MakerType? newType = _mapStringToMakerType(suggestedTypeStr);

        if (newType != null && newType != currentMarkerType) {
          // Guardamos la sugerencia
          pendingSuggestedType = newType;
          geminiAudioProcessedText =
              "Parece que esto es un incidente de tipo: ${newType.name.toUpperCase()}.";
          // Usamos estado de error para mostrar la UI de decisión
          currentInputState = MediaInputState.error;
          notifyListeners();
          return;
        }
        // Si no se reconoce el tipo, error genérico
        geminiAudioProcessedText = text;
        currentInputState = MediaInputState.error;
        notifyListeners();
      } else {
        // UNCLEAR u otros
        geminiAudioProcessedText = text.replaceFirst("UNCLEAR:", "").trim();
        currentInputState = MediaInputState.error;
        notifyListeners();
      }
    } else {
      setErrorState("No actionable text received.");
    }
  }

  void confirmAudio() {
    if (geminiAudioProcessedText.isNotEmpty) {
      confirmedAudioDescription = geminiAudioProcessedText;
      geminiAudioProcessedText = '';
      currentInputState = MediaInputState.displayingConfirmedAudio;
      notifyListeners();
    }
  }

  // --- Image Handling ---
  Future<void> captureImage() async {
    _clearImageData(updateState: false);
    final file = await _deviceMediaHandler.captureImageFromCamera(
        maxWidth: 1024, imageQuality: 70);
    _handleNewImage(file);
  }

  Future<void> pickImage() async {
    _clearImageData(updateState: false);
    final file = await _deviceMediaHandler.pickImageFromGallery(
        maxWidth: 1024, imageQuality: 70);
    _handleNewImage(file);
  }

  void _handleNewImage(File? file) {
    if (file != null) {
      capturedImageFile = file;
      currentInputState = MediaInputState.imagePreview;
    } else {
      currentInputState = MediaInputState.displayingConfirmedAudio;
    }
    notifyListeners();
  }

  Future<void> sendImageToGemini() async {
    if (capturedImageFile == null) return;
    currentInputState = MediaInputState.sendingImageToGemini;
    notifyListeners();

    try {
      final Uint8List imageBytes = await capturedImageFile!.readAsBytes();
      final String mimeType =
          capturedImageFile!.path.endsWith('.png') ? 'image/png' : 'image/jpeg';
      final String incidentTypeName = currentMarkerType.name.split('.').last;

      final text = await _mediaServices.analyzeImageWithGemini(
        imageBytes: imageBytes,
        imageMimeType: mimeType,
        incidentTypeName: incidentTypeName,
      );

      geminiImageAnalysisResultText = text ?? "";

      if (text != null && text.startsWith("MATCH:")) {
        isImageApprovedByGemini = true;
      } else {
        isImageApprovedByGemini = false;
      }
      currentInputState = MediaInputState.imageAnalyzed;
      notifyListeners();
    } catch (e) {
      geminiImageAnalysisResultText = e.toString();
      currentInputState = MediaInputState.error;
      notifyListeners();
    }
  }

  void removeImage() {
    _clearImageData(updateState: true);
  }

  // --- Submission ---

  /// Returns map with correct 'finalMarkerType'
  Future<Map<String, dynamic>?> finalSubmit() async {
    if (_currentUser?.uid == null) return null;

    if (needsContactInfo() && contactInfoController.text.trim().length < 6) {
      return null;
    }
    if (isImageMandatory() && capturedImageFile == null) {
      return null;
    }

    if (capturedImageFile != null &&
        isImageApprovedByGemini &&
        uploadedImageUrl == null) {
      currentInputState = MediaInputState.uploadingMedia;
      notifyListeners();

      uploadedImageUrl = await _mediaServices.uploadIncidentImage(
          storageService: _storageService,
          imageFile: capturedImageFile!,
          userId: _currentUser!.uid,
          incidentType: currentMarkerType.name); // USA EL TIPO ACTUAL

      if (uploadedImageUrl == null) {
        currentInputState = MediaInputState.imageAnalyzed;
        notifyListeners();
        return null;
      }
    }

    if (confirmedAudioDescription.isNotEmpty) {
      return {
        'description': confirmedAudioDescription,
        'imageUrl': uploadedImageUrl,
        'contactInfo':
            needsContactInfo() ? contactInfoController.text.trim() : null,
        // AQUÍ ESTÁ LA CLAVE: DEVOLVEMOS EL TIPO QUE PUEDE HABER CAMBIADO
        'finalMarkerType': currentMarkerType,
      };
    }
    return null;
  }

  // --- Utils ---
  void retryFullProcess() {
    _deviceMediaHandler.deleteTemporaryFile(recordedAudioPath);
    recordedAudioPath = null;
    _clearAllMediaData(updateState: false);
    currentInputState = MediaInputState.idle;
    notifyListeners();
  }

  void switchToTextInput() {
    currentInputState = MediaInputState.textInput;
    notifyListeners();
  }

  void cancelInput() {
    currentInputState = MediaInputState.idle;
    notifyListeners();
  }

  void _clearImageData({bool updateState = true}) {
    capturedImageFile = null;
    geminiImageAnalysisResultText = '';
    isImageApprovedByGemini = false;
    uploadedImageUrl = null;
    if (updateState) {
      currentInputState = MediaInputState.displayingConfirmedAudio;
      notifyListeners();
    }
  }

  void _clearAllMediaData({bool updateState = true}) {
    if (recordedAudioPath != null) {
      _deviceMediaHandler.deleteTemporaryFile(recordedAudioPath);
      recordedAudioPath = null;
    }
    capturedImageFile = null;
    uploadedImageUrl = null;
    geminiAudioProcessedText = '';
    confirmedAudioDescription = '';
    geminiImageAnalysisResultText = '';
    isImageApprovedByGemini = false;
    pendingSuggestedType = null;

    if (updateState) {
      currentInputState = MediaInputState.idle;
      notifyListeners();
    }
  }

  MakerType? _mapStringToMakerType(String suggestion) {
    final cleaned = suggestion.trim().toLowerCase();
    if (cleaned.contains('pet') || cleaned.contains('mascota'))
      return MakerType.pet;
    if (cleaned.contains('event') || cleaned.contains('evento'))
      return MakerType.event;
    if (cleaned.contains('place') || cleaned.contains('lugar'))
      return MakerType.place;
    if (cleaned.contains('crash') || cleaned.contains('accidente'))
      return MakerType.crash;
    if (cleaned.contains('fire') || cleaned.contains('incendio'))
      return MakerType.fire;
    if (cleaned.contains('theft') || cleaned.contains('robo'))
      return MakerType.theft;
    return null;
  }

  @override
  void dispose() {
    _deviceMediaHandler.disposeAudioRecorder();
    if (recordedAudioPath != null) {
      _deviceMediaHandler.deleteTemporaryFile(recordedAudioPath);
    }
    textEditingController.dispose();
    contactInfoController.dispose();
    super.dispose();
  }
}
