// ignore_for_file: avoid_print

import 'package:firebase_auth/firebase_auth.dart'; // For User object
import 'package:flutter/material.dart';
import '../../profile/screens/profile.dart';
import 'package:harkai/l10n/app_localizations.dart';
// Added Home import
import '../screens/home.dart';

class HomeHeaderWidget extends StatelessWidget {
  /// The current authenticated user. Can be null if no user is logged in.
  final User? currentUser;
  final VoidCallback? onLogoTap;
  final bool isLongPressEnabled;
  final String locationText; // New parameter for the location

  const HomeHeaderWidget({
    super.key,
    this.currentUser,
    this.onLogoTap,
    this.isLongPressEnabled = true,
    required this.locationText,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final String? photoURL = currentUser?.photoURL;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30), // Pill shape
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // 1. Logo Section (Left)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: GestureDetector(
                // MODIFIED: Now defaults to navigating to Home if no callback is provided.
                onTap: onLogoTap ??
                    () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const Home()),
                        (Route<dynamic> route) => false,
                      );
                    },
                // MODIFIED: Removed Places specific long press logic
                onLongPress: null,
                child: CircleAvatar(
                  backgroundColor:
                      const Color(0xFF011935), // Updated background color
                  radius: 22,
                  child: Image.asset(
                    'assets/images/logo.png',
                    height: 40,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.shield,
                          color: Color(0xFF57D463), size: 30);
                    },
                  ),
                ),
              ),
            ),

            // 2. Location Info (Center)
            Expanded(
              child: InkWell(
                // Optional: Make the text tap-able to reset location or show details
                onTap: () {
                  // Add logic here if you want tapping the text to do something
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text(
                        locationText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      localizations
                          .homeScreenLocationInfoText, // "Monitoring your zone"
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black, // Brand green
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

            // 3. User Profile (Right)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: InkWell(
                onTap: () {
                  print("User profile tapped. Navigating to Profile screen.");
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const Profile()),
                  );
                },
                borderRadius: BorderRadius.circular(30),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage:
                      photoURL != null ? NetworkImage(photoURL) : null,
                  child: photoURL == null
                      ? const Icon(
                          Icons.account_circle,
                          color: Color(0xFF57D463),
                          size: 40,
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
