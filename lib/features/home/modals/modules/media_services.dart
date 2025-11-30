// lib/features/home/modals/modules/media_services.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_ai/firebase_ai.dart';

// SERVICES
import 'package:harkai/core/services/storage_service.dart';
import 'package:harkai/core/services/speech_service.dart';
import 'package:harkai/features/home/utils/extensions.dart'; // Asegúrate de tener esto

class IncidentMediaServices {
  final SpeechPermissionService _speechPermissionService;

  IncidentMediaServices({String? apiKey})
      : _speechPermissionService = SpeechPermissionService();

  // --- CONFIGURACIÓN E INICIALIZACIÓN DEL MODELO GEMINI (Vertex AI) ---
  GenerativeModel get _model {
    final vertexAI = FirebaseAI.vertexAI(location: 'us-central1');
    return vertexAI.generativeModel(
      model: 'gemini-2.5-flash',
      generationConfig: GenerationConfig(
        temperature:
            0.4, // Temperatura baja para respuestas más "robóticas" y precisas
        maxOutputTokens: 800,
      ),
      safetySettings: [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium,
            HarmBlockMethod.probability),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium,
            HarmBlockMethod.probability),
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.medium,
            HarmBlockMethod.probability),
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.medium,
            HarmBlockMethod.probability),
      ],
    );
  }

  // --- Lógica de Instrucción (Prompting) ---
  String _generateAiInstruction({
    required String incidentTypeName,
    required String specificInstruction,
    required String responseFormats,
  }) {
    const incidentContext = "CONTEXT: Analyze security reports. "
        "Types: THEFT (robbery, stealing), CRASH (accidents), FIRE (smoke, explosion), "
        "EMERGENCY (medical, natural disaster), EVENT (parties, protests), "
        "PLACE (adding a business/park/store to map - NOT an incident).";

    const languageInstruction =
        "LANGUAGE: If input is Spanish, description MUST be Spanish. "
        "KEYWORDS (MATCH, MISMATCH, UNCLEAR) MUST be English.";

    return "Intent: Report '$incidentTypeName'. "
        "$incidentContext "
        "$languageInstruction "
        "RESPONSE FORMATS: $responseFormats "
        "$specificInstruction";
  }

  // --- Permission Service ---
  Future<PermissionStatus> getMicrophonePermissionStatus() async {
    return await Permission.microphone.status;
  }

  Future<bool> requestMicrophonePermission(
      {bool openSettingsOnError = true}) async {
    return await _speechPermissionService.requestMicrophonePermission(
        openSettingsOnError: openSettingsOnError);
  }

  // --- Initialization ---
  GenerativeModel initializeGeminiModel() {
    return _model;
  }

  // --- Analysis Methods ---

  Future<String?> analyzeAudioWithGemini({
    required Uint8List audioBytes,
    required String audioMimeType,
    required String incidentTypeName,
  }) async {
    // FORMATO SIMPLIFICADO PARA DETECCIÓN AUTOMÁTICA
    const responseFormats = "1. 'MATCH: [Summary]'\n"
        "2. 'MISMATCH: [SUGGESTED_TYPE]' (Example: 'MISMATCH: Fire', 'MISMATCH: Theft')\n"
        "3. 'UNCLEAR: [Reason]'";

    final audioInstruction = _generateAiInstruction(
      incidentTypeName: incidentTypeName,
      specificInstruction: "Analyze audio content.",
      responseFormats: responseFormats,
    );

    try {
      final response = await _model.generateContent([
        Content.text(audioInstruction),
        Content.inlineData(audioMimeType, audioBytes),
      ]);
      return response.text?.trim();
    } catch (e) {
      debugPrint("AnalyzeAudio failed: $e");
      return null;
    }
  }

  Future<String?> analyzeTextWithGemini({
    required String text,
    required String incidentTypeName,
  }) async {
    if (text.isEmpty) return null;

    const responseFormats = "1. 'MATCH: [Summary]'\n"
        "2. 'MISMATCH: [SUGGESTED_TYPE]' (Example: 'MISMATCH: Crash')\n"
        "3. 'UNCLEAR: [Reason]'";

    final textInstruction = _generateAiInstruction(
      incidentTypeName: incidentTypeName,
      specificInstruction: "Analyze text content.",
      responseFormats: responseFormats,
    );

    final userPrompt = "$textInstruction\n\nUser Input: $text";

    try {
      final response = await _model.generateContent([Content.text(userPrompt)]);
      return response.text?.trim();
    } catch (e) {
      return null;
    }
  }

  Future<String?> analyzeImageWithGemini({
    required Uint8List imageBytes,
    required String imageMimeType,
    required String incidentTypeName,
  }) async {
    const responseFormats = "1. 'MATCH:' (If relevant)\n"
        "2. 'MISMATCH: [SUGGESTED_TYPE]' (Example: 'MISMATCH: Event')\n"
        "3. 'UNCLEAR: [Reason]'\n"
        "4. 'INAPPROPRIATE: [Reason]'";

    final imageInstruction = _generateAiInstruction(
      incidentTypeName: incidentTypeName,
      specificInstruction: "Check safety first, then relevance.",
      responseFormats: responseFormats,
    );

    try {
      final response = await _model.generateContent([
        Content.text(imageInstruction),
        Content.inlineData(imageMimeType, imageBytes),
      ]);
      return response.text?.trim();
    } catch (e) {
      return null;
    }
  }

  // --- Storage Service ---
  Future<String?> uploadIncidentImage({
    required StorageService storageService,
    required File imageFile,
    required String userId,
    required String incidentType,
  }) async {
    try {
      return await storageService.uploadIncidentImage(
        imageFile: imageFile,
        userId: userId,
        incidentType: incidentType,
      );
    } catch (e) {
      return null;
    }
  }
}
