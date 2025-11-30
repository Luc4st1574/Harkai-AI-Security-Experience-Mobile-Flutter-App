import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_ai/firebase_ai.dart';

// SERVICES
import 'package:harkai/core/services/storage_service.dart';
import 'package:harkai/core/services/speech_service.dart';

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
        temperature: 0.7,
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

  // --- Lógica de Instrucción Consolidada (Prompting) ---

  String _generateAiInstruction({
    required String incidentTypeName,
    required String specificInstruction,
    required String responseFormats,
  }) {
    const incidentContext =
        "On the theft incident type, this includes all kinds of theft, robbery, or burglary. even car theft and armed robbery all kinds of theft, robbery, or burglary please be conscious of this and if it as a theft incident do always a good check. "
        "On the crash incident type, this includes all kinds of car accidents, motorcycle accidents, and pedestrian accidents. "
        "On the fire incident type, this includes all kinds of fires, explosions, or smoke. "
        "On the emergency incident type, this includes all kinds of emergencies, like medical emergencies, natural disasters, or other urgent situations, lesions and all related this is a incident type that must be open to a lot of posible thing so be conscius of all kind of possible emergencies. "
        "On the places incident type, this is for addding businesses, stores,parks,plazas,malls and so on to the map, this is not for incidents but for adding places to the map so be conscious of this and do not use it for incidents, here just add what the user tells you do not try to give it more context or description cause it will look weird, just repeat what the user says on this kind incident do not add anything else, IMAGES like logos are acepeted too. "
        "On the event incident type, this includes community gatherings, parties, concerts, protests, cultural events, sports matches, or any public or private scheduled activity. This is for reporting social things happening now or planned. ";

    // UPDATED SPANISH LOGIC
    const languageInstruction =
        "STRICT LANGUAGE RULE: Analyze the input (audio, text, or image details). If the user speaks Spanish, writes in Spanish, or uses ANY Spanish words/slang: "
        "1. The DESCRIPTION/CONTENT of your response MUST be in Spanish. "
        "2. The SYSTEM KEYWORDS ('MATCH', 'MISMATCH', 'UNCLEAR', 'INAPPROPRIATE') MUST remain in English for code parsing. "
        "Example of correct Spanish response: 'MATCH: Se ha reportado un robo a mano armada en la tienda.' "
        "Do NOT translate the keywords (MATCH/MISMATCH) to Spanish. Do NOT write the description in English if the input is Spanish.";

    return "Incident Type: '$incidentTypeName'. Process the following media. "
        "$incidentContext "
        "Expected response formats: $responseFormats "
        "$languageInstruction "
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

  // --- Analysis Methods (Implementación Directa) ---

  /// Envía datos de audio al modelo Gemini.
  Future<String?> analyzeAudioWithGemini({
    required Uint8List audioBytes,
    required String audioMimeType,
    required String incidentTypeName,
  }) async {
    const specificInstruction = "Analyze the audio provided below.";
    const responseFormats =
        "'MATCH: [Short summary, max 15 words, of the audio content related to the incident type.]', "
        "'MISMATCH: This audio seems to describe a [Correct Incident Type] incident. Please confirm this type or re-record for the \$incidentTypeName incident.', "
        "'UNCLEAR: The audio was not clear enough or did not describe a reportable incident for '\$incidentTypeName'. Please try recording again with more details.'";

    final audioInstruction = _generateAiInstruction(
      incidentTypeName: incidentTypeName,
      specificInstruction: specificInstruction,
      responseFormats:
          responseFormats.replaceAll('\$incidentTypeName', incidentTypeName),
    );

    try {
      final response = await _model.generateContent([
        Content.text(audioInstruction),
        Content.inlineData(
          audioMimeType,
          audioBytes,
        ),
      ]);
      return response.text;
    } catch (e) {
      debugPrint("AnalyzeAudio failed: ${e.toString()}");
      return null;
    }
  }

  /// Envía texto al modelo Gemini.
  Future<String?> analyzeTextWithGemini({
    required String text,
    required String incidentTypeName,
  }) async {
    if (text.isEmpty) {
      debugPrint("IncidentMediaServices: Text input is empty.");
      return null;
    }

    const specificInstruction = "Analyze the text provided below.";
    const responseFormats =
        "'MATCH: [Short summary, max 15 words, of the text content related to the incident type.]', "
        "'MISMATCH: This text seems to describe a [Correct Incident Type] incident. Please confirm this type or re-enter for the \$incidentTypeName incident.', "
        "'UNCLEAR: The text was not clear enough or did not describe a reportable incident for '\$incidentTypeName'. Please try entering again with more details.'";

    final textInstruction = _generateAiInstruction(
      incidentTypeName: incidentTypeName,
      specificInstruction: specificInstruction,
      responseFormats:
          responseFormats.replaceAll('\$incidentTypeName', incidentTypeName),
    );

    final userPromptWithInstruction = "$textInstruction\n\nUser Input: $text";

    try {
      final response = await _model.generateContent([
        Content.text(userPromptWithInstruction),
      ]);
      return response.text;
    } catch (e) {
      debugPrint("AnalyzeText failed: ${e.toString()}");
      return null;
    }
  }

  /// Envía datos de imagen al modelo Gemini.
  Future<String?> analyzeImageWithGemini({
    required Uint8List imageBytes,
    required String imageMimeType,
    required String incidentTypeName,
  }) async {
    const specificInstruction = "Analyze the image provided below.";

    const imageSafetyInstruction =
        "1. SAFETY: If image contains explicit sexual content or excessive gore, respond EXACTLY with 'INAPPROPRIATE: The image contains content that cannot be posted.'. "
        "2. RELEVANCE (If safe): Does image genuinely match the Incident Type? ";

    // ADDED 'Event' to the list of valid other types in MISMATCH
    const responseFormats =
        "IF MATCHES INCIDENT TYPE: Respond EXACTLY 'MATCH:'. "
        "IF MISMATCH (but valid other type like Fire, Crash, Theft, Pet, Emergency, Event): Respond EXACTLY 'MISMATCH: This image looks more like a [Correct Incident Type] alert. Please confirm this type or retake image for \$incidentTypeName incident.'. "
        "IF IRRELEVANT/UNCLEAR: Respond EXACTLY 'UNCLEAR: The image is not clear enough or does not seem to describe a reportable incident for '\$incidentTypeName'. Please try retaking the picture.'.";

    final imageInstruction = _generateAiInstruction(
      incidentTypeName: incidentTypeName,
      specificInstruction: "${imageSafetyInstruction}$specificInstruction",
      responseFormats:
          responseFormats.replaceAll('\$incidentTypeName', incidentTypeName),
    );

    try {
      final response = await _model.generateContent([
        Content.text(imageInstruction),
        Content.inlineData(
          imageMimeType,
          imageBytes,
        ),
      ]);
      return response.text;
    } catch (e) {
      debugPrint("AnalyzeImage failed: ${e.toString()}");
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
      debugPrint(
          "IncidentMediaServices: Failed to upload image via StorageService: ${e.toString()}");
      return null;
    }
  }
}
