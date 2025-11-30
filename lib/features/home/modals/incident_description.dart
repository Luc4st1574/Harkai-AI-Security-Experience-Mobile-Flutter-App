// lib/features/home/modals/incident_description.dart

import 'package:flutter/material.dart';
import 'package:harkai/l10n/app_localizations.dart';

import 'modules/ui_builders.dart';
import 'modules/incident_modal_controller.dart';
import 'modules/incident_state.dart';
import 'modules/incident_status_helper.dart';
import '../utils/markers.dart';

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
  late IncidentModalController _controller;
  late AnimationController _micAnimationController;
  late Animation<double> _micScaleAnimation;
  AppLocalizations? _localizations;

  @override
  void initState() {
    super.initState();
    _controller = IncidentModalController(currentMarkerType: widget.markerType);

    _micAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _micScaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _micAnimationController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.initialize();
      _controller.addListener(_onStateChange);
    });
  }

  void _onStateChange() {
    if (!mounted) return;
    if (_controller.currentInputState == MediaInputState.recordingAudio) {
      _micAnimationController.forward();
    } else {
      _micAnimationController.reverse();
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _localizations ??= AppLocalizations.of(context);
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChange);
    _controller.dispose();
    _micAnimationController.dispose();
    super.dispose();
  }

  void _handleFinalSubmit() async {
    if (_controller.needsContactInfo() &&
        _controller.contactInfoController.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text("Por favor ingrese un número válido.")),
      );
      return;
    }

    final result = await _controller.finalSubmit();

    if (result != null && mounted) {
      Navigator.pop(context, result);
    } else if (_controller.isImageMandatory() &&
        _controller.capturedImageFile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              backgroundColor: Colors.orange,
              content: Text("Es obligatoria una imagen.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_localizations == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final state = _controller.currentInputState;
    final markerType = _controller.currentMarkerType;
    final markerDetails = getMarkerInfo(markerType, _localizations!);
    final accentColor = markerDetails?.color ?? Colors.blueGrey;

    final statusText = IncidentStatusHelper.getStatusText(
        state: state,
        markerType: markerType,
        localizations: _localizations!,
        isImageMandatory: _controller.isImageMandatory());

    final instructionText = IncidentStatusHelper.getInstructionText(
        state: state,
        markerType: markerType,
        localizations: _localizations!,
        hasMicPermission: _controller.hasMicPermission,
        geminiAudioText: _controller.geminiAudioProcessedText,
        geminiImageText: _controller.geminiImageAnalysisResultText,
        isImageApproved: _controller.isImageApprovedByGemini,
        isImageMandatory: _controller.isImageMandatory());

    bool isProcessingAny = state == MediaInputState.sendingAudioToGemini ||
        state == MediaInputState.sendingImageToGemini ||
        state == MediaInputState.uploadingMedia;
    bool isContactInputActive = state == MediaInputState.contactInfoInput;

    return PopScope(
      canPop: !isProcessingAny && state != MediaInputState.recordingAudio,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!isProcessingAny && state != MediaInputState.recordingAudio) {
          _controller.cancelInput();
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
              // Título (se actualiza solo si la IA cambia el tipo)
              Text(
                statusText,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: (state == MediaInputState.error)
                        ? Colors.redAccent
                        : accentColor),
                textAlign: TextAlign.center,
              ),

              // [ELIMINADO] El Dropdown manual ya no está aquí.

              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(instructionText,
                    style: TextStyle(
                        fontSize: 14, color: Colors.white.withOpacity(0.8)),
                    textAlign: TextAlign.center),
              ),
              const SizedBox(height: 15),

              if (isContactInputActive) _buildContactSection(accentColor),

              IncidentModalUiBuilders.buildConfirmedAudioArea(
                shouldShow: state == MediaInputState.displayingConfirmedAudio ||
                    state == MediaInputState.imagePreview ||
                    state == MediaInputState.imageAnalyzed,
                confirmedAudioDescription:
                    _controller.confirmedAudioDescription,
                accentColor: accentColor,
                localizations: _localizations!,
              ),

              IncidentModalUiBuilders.buildImagePreviewArea(
                shouldShow: _controller.capturedImageFile != null,
                capturedImageFile: _controller.capturedImageFile,
                currentInputState: state,
                isImageApprovedByGemini: _controller.isImageApprovedByGemini,
                geminiImageAnalysisResultText:
                    _controller.geminiImageAnalysisResultText,
                accentColor: accentColor,
                onRemoveImage: _controller.removeImage,
                localizations: _localizations!,
              ),
              const SizedBox(height: 10),

              // --- BOTONES PRINCIPALES ---
              if (isProcessingAny)
                IncidentModalUiBuilders.buildProcessingIndicator(
                    accentColor: accentColor,
                    userInstructionText: instructionText)
              else if (state == MediaInputState.error)
                // Aquí mantenemos la lógica de SUGERENCIA DE CAMBIO
                Column(
                  children: [
                    if (_controller.pendingSuggestedType != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: ElevatedButton.icon(
                          onPressed: () => _controller.applySuggestedChange(),
                          icon: const Icon(Icons.auto_fix_high,
                              color: Colors.white),
                          label: Text(
                            "Cambiar a ${_controller.pendingSuggestedType!.name.toUpperCase()}",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                        ),
                      ),
                    IncidentModalUiBuilders.buildErrorControls(
                      localizations: _localizations!,
                      accentColor: accentColor,
                      userInstructionText: instructionText,
                      onRetryFullProcess: _controller.retryFullProcess,
                    ),
                  ],
                )
              else if (!isContactInputActive)
                _buildMainControls(state, accentColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactSection(Color accentColor) {
    return Column(
      children: [
        TextField(
          controller: _controller.contactInfoController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: "Contacto (Requerido)",
            labelStyle: TextStyle(color: accentColor),
            enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white30)),
            focusedBorder:
                OutlineInputBorder(borderSide: BorderSide(color: accentColor)),
            prefixIcon: Icon(Icons.phone, color: accentColor),
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: () {
            if (_controller.contactInfoController.text.trim().length < 6)
              return;
            _controller.submitContactInfo();
          },
          style: ElevatedButton.styleFrom(backgroundColor: accentColor),
          child: const Text("Continuar", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildMainControls(MediaInputState state, Color accentColor) {
    bool showGalleryButton = _controller.currentMarkerType == MakerType.place ||
        _controller.currentMarkerType == MakerType.pet ||
        _controller.currentMarkerType == MakerType.event;

    return Column(
      children: [
        if (state == MediaInputState.textInput)
          _buildTextInputArea(accentColor),
        if (state == MediaInputState.idle ||
            state == MediaInputState.recordingAudio ||
            state == MediaInputState.textInput) ...[
          if (state != MediaInputState.textInput)
            IncidentModalUiBuilders.buildMicInputControl(
              context: context,
              localizations: _localizations!,
              canRecordAudio:
                  _controller.hasMicPermission && state == MediaInputState.idle,
              currentInputState: state,
              micScaleAnimation: _micScaleAnimation,
              accentColor: accentColor,
              onLongPressStart: () => _controller.startRecording(),
              onLongPressEnd: () => _controller.stopRecording(),
              onTapHint: () {
                if (!_controller.hasMicPermission) _controller.initialize();
              },
            ),
          if (state == MediaInputState.idle && _controller.needsContactInfo())
            TextButton(
                onPressed: () => setState(() => _controller.currentInputState =
                    MediaInputState.contactInfoInput),
                child: const Text("Editar Contacto",
                    style: TextStyle(color: Colors.white60))),
        ],
        if (state == MediaInputState.displayingConfirmedAudio ||
            state == MediaInputState.imagePreview)
          Padding(
            padding: const EdgeInsets.only(top: 15.0),
            child: IncidentModalUiBuilders.buildCameraInputControl(
              localizations: _localizations!,
              capturedImageFile: _controller.capturedImageFile,
              accentColor: accentColor,
              onPressedCapture: _controller.captureImage,
              onPressedGallery: _controller.pickImage,
              showGalleryButton: showGalleryButton,
            ),
          ),
        const SizedBox(height: 20),
        IncidentModalUiBuilders.buildActionButtons(
          context: context,
          localizations: _localizations!,
          currentInputState: state,
          accentColor: accentColor,
          isImageApprovedByGemini: _controller.isImageApprovedByGemini,
          onSendAudioToGemini: _controller.sendAudioToGemini,
          onConfirmAudioAndProceed: _controller.confirmAudio,
          onRetryFullProcessAudio: _controller.retryFullProcess,
          onSubmitWithAudioOnlyAfterConfirmation: _handleFinalSubmit,
          onSendImageToGemini: _controller.sendImageToGemini,
          onRemoveImageAndGoBackToDecision: _controller.removeImage,
          onSubmitWithAudioAndImage: _handleFinalSubmit,
          onSubmitAudioOnlyFromImageAnalyzed: () {
            _controller.removeImage();
            _handleFinalSubmit();
          },
          onClearImageDataAndSubmitAudioOnlyFromAnalyzed: () {
            _controller.removeImage();
            _handleFinalSubmit();
          },
          allowAudioOnlySubmit: !_controller.isImageMandatory(),
        ),
        if (state == MediaInputState.idle)
          TextButton(
            onPressed: _controller.switchToTextInput,
            child: Text(_localizations!.incidentModalButtonEnterTextInstead,
                style: TextStyle(color: accentColor)),
          ),
        if (state != MediaInputState.recordingAudio)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_localizations!.incidentModalButtonCancelReport,
                style: const TextStyle(color: Colors.grey, fontSize: 15)),
          ),
      ],
    );
  }

  Widget _buildTextInputArea(Color accentColor) {
    return Column(
      children: [
        TextField(
          controller: _controller.textEditingController,
          style: const TextStyle(color: Colors.white),
          maxLines: 3,
          decoration: InputDecoration(
            hintText: _localizations!.incidentModalInstructionEnterText,
            hintStyle: const TextStyle(color: Colors.white60),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.mic, color: Colors.white70, size: 18),
              label: const Text("Usar Audio",
                  style: TextStyle(color: Colors.white70)),
              onPressed: _controller.cancelInput,
            ),
            ElevatedButton.icon(
              icon:
                  const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              label: Text(_localizations!.incidentModalButtonSendTextToHarki,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              onPressed: _controller.sendTextToGemini,
            ),
          ],
        )
      ],
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
