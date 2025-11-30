const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// 1. KEEP YOUR EXISTING FUNCTION (It handles specific user entry events)
exports.sendGeofenceNotification = onDocumentCreated("geofence_events/{eventId}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  
  const eventData = snap.data();
  const userId = eventData.userId;

  try {
    const userDoc = await admin.firestore().collection("users").doc(userId).get();
    if (!userDoc.exists || !userDoc.data().deviceToken) return;

    const payload = {
      notification: {
        title: "You entered a high-risk zone",
        body: "Please be careful in this area."
      }
    };

    await admin.messaging().sendToDevice(userDoc.data().deviceToken, payload);
    logger.log("Geofence Entry Notification sent to:", userId);
  } catch (error) {
    logger.error("Error sending geofence notification:", error);
  }
});


// 2. NEW FUNCTION: Triggers when a NEW INCIDENT (HeatPoint) is added to DB
// This sends a "Mass Alert" to everyone subscribed to the 'incidents' topic.
exports.notifyUsersOnNewIncident = onDocumentCreated("HeatPoints/{incidentId}", async (event) => {
    const snap = event.data;
    if (!snap) {
        logger.log("No data associated with the incident event");
        return;
    }

    const incident = snap.data();
    const type = incident.type || "alert"; // e.g., 'fire', 'theft'
    const description = incident.description || "New security incident reported nearby.";

    // Define titles based on type (simple logic)
    let title = "Security Alert";
    if (type === 'fire') title = "🔥 Fire Alert Nearby!";
    else if (type === 'theft') title = "👮 Theft Reported Nearby";
    else if (type === 'crash') title = "🚗 Accident Reported";
    
    // Create the message for the 'incidents' TOPIC
    const message = {
        topic: 'incidents', // Sends to ALL users subscribed to this topic
        notification: {
            title: title,
            body: description,
        },
        data: {
            click_action: "FLUTTER_NOTIFICATION_CLICK",
            incidentId: event.params.incidentId,
            type: type,
            lat: String(incident.latitude),
            lng: String(incident.longitude)
        },
        android: {
            priority: 'high',
            notification: {
                channelId: 'harkai_channel_id', // Matches your Flutter channel
                priority: 'max',
                defaultSound: true,
            }
        }
    };

    try {
        const response = await admin.messaging().send(message);
        logger.log("Successfully sent message to 'incidents' topic:", response);
    } catch (error) {
        logger.error("Error sending topic notification:", error);
    }
});