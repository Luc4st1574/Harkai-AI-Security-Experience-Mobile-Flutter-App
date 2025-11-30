import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  // ValueNotifiers allow parts of the app to listen for changes
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  // Options: 'all', 'critical', 'none'
  final ValueNotifier<String> notificationFilter = ValueNotifier('all');

  // Load settings when the app starts
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Theme
    final isDark = prefs.getBool('isDarkMode');
    if (isDark != null) {
      themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
    }

    // Load Notifications
    notificationFilter.value = prefs.getString('notificationFilter') ?? 'all';
  }

  // Toggle Dark Mode
  Future<void> toggleTheme(bool isDark) async {
    themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDark);
  }

  // Set Notification Filter
  Future<void> setNotificationFilter(String filter) async {
    notificationFilter.value = filter;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notificationFilter', filter);
  }
}
