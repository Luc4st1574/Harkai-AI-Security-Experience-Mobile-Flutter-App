// lib/features/home/modals/share_incident_modal.dart

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class ShareIncidentModal extends StatelessWidget {
  final String incidentId;

  const ShareIncidentModal({super.key, required this.incidentId});

  void _shareIncident(BuildContext context) {
    // Generamos el link con el ID real
    final String url = 'https://harkai-b2b-nu.vercel.app/incidents/$incidentId';
    Share.share(
        '¡Alerta de seguridad en Harkai! He reportado un incidente. Ver detalles aquí: $url');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF001F3F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.0),
        side: const BorderSide(color: Colors.blueGrey, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline,
                  color: Colors.greenAccent, size: 50),
            ),
            const SizedBox(height: 20),
            const Text(
              "¡Incidente Publicado!",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              "Gracias por tu reporte. Tu colaboración ayuda a mantener segura a la comunidad.",
              style: TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _shareIncident(context),
                icon: const Icon(Icons.share, color: Colors.white),
                label: const Text("Compartir reporte",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text("Cerrar", style: TextStyle(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showShareIncidentDialog({
  required BuildContext context,
  required String incidentId,
}) {
  return showDialog(
    context: context,
    builder: (context) => ShareIncidentModal(incidentId: incidentId),
  );
}
