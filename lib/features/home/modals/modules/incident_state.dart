// lib/features/home/modals/modules/incident_state.dart

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
