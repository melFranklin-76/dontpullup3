const {setGlobalOptions} = require("firebase-functions");
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

// Force redeployment - v3
setGlobalOptions({maxInstances: 10});

exports.sendIncidentNotification = functions.https.onCall(async (request, context) => {
  console.log("=== Cloud Function Called ===");
  
  // For callable functions, the payload is in request.data or just request
  const data = request.data || request;
  
  console.log("Payload keys:", Object.keys(data));
  
  const tokens = data.tokens;
  const title = data.title;
  const body = data.body;
  const payloadData = data.data;
  const tokenOwners = data.tokenOwners || {};
  
  console.log("Tokens:", tokens ? tokens.length : 0);
  console.log("Title:", title);

  if (!Array.isArray(tokens) || tokens.length === 0) {
    console.error("No valid tokens");
    throw new functions.https.HttpsError("invalid-argument", "No tokens");
  }

  try {
    // Convert all data values to strings (FCM requirement)
    const stringData = {};
    if (payloadData && typeof payloadData === 'object') {
      for (const [key, value] of Object.entries(payloadData)) {
        stringData[key] = String(value);
      }
    }
    
    console.log("Sending to", tokens.length, "devices");
    
    const message = {
      tokens: tokens,
      notification: {
        title: title || "Incident Nearby",
        body: body || "",
      },
      data: stringData,
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };
    
    const response = await admin.messaging().sendEachForMulticast(message);
    
    console.log("SUCCESS! Sent:", response.successCount, "Failed:", response.failureCount);
    
    if (response.failureCount > 0) {
      const cleanupPromises = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          const token = tokens[idx];
          console.error("Failed token", idx, token, ":", resp.error);
          const ownerId = tokenOwners[token];
          if (ownerId) {
            const promise = admin.firestore()
              .collection("users")
              .doc(ownerId)
              .update({
                fcmToken: admin.firestore.FieldValue.delete(),
              })
              .then(() => console.log("Cleared invalid token for user", ownerId))
              .catch((err) => console.error("Failed to clear token for user", ownerId, err));
            cleanupPromises.push(promise);
          }
        }
      });
      await Promise.allSettled(cleanupPromises);
    }
    
    return {
      successCount: response.successCount,
      failureCount: response.failureCount,
      responses: response.responses.map(r => ({
        success: r.success,
        messageId: r.messageId,
        error: r.error ? r.error.message : null,
      })),
    };
  } catch (error) {
    console.error("ERROR:", error.message);
    throw new functions.https.HttpsError("internal", error.message || "Failed");
  }
});
