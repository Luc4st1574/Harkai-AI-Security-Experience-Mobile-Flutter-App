// lib/features/home/modals/modules/media_services.dart

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
        temperature:
            0.4, // Temperatura baja para respuestas más "robóticas" y precisas
        maxOutputTokens: 800,
      ),
      safetySettings: [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium,
            HarmBlockMethod.probability),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium,
            HarmBlockMethod.probability),
        // Allow medical/accident content for Emergency/Crash validation
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.medium,
            HarmBlockMethod.probability),
        // Keep explicit content blocked
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.medium,
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
    // 1. DEFINICIONES DETALLADAS (Your Provided Context)
    const incidentDefinitions = """
    CONTEXT & DEFINITIONS (Harkai App):
    
    1. PET (Mascota):
       - INTENT: Lost, found, or animal in danger.
       - IMAGE: Dogs, cats, domestic animals. Pictures of animals alone or with humans.
       - AUDIO: people resporting for a lost animal, descriptions of lost/found pets, or a person reporting their pet situation.
       - TEXT: people resporting for a lost animal, descriptions of lost/found pets, or a person reporting their pet situation.
    
    2. PLACE (Lugar/Negocio):
       - INTENT: Validate a physical location to add to the map (e.g., store, park, school). NOT an incident.
       - IMAGE: Storefronts, shop logos, parks, building facades, signs with names.
       - AUDIO:  A person reporting a business name, category, or address to register as a new place.
       - TEXT: A person typing a business name, category, or address to register as a new place.
    
    3. EVENT (Evento):
       - INTENT: Social gatherings or public activities (e.g., concert, protest).
       - IMAGE: Event posters, flyers, concert stages, crowds, parties, protests, meetings.
       - AUDIO: A person reporting details about the event, like name, date, time, or purpose.
       - TEXT: A person typing details about the event, like name, date, time, or purpose.
    
    4. EMERGENCY (Emergencia Médica/Salud):
       - SCOPE: Human health crises, injuries, medical urgency (lesiones, huesos rotos, problemas de salud).
       - IMAGE: People fainting, broken bones, blood (in medical context), ambulances, paramedics.
       - AUDIO: Screaming for help, breathing difficulties, mentioning "ambulance", "doctor", or specific injuries, or a person urgently reporting the medical emergency and more related topics.
       - TEXT: A person typing a clear, urgent report of a medical emergency, injury, or health crisis.
    
    5. THEFT (Robo):
       - INTENT: Robbery, burglary, stealing, pickpocketing.
       - IMAGE: Broken windows, someone running with stolen items, broken locks, pickpocketing.
       - AUDIO: a person reporting the theft and acts of breakin the law like extorsion, violence and more related or description of a theft fisical ones.
       - TEXT: a person reporting the theft and acts of breakin the law like extorsion, violence and more related or description of a theft fisical ones.
    6. FIRE (Incendio):
       - INTENT: Fire, explosion, or smoke visible.
       - IMAGE: Flames, heavy smoke, firefighters, burnt structures.
       - AUDIO: a person reporting the fire and all the posible variant like explosion etc.
       - TEXT: a person reporting the fire and all the posible variant like explosion etc.
    
    7. CRASH (Accidente de Tránsito):
       - INTENT: Vehicle accident (car, motorcycle, pedestrian).
       - IMAGE: Car collisions, damaged vehicles, road debris, motorcycles on the ground.
       - AUDIO: a person reporting the specific car accident and kind of vehicles.
       - TEXT: a person reporting the specific car accident and kind of vehicles.
    
    USER INPUT CONTEXT:
    - The content (audio, text, image) might be a person typing or recording themselves talking about what happened naturally.
    - Be FLEXIBLE to colloquialisms, incomplete sentences, and natural speech when determining the intention.
    
    SYSTEM DIRECTIVE:
    4. PRIORITY: Prioritize identifying the intent correctly over minor details.
    """;

    // 2. REGLAS DE IDIOMA Y PRIORIDAD (Usando 'final' para la interpolación)
    final languageInstruction = """
    SYSTEM DIRECTIVE:
    1. ANALYSIS: Compare the input media against the definition of '$incidentTypeName'.
    2. LANGUAGE: The logic keywords (MATCH, MISMATCH, UNCLEAR, INAPPROPRIATE) MUST be in ENGLISH.
    3. DESCRIPTION: The descriptive summary/reasoning MUST be in SPANISH (Español).
    4. PRIORITY: Prioritize identifying the intent correctly over minor details.
    """;

    return "$incidentDefinitions\n"
        "$languageInstruction\n"
        "CURRENT TARGET: The user is trying to report: '$incidentTypeName'.\n"
        "RESPONSE FORMATS:\n$responseFormats\n"
        "SPECIFIC TASK: $specificInstruction";
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

  // --- Analysis Methods (AUDIO) ---

  Future<String?> analyzeAudioWithGemini({
    required Uint8List audioBytes,
    required String audioMimeType,
    required String incidentTypeName,
  }) async {
    const responseFormats = "1. 'MATCH: [Resumen en Español]'\n"
        "2. 'MISMATCH: [SUGGESTED_TYPE]' (Types: Pet, Place, Event, Emergency, Fire, Theft, Crash)\n"
        "3. 'UNCLEAR: [Motivo en Español]'";

    final audioInstruction = _generateAiInstruction(
      incidentTypeName: incidentTypeName,
      specificInstruction:
          "Listen to the user's story or sounds. Does the intent match '$incidentTypeName'? Summarize in Spanish.",
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

  // --- Analysis Methods (TEXT) ---

  Future<String?> analyzeTextWithGemini({
    required String text,
    required String incidentTypeName,
  }) async {
    if (text.isEmpty) return null;

    const responseFormats = "1. 'MATCH: [Resumen mejorado en Español]'\n"
        "2. 'MISMATCH: [SUGGESTED_TYPE]' (Types: Pet, Place, Event, Emergency, Fire, Theft, Crash)\n"
        "3. 'UNCLEAR: [Motivo en Español]'";

    final textInstruction = _generateAiInstruction(
      incidentTypeName: incidentTypeName,
      specificInstruction:
          "Analyze the user's text description. Identify the core intent. Correct grammar in Spanish if it's a MATCH.",
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

  // --- Analysis Methods (IMAGE) ---

  Future<String?> analyzeImageWithGemini({
    required Uint8List imageBytes,
    required String imageMimeType,
    required String incidentTypeName,
  }) async {
    const responseFormats = "1. 'MATCH: [Descripción breve en Español]'\n"
        "2. 'MISMATCH: [SUGGESTED_TYPE]' (Types: Pet, Place, Event, Emergency, Fire, Theft, Crash)\n"
        "3. 'UNCLEAR: [Motivo en Español]'\n"
        "4. 'INAPPROPRIATE: [Motivo en Español]' (For sexual/prohibited content)";

    final imageInstruction = _generateAiInstruction(
      incidentTypeName: incidentTypeName,
      specificInstruction:
          "Analyze the image. 1. Check for sexual/prohibited content (INAPPROPRIATE). 2. Does the image visually confirm a '$incidentTypeName'? 3. If it clearly shows a different category, suggest it.",
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
