import 'package:flutter/material.dart';
import 'package:harkai/core/services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();

  @override
  Widget build(BuildContext context) {
    final bool isDark = _settings.themeMode.value == ThemeMode.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        title: Text(
          "Configuración", // Spanish Title
          style: TextStyle(color: Theme.of(context).primaryColor),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).primaryColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader("Apariencia"), // Spanish Header
            _buildSwitchTile(
              title: "Modo Oscuro", // Spanish Option
              subtitle:
                  "Activar tema oscuro para interfaz y mapas", // Spanish Description
              value: isDark,
              onChanged: (val) {
                _settings.toggleTheme(val);
                setState(() {});
              },
            ),
            const Divider(color: Colors.grey),
            const SizedBox(height: 16),
            _buildSectionHeader("Notificaciones"), // Spanish Header
            const SizedBox(height: 8),
            _buildNotificationOption(
                "Todas las notificaciones", "all"), // Spanish Option
            _buildNotificationOption("Solo críticas (Incendio, Robo, SOS)",
                "critical"), // Spanish Option
            _buildNotificationOption("Ninguna", "none"), // Spanish Option
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    // Determine tile color based on theme
    final tileColor = Theme.of(context).cardColor;
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Container(
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SwitchListTile(
        title: Text(title,
            style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 12, color: textColor.withAlpha(180))),
        value: value,
        onChanged: onChanged,
        activeColor: Theme.of(context).primaryColor,
      ),
    );
  }

  Widget _buildNotificationOption(String title, String value) {
    final currentFilter = _settings.notificationFilter.value;
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    return RadioListTile<String>(
      title: Text(title, style: TextStyle(color: textColor)),
      value: value,
      groupValue: currentFilter,
      activeColor: Theme.of(context).primaryColor,
      onChanged: (val) {
        if (val != null) {
          _settings.setNotificationFilter(val);
          setState(() {});
        }
      },
    );
  }
}
