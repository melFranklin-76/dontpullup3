# 🎉 Notification System - WORKING!

## Status: ✅ FIXED AND WORKING

Date: November 10, 2025

## The Problem

Cloud Function `sendIncidentNotification` was failing with multiple error codes when called from iOS:

### Error Code 13 (INTERNAL)
**Root Cause:** Circular reference crash in logging code at line 41:
```javascript
console.log("Full data object:", JSON.stringify(data, null, 2));
```

The `data` object contains Socket and HTTPParser objects with circular references:
```
TypeError: Converting circular structure to JSON
    --> starting at object with constructor 'Socket'
    |     property 'parser' -> object with constructor 'HTTPParser'
    --- property 'socket' closes the circle
```

This crashed the function before it could even attempt to send notifications.

### Error Code 3 (INVALID_ARGUMENT)
**Root Cause:** Firebase callable functions wrap the payload in `request.data`, but we were accessing `data` directly.

The function received:
```javascript
Data keys: ['rawRequest', 'auth', 'instanceIdToken', 'data', 'acceptsStreaming']
```

But we were trying to access `data.tokens` directly, which was `undefined`. The actual tokens were in `data.data.tokens`.

## The Solution

### Fixed Cloud Function (`functions/index.js`)

```javascript
exports.sendIncidentNotification = functions.https.onCall(async (request, context) => {
  // Extract payload from wrapped format
  const data = request.data || request;
  
  const tokens = data.tokens;
  const title = data.title;
  const body = data.body;
  const payloadData = data.data;
  
  // Convert all data values to strings (FCM requirement)
  const stringData = {};
  if (payloadData && typeof payloadData === 'object') {
    for (const [key, value] of Object.entries(payloadData)) {
      stringData[key] = String(value);
    }
  }
  
  // Send via FCM with APNS config for iOS
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
  return {
    successCount: response.successCount,
    failureCount: response.failureCount
  };
});
```

### Key Changes:

#### 1. Fixed Parameter Naming (Lines 9-13)
Changed from `data` to `request` to avoid confusion:
```javascript
// Before (causing issues):
exports.sendIncidentNotification = functions.https.onCall(async (data, context) => {
  const tokens = data.tokens; // undefined!
});

// After (working):
exports.sendIncidentNotification = functions.https.onCall(async (request, context) => {
  const data = request.data || request; // Properly extracts payload
  const tokens = data.tokens; // Works!
});
```

#### 2. Removed Circular Reference Logging (Lines 38-46)
```javascript
// Before (crashes):
console.log("Full data object:", JSON.stringify(data, null, 2));

// After (works):
console.log("Data keys:", Object.keys(data || {}));
console.log("Tokens count:", data.tokens ? data.tokens.length : 0);
```

#### 3. String Data Conversion (Lines 69-75)
FCM requires all `data` payload values to be strings:
```javascript
const stringData = {};
if (payloadData && typeof payloadData === 'object') {
  for (const [key, value] of Object.entries(payloadData)) {
    stringData[key] = String(value);
  }
}
```

#### 4. iOS APNS Configuration (Lines 86-93)
Added iOS-specific push notification settings:
```javascript
apns: {
  payload: {
    aps: {
      sound: "default",
      badge: 1,
    },
  },
}
```

#### 5. Better FCM Method (Line 98)
Changed from `sendMulticast()` to `sendEachForMulticast()` for better error tracking per device

## How It Works Now

### When a user drops a pin:

1. **MapViewModel** uploads video to Firebase Storage
2. **MapViewModel** saves pin to Firestore
3. **MapViewModel** calls `NotificationManager.notifyUsersInZipCode()`
4. **NotificationManager** queries Firestore for users in same zip code
5. **NotificationManager** collects FCM tokens (excludes pin creator)
6. **NotificationManager** calls Cloud Function with tokens
7. **Cloud Function** sends push notification via FCM
8. **Other users** receive notification on their devices

### Expected Console Output:

```
[MapViewModel] Sending notifications to users in zip code: 53212
[NotificationManager] Found 4 total users in zip code 53212
[NotificationManager] Added user ngcTU6u5LfZH1kXkrvM8zA5Jcbp2 to notification list
[NotificationManager] Final notification list: 1 users
[NotificationManager] 🚀 Calling Cloud Function to notify 1 OTHER users
[NotificationManager] 🔄 Calling 'sendIncidentNotification'...
[NotificationManager] ✅ SUCCESS! Cloud Function returned
[NotificationManager] 📤 Sent to 1 device(s)
```

## Test Results: ✅ WORKING

- User drops pin → ✅ Video uploaded
- Pin saved to Firestore → ✅ Success
- Cloud Function called → ✅ Success
- Notification sent → ✅ Delivered to 1 device
- Other user received notification → ✅ Confirmed working

## Files Modified

1. **functions/index.js** - Fixed Cloud Function with proper data extraction and FCM compliance
2. **dontpullup/Services/NotificationManager.swift** - Clean error logging

## Deployment Details

- **Function Name**: `sendIncidentNotification`
- **Region**: `us-central1`
- **Runtime**: Node.js 22
- **Status**: ACTIVE
- **Latest Deployment**: November 10, 2025 (v3)

## Next Steps

✅ Notifications are working  
✅ Ready for production  
✅ Ready for App Store submission  

## Debugging Journey

### Attempt 1: Initial Deployment
- **Error:** Code 13 (INTERNAL)
- **Cause:** Circular reference in `JSON.stringify()`
- **Fix:** Removed problematic logging

### Attempt 2: After Logging Fix
- **Error:** Code 3 (INVALID_ARGUMENT) - "No tokens provided"
- **Cause:** Accessing `data.tokens` when it was in `request.data.tokens`
- **Fix:** Changed parameter from `data` to `request` and extracted properly

### Attempt 3: Final Deployment (v3)
- ✅ **Success!** Notifications sending to devices
- ✅ FCM message ID: `projects/ongrandma1/messages/1762799215142046`
- ✅ Verified on physical devices in zip code 53212

## Firebase Console Log Evidence

**Successful execution (latest):**
```
=== Cloud Function Called ===
Data keys: tokens, title, body, data
Tokens: 1
Title: Incident Nearby
Prepared data payload with 5 keys
Sending FCM message to 1 device(s)
✅ Notification sent successfully!
📤 Success: 1 device(s)
❌ Failures: 0 device(s)
```

## Notes

- Notifications are sent to OTHER users in the same zip code only
- The user who creates the pin does NOT receive a notification
- FCM tokens must be valid and registered
- Devices must have notification permissions enabled
- Push notifications require physical devices (not simulator)
- Function uses Node.js 22 and Firebase Functions v6.0.1
- APNS configuration ensures proper iOS delivery with sound and badge

---

**Problem solved! 🎉**

### Lessons Learned
1. Firebase callable functions wrap payload in `request.data` - always extract it first
2. Never use `JSON.stringify()` on request objects with circular references
3. FCM requires all data payload values to be strings
4. iOS needs APNS configuration for proper notification delivery
5. Use `sendEachForMulticast()` instead of `sendMulticast()` for better error tracking

