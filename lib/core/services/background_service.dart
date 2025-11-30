import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart'; // ADDED
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:harkai/core/managers/download_data_manager.dart';
import 'package:harkai/core/managers/geofence_manager.dart';
import 'package:harkai/core/managers/notification_manager.dart';
import 'package:harkai/core/models/geofence_model.dart'; // ADDED
import 'package:harkai/core/services/location_service.dart';
import 'package:harkai/l10n/app_localizations.dart';
import 'package:harkai/l10n/app_localizations_en.dart';
import 'package:harkai/l10n/app_localizations_es.dart';
import 'package:workmanager/workmanager.dart';

const String backgroundTask = "harkaiBackgroundTask";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // 1. Use a Completer to keep the task running while the stream is active.
    final Completer<bool> taskCompleter = Completer<bool>();

    // These ensure we can clean up the stream listeners if an error occurs.
    StreamSubscription<Position>? positionStreamSubscription;
    StreamSubscription<QuerySnapshot>?
        firestoreSubscription; // ADDED: Subscription for HeatPoints

    try {
      // 2. Initialize dependencies required for the background isolate.
      WidgetsFlutterBinding.ensureInitialized();
      await dotenv.load(fileName: ".env");
      await Firebase.initializeApp();

      // Dynamically select the localization class
      final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
      final AppLocalizations localizations = deviceLocale.languageCode == 'es'
          ? AppLocalizationsEs()
          : AppLocalizationsEn();

      final locationService = LocationService();
      final downloadDataManager = DownloadDataManager();
      final notificationManager =
          NotificationManager(localizations: localizations);
      final geofenceManager = GeofenceManager(
        downloadDataManager,
        onNotificationTrigger: notificationManager.handleIncidentNotification,
      );

      // Load initial data (First time load or periodic refresh)
      await geofenceManager.initialize();
      await notificationManager.initialize();
      debugPrint("Background Service: Managers initialized globally.");

      // 3. LISTEN TO FIRESTORE TRIGGERS (Real-time updates)
      // This will automatically download new incidences when they are added to the DB.
      firestoreSubscription = FirebaseFirestore.instance
          .collection('HeatPoints')
          .snapshots()
          .listen(
        (snapshot) {
          for (var change in snapshot.docChanges) {
            // We only care about added or modified documents
            if (change.type == DocumentChangeType.added ||
                change.type == DocumentChangeType.modified) {
              try {
                final newIncident = GeofenceModel.fromFirestore(change.doc);

                // Update the live manager immediately
                geofenceManager.addOrUpdateIncident(newIncident);

                // Update the local cache so it's available next time
                downloadDataManager.updateCacheWith(newIncident);

                debugPrint(
                    "Background Service: Real-time update received for incident: ${newIncident.id}");
              } catch (e) {
                debugPrint(
                    "Background Service: Error parsing real-time incident: $e");
              }
            }
          }
        },
        onError: (e) =>
            debugPrint("Background Service: Firestore stream error: $e"),
      );

      // 4. Listen to the location stream and manage the completer's state.
      positionStreamSubscription = locationService.getPositionStream().listen(
        (Position newPosition) {
          // This will now run continuously as the task is kept alive.
          geofenceManager.onLocationUpdate(newPosition);
        },
        onError: (error) {
          debugPrint('Error in background location stream: $error');
          positionStreamSubscription?.cancel();
          firestoreSubscription?.cancel(); // Cancel Firestore listener too
          if (!taskCompleter.isCompleted) {
            taskCompleter.complete(false);
          }
        },
        onDone: () {
          debugPrint('Background location stream was closed.');
          positionStreamSubscription?.cancel();
          firestoreSubscription?.cancel(); // Cancel Firestore listener too
          if (!taskCompleter.isCompleted) {
            taskCompleter.complete(true);
          }
        },
      );
    } catch (e, s) {
      debugPrint('FATAL Error in background task setup: $e');
      debugPrint(s.toString());
      positionStreamSubscription?.cancel();
      firestoreSubscription?.cancel();
      if (!taskCompleter.isCompleted) {
        taskCompleter.complete(false);
      }
    }

    return taskCompleter.future;
  });
}
