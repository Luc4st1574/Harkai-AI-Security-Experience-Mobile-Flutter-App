// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart'; // Added for Firebase
import 'package:flutter/material.dart'; // Required for BuildContext and ScaffoldMessenger
import 'package:permission_handler/permission_handler.dart' as perm_handler;
import 'package:url_launcher/url_launcher.dart' as url_launcher;

/// A service class to handle phone call functionalities.
class PhoneService {
  /// Constructor for PhoneService.
  PhoneService() {
    print("PhoneService initialized.");
  }

  /// Requests permission to make phone calls.
  Future<bool> requestPhoneCallPermission(
      {bool openSettingsOnError = false}) async {
    print("Requesting phone call permission...");
    var status = await perm_handler.Permission.phone.status;

    if (status.isGranted) {
      print("Phone call permission already granted.");
      return true;
    }

    if (status.isDenied || status.isRestricted || status.isLimited) {
      print(
          "Phone call permission is denied/restricted/limited. Requesting...");
      status = await perm_handler.Permission.phone.request();
      if (status.isGranted) {
        print("Phone call permission granted after request.");
        return true;
      } else {
        print("Phone call permission denied after request.");
        return false;
      }
    }

    if (status.isPermanentlyDenied) {
      print("Phone call permission is permanently denied.");
      if (openSettingsOnError) {
        print("Attempting to open app settings for phone permission...");
        await perm_handler.openAppSettings();
      }
    }
    return false;
  }

  /// [NEW] Fetches the contact info from Firebase using the Incident ID and then makes the call.
  Future<void> makePhoneCallFromIncidentId({
    required String incidentId,
    required BuildContext context,
  }) async {
    try {
      print("Fetching contact info for incident: $incidentId");

      // Fetch the document from the 'HeatPoints' collection
      final DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('HeatPoints')
          .doc(incidentId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        // Access the 'contactInfo' field
        final String? contactInfo = data?['contactInfo'] as String?;

        if (contactInfo != null && contactInfo.isNotEmpty) {
          print("Found contact info: $contactInfo");
          // Proceed to make the call
          await makePhoneCall(phoneNumber: contactInfo, context: context);
        } else {
          print("No contact info found in document.");
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content:
                      Text('No phone number available for this incident.')),
            );
          }
        }
      } else {
        print("Incident document does not exist.");
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Incident details not found.')),
          );
        }
      }
    } catch (e) {
      print("Error fetching incident contact info: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching contact info: $e')),
        );
      }
    }
  }

  /// Attempts to make a phone call using the device's dialer.
  Future<void> makePhoneCall({
    required String phoneNumber,
    required BuildContext context,
    String permissionDeniedMessage =
        'Permission denied to make calls. Please enable it in settings.',
    String dialerErrorMessage = 'Could not launch dialer:',
  }) async {
    print("Attempting to make phone call to: $phoneNumber");

    // Ensure the phone number doesn't already have the scheme
    final String numberToDial =
        phoneNumber.startsWith('tel:') ? phoneNumber.substring(4) : phoneNumber;

    final Uri launchUri = Uri(
      scheme: 'tel',
      path: numberToDial,
    );

    bool permissionGranted =
        await requestPhoneCallPermission(openSettingsOnError: true);

    if (!permissionGranted) {
      print("Phone call permission not granted for $phoneNumber.");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(permissionDeniedMessage)),
        );
      }
      return;
    }

    try {
      print("Launching dialer for $phoneNumber...");
      bool launched = await url_launcher.launchUrl(
        launchUri,
        // Using external application mode is generally recommended for 'tel'
        mode: url_launcher.LaunchMode.externalApplication,
      );
      if (!launched) {
        print("Failed to launch dialer for $phoneNumber.");
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('$dialerErrorMessage Could not launch $launchUri')),
          );
        }
      } else {
        print("Dialer launched successfully for $phoneNumber.");
      }
    } catch (e) {
      print("Error launching dialer for $phoneNumber: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$dialerErrorMessage ${e.toString()}')),
        );
      }
    }
  }
}
