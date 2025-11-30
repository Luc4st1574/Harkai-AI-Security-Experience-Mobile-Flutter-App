import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:harkai/l10n/app_localizations.dart';

import 'modules/media_services.dart';
import 'modules/media_handler.dart';
import 'modules/ui_builders.dart';

import 'package:harkai/core/services/storage_service.dart';
import '../utils/markers.dart';
import 'package:harkai/features/home/utils/extensions.dart';

enum MediaInputState {
  contactInfoInput,
  idle,
  recordingAudio,
  audioRecordedReadyToSend,
  sendingAudioToGemini,
  audioDescriptionReadyForConfirmation,
  textInput,
  displayingConfirmedAudio,
  awaitingImageCapture,
  imagePreview,
  sendingImageToGemini,
  imageAnalyzed,
  uploadingMedia,
  error,
}

class IncidentVoiceDescriptionModal extends StatefulWidget {
  final MakerType markerType;

  const IncidentVoiceDescriptionModal({
    super.key,
    required this.markerType,
  });

  @override
  State<IncidentVoiceDescriptionModal> createState() =>
      _IncidentVoiceDescriptionModalState();
}

class _IncidentVoiceDescriptionModalState
    extends State<IncidentVoiceDescriptionModal> with TickerProviderStateMixin {
  // NEW: Mutable type that can change if Gemini detects a mismatch
  late MakerType _currentMarkerType;

  String? _recordedAudioPath;
  String _geminiAudioProcessedText = '';
  String _confirmedAudioDescription = '';
  File? _capturedImageFile;
  String _geminiImageAnalysisResultText = '';
  bool _isImageApprovedByGemini = false;
  String? _uploadedImageUrl;

  MediaInputState _currentInputState = MediaInputState.idle;
  final TextEditingController _textEditingController = TextEditingController();
  final TextEditingController _contactInfoController = TextEditingController();

  bool _hasMicPermission = false;
  String _statusText = '';
  String _userInstructionText = '';

  late AnimationController _micAnimationController;
  late Animation<double> _micScaleAnimation;

  late IncidentMediaServices _mediaServices;
  late DeviceMediaHandler _deviceMediaHandler;
  final StorageService _storageService = StorageService();
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  AppLocalizations? _localizations;

  @override
  void initState() {
    super.initState();
    // Initialize current marker type from widget configuration
    _currentMarkerType = widget.markerType;

    _mediaServices = IncidentMediaServices();
    _deviceMediaHandler = DeviceMediaHandler();

    _micAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _micScaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _micAnimationController, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_localizations == null) {
      _localizations = AppLocalizations.of(context)!;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _initializeModal();
      });
    }
  }

  Future<void> _initializeModal() async {
    if (_localizations == null) {
      if (mounted) {
        _localizations = AppLocalizations.of(context);
      }
      if (_localizations == null) {
        setState(() {
          _statusText = "Error initializing...";
          _userInstructionText = "Please try again.";
        });
        return;
      }
    }

    _statusText = _localizations!.incidentModalStatusInitializing;

    PermissionStatus micStatus =
        await _mediaServices.getMicrophonePermissionStatus();
    _hasMicPermission = micStatus.isGranted;

    if (!_hasMicPermission) {
      _hasMicPermission = await _mediaServices.requestMicrophonePermission(
          openSettingsOnError: true);
      if (!_hasMicPermission && mounted) {
        _handleError(_localizations!.incidentModalErrorMicPermissionRequired);
        return;
      }
    }

    try {
      _mediaServices.initializeGeminiModel();
    } catch (e) {
      if (mounted) {
        _handleError(_localizations!
            .incidentModalErrorHarkiAudioProcessingFailed(e.toString()));
        return;
      }
    }

    if (mounted) {
      if (_needsContactInfo()) {
        _currentInputState = MediaInputState.contactInfoInput;
      } else {
        _currentInputState = MediaInputState.idle;
      }
      _updateStatusAndInstructionText();
    }
  }

  // MODIFIED: Use _currentMarkerType
  bool _needsContactInfo() {
    return _currentMarkerType == MakerType.pet ||
        _currentMarkerType == MakerType.event ||
        _currentMarkerType == MakerType.place;
  }

  // NEW: Check if image is mandatory for current type
  bool _isImageMandatory() {
    return _currentMarkerType == MakerType.pet ||
        _currentMarkerType == MakerType.event ||
        _currentMarkerType == MakerType.place;
  }

  void _handleContactSubmit() {
    if (_contactInfoController.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
                "Por favor ingrese un número válido (mínimo 6 dígitos). Obligatorio para continuar.",
                style: TextStyle(color: Colors.white))), // Spanish
      );
      return;
    }
    setState(() {
      _currentInputState = MediaInputState.idle;
      _updateStatusAndInstructionText();
    });
  }

  void _handleError(String errorMessage,
      {bool isGeminiError = false,
      bool isMismatch = false,
      bool isUnclear = false}) {
    if (mounted && _localizations != null) {
      _micAnimationController.reverse();
      setState(() {
        _currentInputState = MediaInputState.error;
        if (isMismatch) {
          _statusText = _localizations!.incidentModalStatusTypeMismatch;
        } else if (isUnclear) {
          _statusText = _localizations!.incidentModalStatusInputUnclearInvalid;
        } else if (isGeminiError) {
          _statusText = _localizations!.incidentModalStatusHarkiProcessingError;
        } else {
          _statusText = _localizations!.incidentModalStatusError;
        }
        _userInstructionText = errorMessage;
      });
    }
  }

  Future<void> _handleStartRecording() async {
    if (_localizations == null) return;
    _clearAllMediaData(
        clearAudioProcessingResults: true,
        clearImageProcessingResults: true,
        updateState: false);

    if (!_hasMicPermission) {
      _handleError(_localizations!.incidentModalErrorMicNotGranted);
      await _initializeModal();
      return;
    }

    _recordedAudioPath = await _deviceMediaHandler.getTemporaryFilePath("m4a");
    const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 48000);

    final successPath = await _deviceMediaHandler.startRecording(
        filePath: _recordedAudioPath!, config: config);

    if (successPath != null) {
      _recordedAudioPath = successPath;
      if (mounted) {
        _micAnimationController.forward();
        setState(() {
          _currentInputState = MediaInputState.recordingAudio;
          _updateStatusAndInstructionText();
        });
      }
    } else {
      _recordedAudioPath = null;
      _handleError(_localizations!.incidentModalErrorCouldNotStartRecording);
    }
  }

  Future<void> _handleStopRecording() async {
    if (_localizations == null) return;
    final path = await _deviceMediaHandler.stopRecording();
    if (path != null) {
      _recordedAudioPath = path;
      if (mounted) {
        _micAnimationController.reverse();
        setState(() {
          _currentInputState = MediaInputState.audioRecordedReadyToSend;
          _updateStatusAndInstructionText();
        });
      }
    } else {
      _recordedAudioPath = null;
      if (mounted) _micAnimationController.reverse();
      _handleError(_localizations!.incidentModalErrorAudioEmptyNotSaved);
      if (mounted) {
        setState(() {
          _currentInputState = MediaInputState.idle;
          _updateStatusAndInstructionText();
        });
      }
    }
  }

  // NEW: Helper to map Gemini suggested string to enum
  MakerType? _mapStringToMakerType(String suggestion) {
    final cleaned = suggestion.trim().toLowerCase();
    if (cleaned.contains('pet') || cleaned.contains('mascota')) {
      return MakerType.pet;
    }
    if (cleaned.contains('event') || cleaned.contains('evento')) {
      return MakerType.event;
    }
    if (cleaned.contains('place') || cleaned.contains('lugar')) {
      return MakerType.place;
    }
    if (cleaned.contains('crash') || cleaned.contains('accidente')) {
      return MakerType.crash;
    }
    if (cleaned.contains('fire') || cleaned.contains('incendio')) {
      return MakerType.fire;
    }
    return null;
  }

  Future<void> _handleSendAudioToGemini() async {
    if (_localizations == null) return;
    if (_recordedAudioPath == null) {
      _handleError(_localizations!.incidentModalErrorNoAudioOrHarkiNotReady);
      return;
    }
    if (mounted) {
      setState(() {
        _currentInputState = MediaInputState.sendingAudioToGemini;
        // MODIFIED: Update status text to show current type being analyzed
        _statusText =
            "Analizando para tipo: ${_currentMarkerType.name.capitalizeAllWords()}...";
        _userInstructionText =
            _localizations!.incidentModalInstructionPleaseWait;
      });
    }

    try {
      final audioFile = File(_recordedAudioPath!);
      final Uint8List audioBytes = await audioFile.readAsBytes();
      // MODIFIED: Use _currentMarkerType
      final String incidentTypeName = _currentMarkerType.name
          .toString()
          .split('.')
          .last
          .capitalizeAllWords();

      final text = await _mediaServices.analyzeAudioWithGemini(
        audioBytes: audioBytes,
        audioMimeType: "audio/mp4",
        incidentTypeName: incidentTypeName,
      );

      _geminiAudioProcessedText = text ??
          _localizations!.incidentModalErrorHarkiAudioProcessingFailed("");

      if (mounted) {
        if (text != null && text.isNotEmpty) {
          if (text.startsWith("MATCH:")) {
            _geminiAudioProcessedText = text.substring("MATCH:".length).trim();
            setState(() {
              _currentInputState =
                  MediaInputState.audioDescriptionReadyForConfirmation;
              _updateStatusAndInstructionText();
            });
          } else if (text.startsWith("MISMATCH:")) {
            // MODIFIED: Automatic switching logic
            String suggestedTypeStr = text.substring("MISMATCH:".length).trim();
            MakerType? newType = _mapStringToMakerType(suggestedTypeStr);

            if (newType != null && newType != _currentMarkerType) {
              setState(() {
                _currentMarkerType = newType;
                _statusText =
                    "Redirigiendo a ${newType.name.toUpperCase()} y reanalizando...";
              });
              // RECURSIVE CALL: Re-run analysis with new type immediately
              await _handleSendAudioToGemini();
              return;
            }

            _handleError(_geminiAudioProcessedText, isMismatch: true);
          } else if (text.startsWith("UNCLEAR:")) {
            _handleError(_geminiAudioProcessedText, isUnclear: true);
          } else {
            _handleError(
                _localizations!
                    .incidentModalErrorHarkiAudioResponseFormatUnexpected(
                        _geminiAudioProcessedText),
                isGeminiError: true);
          }
        } else {
          _handleError(
              _localizations!.incidentModalErrorHarkiNoActionableTextAudio,
              isGeminiError: true);
        }
      }
    } catch (e) {
      _handleError(
          _localizations!
              .incidentModalErrorHarkiAudioProcessingFailed(e.toString()),
          isGeminiError: true);
    }
  }

  void _handleConfirmAudioAndProceed() {
    if (_localizations == null) return;
    if (_geminiAudioProcessedText.isNotEmpty) {
      _confirmedAudioDescription = _geminiAudioProcessedText;
      _geminiAudioProcessedText = '';
      if (mounted) {
        setState(() {
          _currentInputState = MediaInputState.displayingConfirmedAudio;
          _updateStatusAndInstructionText();
        });
      }
    } else {
      _handleError(_localizations!.incidentModalErrorNoAudioToConfirm);
    }
  }

  Future<void> _handleCaptureImage() async {
    if (_localizations == null) return;
    _clearImageData(updateState: false);

    final File? capturedFile = await _deviceMediaHandler.captureImageFromCamera(
        maxWidth: 1024, imageQuality: 70);

    if (mounted) {
      if (capturedFile != null) {
        setState(() {
          _capturedImageFile = capturedFile;
          _currentInputState = MediaInputState.imagePreview;
          _geminiImageAnalysisResultText = '';
          _isImageApprovedByGemini = false;
          _uploadedImageUrl = null;
          _updateStatusAndInstructionText();
        });
      } else {
        setState(() {
          _currentInputState = MediaInputState.displayingConfirmedAudio;
          _updateStatusAndInstructionText();
        });
      }
    }
  }

  Future<void> _handlePickImageFromGallery() async {
    if (_localizations == null) return;
    _clearImageData(updateState: false);

    final File? pickedFile = await _deviceMediaHandler.pickImageFromGallery(
        maxWidth: 1024, imageQuality: 70);

    if (mounted) {
      if (pickedFile != null) {
        setState(() {
          _capturedImageFile = pickedFile;
          _currentInputState = MediaInputState.imagePreview;
          _geminiImageAnalysisResultText = '';
          _isImageApprovedByGemini = false;
          _uploadedImageUrl = null;
          _updateStatusAndInstructionText();
        });
      } else {
        setState(() {
          _currentInputState = MediaInputState.displayingConfirmedAudio;
          _updateStatusAndInstructionText();
        });
      }
    }
  }

  Future<void> _handleSendImageToGemini() async {
    if (_localizations == null) return;
    if (_capturedImageFile == null) {
      _handleError(_localizations!.incidentModalErrorNoImageOrHarkiNotReady);
      return;
    }
    if (mounted) {
      setState(() {
        _currentInputState = MediaInputState.sendingImageToGemini;
        _updateStatusAndInstructionText();
      });
    }

    try {
      final Uint8List imageBytes = await _capturedImageFile!.readAsBytes();
      final String mimeType = _capturedImageFile!.path.endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      // MODIFIED: Use _currentMarkerType
      final String incidentTypeName = _currentMarkerType.name
          .toString()
          .split('.')
          .last
          .capitalizeAllWords();

      final text = await _mediaServices.analyzeImageWithGemini(
        imageBytes: imageBytes,
        imageMimeType: mimeType,
        incidentTypeName: incidentTypeName,
      );

      _geminiImageAnalysisResultText = text ??
          _localizations!.incidentModalErrorHarkiImageProcessingFailed("");

      if (mounted) {
        if (text != null && text.isNotEmpty) {
          if (text.startsWith("MATCH:")) {
            _isImageApprovedByGemini = true;
          } else {
            _isImageApprovedByGemini = false;
          }
        } else {
          _isImageApprovedByGemini = false;
          _geminiImageAnalysisResultText =
              _localizations!.incidentModalErrorHarkiNoActionableTextImage;
        }
        setState(() {
          _currentInputState = MediaInputState.imageAnalyzed;
          _updateStatusAndInstructionText();
        });
      }
    } catch (e) {
      _isImageApprovedByGemini = false;
      _handleError(
          _localizations!
              .incidentModalErrorHarkiImageProcessingFailed(e.toString()),
          isGeminiError: true);
    }
  }

  Future<void> _handleSendTextToGemini() async {
    if (_localizations == null) return;
    final text = _textEditingController.text;
    if (text.isEmpty) {
      _handleError(_localizations!.incidentModalErrorNoAudioOrHarkiNotReady);
      return;
    }

    if (mounted) {
      setState(() {
        _currentInputState = MediaInputState.sendingAudioToGemini;
        // MODIFIED: Update status text to show current type being analyzed
        _statusText =
            "Analizando texto para tipo: ${_currentMarkerType.name.capitalizeAllWords()}...";
        _userInstructionText =
            _localizations!.incidentModalInstructionPleaseWait;
      });
    }

    try {
      // MODIFIED: Use _currentMarkerType
      final incidentTypeName = _currentMarkerType.name
          .toString()
          .split('.')
          .last
          .capitalizeAllWords();

      final response = await _mediaServices.analyzeTextWithGemini(
        text: text,
        incidentTypeName: incidentTypeName,
      );

      _geminiAudioProcessedText = response ??
          _localizations!.incidentModalErrorHarkiAudioProcessingFailed("");

      if (mounted) {
        if (response != null && response.isNotEmpty) {
          if (response.startsWith("MATCH:")) {
            _geminiAudioProcessedText =
                response.substring("MATCH:".length).trim();
            setState(() {
              _currentInputState =
                  MediaInputState.audioDescriptionReadyForConfirmation;
              _updateStatusAndInstructionText();
            });
          } else if (response.startsWith("MISMATCH:")) {
            // MODIFIED: Automatic switching logic for text
            String suggestedTypeStr =
                response.substring("MISMATCH:".length).trim();
            MakerType? newType = _mapStringToMakerType(suggestedTypeStr);

            if (newType != null && newType != _currentMarkerType) {
              setState(() {
                _currentMarkerType = newType;
                _statusText =
                    "Redirigiendo a ${newType.name.toUpperCase()} y reanalizando texto...";
              });
              // RECURSIVE CALL: Re-run text analysis with new type immediately
              await _handleSendTextToGemini();
              return;
            }

            _handleError(_geminiAudioProcessedText, isMismatch: true);
          } else if (response.startsWith("UNCLEAR:")) {
            _handleError(_geminiAudioProcessedText, isUnclear: true);
          } else {
            _handleError(
                _localizations!
                    .incidentModalErrorHarkiAudioResponseFormatUnexpected(
                        _geminiAudioProcessedText),
                isGeminiError: true);
          }
        } else {
          _handleError(
              _localizations!.incidentModalErrorHarkiNoActionableTextAudio,
              isGeminiError: true);
        }
      }
    } catch (e) {
      _handleError(
          _localizations!
              .incidentModalErrorHarkiAudioProcessingFailed(e.toString()),
          isGeminiError: true);
    }
  }

  void _handleRemoveImageAndGoBackToDecision() {
    _clearImageData(updateState: false);
    if (mounted) {
      setState(() {
        _currentInputState = MediaInputState.displayingConfirmedAudio;
        _updateStatusAndInstructionText();
      });
    }
  }

  void _clearImageData({bool updateState = true}) {
    if (mounted) {
      _capturedImageFile = null;
      _geminiImageAnalysisResultText = '';
      _isImageApprovedByGemini = false;
      _uploadedImageUrl = null;
      if (updateState) {
        setState(() {
          if (_currentInputState.name.startsWith("image") ||
              _currentInputState == MediaInputState.displayingConfirmedAudio) {
            _currentInputState = MediaInputState.displayingConfirmedAudio;
          } else {
            _currentInputState = MediaInputState.idle;
          }
          _updateStatusAndInstructionText();
        });
      }
    }
  }

  void _clearAllMediaData(
      {bool clearAudioProcessingResults = true,
      bool clearImageProcessingResults = true,
      bool updateState = true}) {
    if (mounted) {
      if (_recordedAudioPath != null) {
        _deviceMediaHandler.deleteTemporaryFile(_recordedAudioPath);
        _recordedAudioPath = null;
      }
      _capturedImageFile = null;
      _uploadedImageUrl = null;

      if (clearAudioProcessingResults) {
        _geminiAudioProcessedText = '';
        _confirmedAudioDescription = '';
      }
      if (clearImageProcessingResults) {
        _geminiImageAnalysisResultText = '';
        _isImageApprovedByGemini = false;
      }
      if (updateState) {
        setState(() {
          _currentInputState = MediaInputState.idle;
          _updateStatusAndInstructionText();
        });
      }
    }
  }

  Future<void> _handleFinalSubmitIncident() async {
    if (_localizations == null) return;
    if (_currentUser?.uid == null) {
      _handleError(_localizations!.incidentModalErrorUserNotLoggedIn);
      if (mounted) {
        setState(() {
          _currentInputState =
              _capturedImageFile != null && _isImageApprovedByGemini
                  ? MediaInputState.imageAnalyzed
                  : MediaInputState.displayingConfirmedAudio;
          _updateStatusAndInstructionText();
        });
      }
      return;
    }

    if (_needsContactInfo() && _contactInfoController.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
                "Por favor ingrese un número válido (mínimo 6 dígitos).")), // Spanish
      );
      return;
    }

    // MODIFIED: Enforce mandatory image for specific types
    if (_isImageMandatory() && _capturedImageFile == null) {
      _handleError(
          "Es obligatorio adjuntar una imagen para este tipo de reporte."); // Hardcoded Spanish
      if (mounted) {
        setState(() {
          _currentInputState = MediaInputState.displayingConfirmedAudio;
          _updateStatusAndInstructionText();
        });
      }
      return;
    }

    if (_capturedImageFile != null &&
        _isImageApprovedByGemini &&
        _uploadedImageUrl == null) {
      if (mounted) {
        setState(() {
          _currentInputState = MediaInputState.uploadingMedia;
          _updateStatusAndInstructionText();
        });
      }
      _uploadedImageUrl = await _mediaServices.uploadIncidentImage(
          storageService: _storageService,
          imageFile: _capturedImageFile!,
          userId: _currentUser!.uid,
          // MODIFIED: Use _currentMarkerType
          incidentType: _currentMarkerType.name);

      if (_uploadedImageUrl == null && mounted) {
        _handleError(_localizations!.incidentModalErrorFailedToUploadImage);
        setState(() {
          _currentInputState = MediaInputState.imageAnalyzed;
          _updateStatusAndInstructionText();
        });
        return;
      }
    }

    if (_confirmedAudioDescription.isNotEmpty) {
      if (mounted) {
        Navigator.pop(context, {
          'description': _confirmedAudioDescription,
          'imageUrl': _uploadedImageUrl,
          'contactInfo':
              _needsContactInfo() ? _contactInfoController.text.trim() : null,
          // NEW: Return the final, potentially changed, marker type
          'finalMarkerType': _currentMarkerType,
        });
      }
    } else {
      _handleError(
          _localizations!.incidentModalErrorNoConfirmedAudioDescription);
      if (mounted) {
        setState(() {
          _currentInputState = MediaInputState.idle;
          _updateStatusAndInstructionText();
        });
      }
    }
  }

  Future<void> _deleteRecordedAudioFile() async {
    if (_recordedAudioPath != null) {
      await _deviceMediaHandler.deleteTemporaryFile(_recordedAudioPath);
      _recordedAudioPath = null;
    }
  }

  Future<void> _handleRetryFullProcess() async {
    await _deleteRecordedAudioFile();
    _clearAllMediaData(updateState: false);

    if (!_hasMicPermission) {
      await _initializeModal();
    } else if (mounted) {
      setState(() {
        // Reset type back to original if retrying completely
        _currentMarkerType = widget.markerType;
        _currentInputState = MediaInputState.idle;
        _updateStatusAndInstructionText();
      });
    }
  }

  Future<void> _handleCancelInput() async {
    if (await _deviceMediaHandler.isAudioRecording()) {
      await _deviceMediaHandler.stopRecording();
    }
    await _deleteRecordedAudioFile();
    _clearAllMediaData(updateState: false);
    if (mounted) {
      Navigator.pop(context, null);
    }
  }

  void _onTapMicHintOrPermissionRecheck() {
    if (!_hasMicPermission) {
      _initializeModal();
    }
  }

  void _updateStatusAndInstructionText() {
    if (_localizations == null) {
      _statusText = "Loading...";
      _userInstructionText = "Please wait.";
      if (mounted) setState(() {});
      return;
    }

    // MODIFIED: Use _currentMarkerType
    final markerDetails = getMarkerInfo(_currentMarkerType, _localizations!);
    final incidentName =
        markerDetails?.title ?? _currentMarkerType.name.capitalizeAllWords();

    switch (_currentInputState) {
      case MediaInputState.contactInfoInput:
        _statusText = "Información de Contacto"; // Spanish
        _userInstructionText =
            "Por favor, ingrese un número de teléfono para contactarlo si es necesario."; // Spanish
        break;
      case MediaInputState.idle:
        _statusText =
            _localizations!.incidentModalStep1ReportAudioTitle(incidentName);
        _userInstructionText = _localizations!.incidentModalInstructionHoldMic;
        if (!_hasMicPermission) {
          _userInstructionText =
              _localizations!.incidentModalInstructionMicPermissionNeeded;
        }
        break;
      case MediaInputState.textInput:
        _statusText =
            _localizations!.incidentModalReportTextTitle(incidentName);
        _userInstructionText =
            _localizations!.incidentModalInstructionEnterText;
        break;
      case MediaInputState.recordingAudio:
        _statusText = _localizations!.incidentModalStatusRecordingAudio;
        _userInstructionText =
            _localizations!.incidentModalInstructionReleaseMic;
        break;
      case MediaInputState.audioRecordedReadyToSend:
        _statusText = _localizations!.incidentModalStatusAudioRecorded;
        _userInstructionText =
            _localizations!.incidentModalInstructionSendAudioToHarki;
        break;
      case MediaInputState.sendingAudioToGemini:
        _statusText = _localizations!.incidentModalStatusSendingAudioToHarki;
        _userInstructionText =
            _localizations!.incidentModalInstructionPleaseWait;
        break;
      case MediaInputState.audioDescriptionReadyForConfirmation:
        _statusText =
            _localizations!.incidentModalStatusConfirmAudioDescription;
        _userInstructionText = _localizations!
            .incidentModalInstructionConfirmAudio(_geminiAudioProcessedText);
        break;
      case MediaInputState.displayingConfirmedAudio:
        // MODIFIED: Hardcoded Spanish text for mandatory vs optional images
        _statusText = _isImageMandatory()
            ? "Paso 2: Foto Obligatoria"
            : "Paso 2: Añadir Imagen (Opcional)";
        _userInstructionText = _isImageMandatory()
            ? "Para este tipo de incidente (${incidentName}), ES OBLIGATORIO adjuntar una evidencia visual antes de enviar."
            : "Puede adjuntar una imagen como evidencia adicional, o enviar el reporte solo con el audio confirmado.";
        break;
      case MediaInputState.awaitingImageCapture:
        _statusText = _localizations!.incidentModalStatusCapturingImage;
        _userInstructionText =
            _localizations!.incidentModalInstructionUseCamera;
        break;
      case MediaInputState.imagePreview:
        _statusText = _localizations!.incidentModalStatusImagePreview;
        _userInstructionText =
            _localizations!.incidentModalInstructionAnalyzeRetakeRemoveImage;
        break;
      case MediaInputState.sendingImageToGemini:
        _statusText = _localizations!.incidentModalStatusSendingImageToHarki;
        _userInstructionText =
            _localizations!.incidentModalInstructionPleaseWait;
        break;
      case MediaInputState.imageAnalyzed:
        _statusText = _localizations!.incidentModalStatusImageAnalyzed;
        String imageAnalysisFeedback = _geminiImageAnalysisResultText.isNotEmpty
            ? _geminiImageAnalysisResultText
            : _localizations!.incidentModalImageHarkiAnalysisComplete;
        if (_isImageApprovedByGemini) {
          _userInstructionText =
              "${_localizations!.incidentModalImageHarkiLooksGood}\n${_localizations!.incidentModalInstructionImageApproved.split('\n').sublist(1).join('\n')}";
        } else {
          _userInstructionText =
              "${_localizations!.incidentModalImageHarkiFeedback(imageAnalysisFeedback)}\n${_localizations!.incidentModalInstructionImageFeedback("").split('\n').sublist(1).join('\n')}";
        }
        break;
      case MediaInputState.uploadingMedia:
        _statusText = _localizations!.incidentModalStatusSubmittingIncident;
        _userInstructionText =
            _localizations!.incidentModalInstructionUploadingMedia;
        break;
      case MediaInputState.error:
        break;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _micAnimationController.dispose();
    _deviceMediaHandler.disposeAudioRecorder();
    _deleteRecordedAudioFile();
    _textEditingController.dispose();
    _contactInfoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_localizations == null) {
      _localizations = AppLocalizations.of(context);
      if (_localizations == null) {
        return const Dialog(
            child: Center(
                child: CircularProgressIndicator(
          semanticsLabel: "Loading localization",
        )));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateStatusAndInstructionText();
      });
    }

    // MODIFIED: Use _currentMarkerType
    final MarkerInfo? markerDetails =
        getMarkerInfo(_currentMarkerType, _localizations!);
    final Color accentColor = markerDetails?.color ?? Colors.blueGrey;

    bool isProcessingAny =
        _currentInputState == MediaInputState.sendingAudioToGemini ||
            _currentInputState == MediaInputState.sendingImageToGemini ||
            _currentInputState == MediaInputState.uploadingMedia;

    bool isStep1Active = _currentInputState == MediaInputState.idle ||
        _currentInputState == MediaInputState.recordingAudio ||
        _currentInputState == MediaInputState.audioRecordedReadyToSend ||
        _currentInputState == MediaInputState.sendingAudioToGemini ||
        _currentInputState ==
            MediaInputState.audioDescriptionReadyForConfirmation;

    bool isTextInputActive = _currentInputState == MediaInputState.textInput;
    bool isContactInputActive =
        _currentInputState == MediaInputState.contactInfoInput;

    bool showStep2ImageRelatedUI =
        _currentInputState == MediaInputState.displayingConfirmedAudio ||
            _currentInputState == MediaInputState.imagePreview ||
            _currentInputState == MediaInputState.sendingImageToGemini ||
            _currentInputState == MediaInputState.imageAnalyzed;

    // MODIFIED: Use _currentMarkerType for gallery check
    final bool showGalleryButton = _currentMarkerType == MakerType.place ||
        _currentMarkerType == MakerType.pet ||
        _currentMarkerType == MakerType.event;

    return PopScope(
      canPop: !isProcessingAny &&
          _currentInputState != MediaInputState.recordingAudio,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        if (!(isProcessingAny ||
            _currentInputState == MediaInputState.recordingAudio)) {
          _handleCancelInput();
        }
      },
      child: Dialog(
        backgroundColor: const Color(0xFF001F3F),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
            side: BorderSide(color: accentColor, width: 2)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _statusText,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: (_currentInputState == MediaInputState.error &&
                            !(_statusText ==
                                    _localizations!
                                        .incidentModalStatusTypeMismatch ||
                                _statusText ==
                                    _localizations!
                                        .incidentModalStatusInputUnclearInvalid))
                        ? Colors.redAccent
                        : accentColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(_userInstructionText,
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withAlpha((0.8 * 255).toInt())),
                    textAlign: TextAlign.center),
              ),
              const SizedBox(height: 15),

              // --- CONTACT INFO SCREEN (First Step if needed) ---
              if (isContactInputActive)
                Column(
                  children: [
                    const SizedBox(height: 10),
                    TextField(
                      controller: _contactInfoController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Información de contacto (REQUERIDO)",
                        labelStyle: TextStyle(color: accentColor),
                        enabledBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.white.withOpacity(0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: accentColor),
                        ),
                        prefixIcon: Icon(Icons.phone, color: accentColor),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _handleContactSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 12),
                      ),
                      child: const Text(
                        "Continuar", // Spanish
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),

              // --- CONFIRMED AUDIO UI ---
              IncidentModalUiBuilders.buildConfirmedAudioArea(
                shouldShow: showStep2ImageRelatedUI ||
                    _currentInputState == MediaInputState.imagePreview,
                confirmedAudioDescription: _confirmedAudioDescription,
                accentColor: accentColor,
                localizations: _localizations!,
              ),

              // --- IMAGE PREVIEW UI ---
              IncidentModalUiBuilders.buildImagePreviewArea(
                shouldShow: _capturedImageFile != null &&
                    (showStep2ImageRelatedUI ||
                        _currentInputState == MediaInputState.imagePreview),
                capturedImageFile: _capturedImageFile,
                currentInputState: _currentInputState,
                isImageApprovedByGemini: _isImageApprovedByGemini,
                geminiImageAnalysisResultText: _geminiImageAnalysisResultText,
                accentColor: accentColor,
                onRemoveImage: _handleRemoveImageAndGoBackToDecision,
                localizations: _localizations!,
              ),
              const SizedBox(height: 10),

              // --- STANDARD MEDIA INPUT CONTROLS ---
              if (isProcessingAny)
                IncidentModalUiBuilders.buildProcessingIndicator(
                    accentColor: accentColor,
                    userInstructionText: _userInstructionText)
              else if (_currentInputState == MediaInputState.error)
                IncidentModalUiBuilders.buildErrorControls(
                  accentColor: accentColor,
                  userInstructionText: _userInstructionText,
                  onRetryFullProcess: _handleRetryFullProcess,
                  localizations: _localizations!,
                )
              else if (!isContactInputActive) // Hide standard controls if on contact screen
                Column(
                  children: [
                    if (isTextInputActive)
                      Column(
                        children: [
                          TextField(
                            controller: _textEditingController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: _localizations!
                                  .incidentModalInstructionEnterText,
                              hintStyle:
                                  TextStyle(color: Colors.white.withAlpha(150)),
                              border: const OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.mic,
                                    color: Colors.white70, size: 18),
                                label: const Text("Usar Audio",
                                    style: TextStyle(color: Colors.white70)),
                                onPressed: () {
                                  setState(() {
                                    _currentInputState = MediaInputState.idle;
                                    _updateStatusAndInstructionText();
                                  });
                                },
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.send_rounded,
                                    color: Colors.white, size: 18),
                                label: Text(
                                    _localizations!
                                        .incidentModalButtonSendTextToHarki,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: accentColor,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12)),
                                onPressed: _handleSendTextToGemini,
                              ),
                            ],
                          )
                        ],
                      ),
                    if (isStep1Active) ...[
                      IncidentModalUiBuilders.buildMicInputControl(
                        context: context,
                        canRecordAudio: _hasMicPermission &&
                            _currentInputState == MediaInputState.idle,
                        currentInputState: _currentInputState,
                        micScaleAnimation: _micScaleAnimation,
                        accentColor: accentColor,
                        onLongPressStart: _handleStartRecording,
                        onLongPressEnd: _handleStopRecording,
                        onTapHint: _onTapMicHintOrPermissionRecheck,
                        localizations: _localizations!,
                      ),
                      if (_currentInputState == MediaInputState.idle &&
                          _needsContactInfo())
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _currentInputState =
                                  MediaInputState.contactInfoInput;
                              _updateStatusAndInstructionText();
                            });
                          },
                          child: Text("Editar Contacto",
                              style: TextStyle(
                                  color: Colors.white.withAlpha(150))),
                        ),
                    ],
                    if (showStep2ImageRelatedUI &&
                        _currentInputState !=
                            MediaInputState.sendingImageToGemini &&
                        _currentInputState != MediaInputState.uploadingMedia)
                      Padding(
                        padding: const EdgeInsets.only(top: 15.0),
                        child: IncidentModalUiBuilders.buildCameraInputControl(
                          capturedImageFile: _capturedImageFile,
                          accentColor: accentColor,
                          onPressedCapture: _handleCaptureImage,
                          localizations: _localizations!,
                          onPressedGallery: _handlePickImageFromGallery,
                          showGalleryButton: showGalleryButton,
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (_currentInputState ==
                        MediaInputState.displayingConfirmedAudio)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: TextButton(
                          onPressed: _handleRetryFullProcess,
                          child: const Text("Volver / Editar Descripción",
                              style: TextStyle(color: Colors.white70)),
                        ),
                      ),
                    IncidentModalUiBuilders.buildActionButtons(
                      context: context,
                      currentInputState: _currentInputState,
                      accentColor: accentColor,
                      isImageApprovedByGemini: _isImageApprovedByGemini,
                      onSendAudioToGemini: _handleSendAudioToGemini,
                      onConfirmAudioAndProceed: _handleConfirmAudioAndProceed,
                      onRetryFullProcessAudio: _handleRetryFullProcess,
                      onSubmitWithAudioOnlyAfterConfirmation:
                          _handleFinalSubmitIncident,
                      onSendImageToGemini: _handleSendImageToGemini,
                      onRemoveImageAndGoBackToDecision:
                          _handleRemoveImageAndGoBackToDecision,
                      onSubmitWithAudioAndImage: _handleFinalSubmitIncident,
                      onSubmitAudioOnlyFromImageAnalyzed: () {
                        _clearImageData(updateState: false);
                        _handleFinalSubmitIncident();
                      },
                      onClearImageDataAndSubmitAudioOnlyFromAnalyzed: () {
                        _clearImageData(updateState: false);
                        _handleFinalSubmitIncident();
                      },
                      localizations: _localizations!,
                      // MODIFIED: Pass flag to hide/disable "submit without image" button based on type
                      // NOTE: You need to update IncidentModalUiBuilders.buildActionButtons to accept this parameter.
                      allowAudioOnlySubmit: !_isImageMandatory(),
                    ),
                  ],
                ),
              if (_currentInputState == MediaInputState.idle) ...[
                const SizedBox(height: 0),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _currentInputState = MediaInputState.textInput;
                      _updateStatusAndInstructionText();
                    });
                  },
                  child: Text(
                      _localizations!.incidentModalButtonEnterTextInstead,
                      style: TextStyle(color: accentColor)),
                ),
              ],
              const SizedBox(height: 0),
              if (!isProcessingAny &&
                  _currentInputState != MediaInputState.recordingAudio)
                TextButton(
                  onPressed: _handleCancelInput,
                  child: Text(_localizations!.incidentModalButtonCancelReport,
                      style: const TextStyle(color: Colors.grey, fontSize: 15)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<Map<String, dynamic>?> showIncidentVoiceDescriptionDialog({
  required BuildContext context,
  required MakerType markerType,
}) async {
  return await showDialog<Map<String, dynamic>?>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return IncidentVoiceDescriptionModal(markerType: markerType);
    },
  );
}
