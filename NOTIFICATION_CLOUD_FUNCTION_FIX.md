# Notification Cloud Function Fix

## Issue Identified
The Cloud Function `sendIncidentNotification` was returning error code 13 (INTERNAL) when called from the iOS app. This prevented push notifications from being sent to users in the same zip code when a pin was created.

## Root Cause
**Circular Reference in Logging Code**: The Cloud Function was crashing immediately due to a circular reference error when trying to log the incoming request. 

At line 41, the code attempted:
```javascript
console.log("Full data object:", JSON.stringify(data, null, 2));
```

The `data` object contains Socket and HTTPParser objects with circular references that cannot be serialized by `JSON.stringify()`, causing this error:
```
TypeError: Converting circular structure to JSON
    --> starting at object with constructor 'Socket'
    |     property 'parser' -> object with constructor 'HTTPParser'
    --- property 'socket' closes the circle
```

This crashed the function before it could even attempt to send notifications, resulting in the INTERNAL error code 13 on the iOS side.

## Changes Made

### 1. Updated Cloud Function (`functions/index.js`)

**Primary Fix - Removed Circular Reference:**
- **Lines 38-46**: Simplified logging to avoid `JSON.stringify()` on objects with circular references
- Changed from detailed object serialization to simple property logging
- Only log safe primitive values (counts, strings, keys)

**Additional Improvements:**
- **Lines 66-72**: Added explicit conversion of all data payload values to strings (FCM requirement)
- **Lines 76-91**: Added comprehensive message object with APNS-specific configuration for iOS
- **Line 95**: Changed from `sendMulticast()` to `sendEachForMulticast()` for better error tracking
- **Lines 113-117**: Improved response mapping with detailed error information
- **Lines 119-130**: Simplified error logging to avoid circular references while preserving useful info

### Key Code Changes:

**Before (Problematic):**
```javascript
console.log("Full data object:", JSON.stringify(data, null, 2)); // ❌ Crashes on circular refs
console.log("Full message object:", JSON.stringify(message, null, 2)); // ❌ Potentially problematic
```

**After (Fixed):**
```javascript
console.log("Data keys:", Object.keys(data || {}));
console.log("Tokens count:", data.tokens ? data.tokens.length : 0);
console.log("Sending FCM message to", tokens.length, "device(s)");
```

**Additional Features Added:**
```javascript
// Ensure all data values are strings (FCM requirement)
const stringData = {};
if (payloadData && typeof payloadData === 'object') {
  for (const [key, value] of Object.entries(payloadData)) {
    stringData[key] = String(value);
  }
}

// Added APNS configuration for iOS
apns: {
  payload: {
    aps: {
      sound: "default",
      badge: 1,
    },
  },
}
```

### 2. Deployed to Firebase
Successfully deployed the updated Cloud Function to the `ongrandma1` Firebase project in the `us-central1` region.

**Deployment Details:**
- Deployed: November 10, 2025 (twice - initial deployment and then circular reference fix)
- Function Name: `sendIncidentNotification`
- Region: `us-central1`
- Runtime: Node.js 22
- Status: ACTIVE

**Note:** After deployment, the function may take 1-2 minutes to fully roll out and become available for new requests.

## Testing Instructions

To verify the fix works:

1. **Open the app on a physical iOS device** (push notifications don't work in simulator)
2. **Ensure you're signed in** with a user account
3. **Long-press on the map** to drop a pin
4. **Select an incident type** (Verbal, Physical, or 911)
5. **Record a video** (keep it short for testing)
6. **Monitor the Xcode console** for these log messages:
   ```
   [NotificationManager] 🚀 Preparing to call Cloud Function with X tokens
   [NotificationManager] ✅ Cloud Function returned successfully!
   [NotificationManager] 📤 Successfully sent to X device(s)
   ```

7. **Check Firebase Console > Functions > Logs** for detailed Cloud Function execution logs
8. **Verify another device receives the notification** (if there's another user in the same zip code)

## What to Look For

### Success Indicators:
- ✅ No more error code 13 (INTERNAL) in Xcode console
- ✅ Cloud Function returns successfully with success count
- ✅ Firebase Function logs show successful message sending
- ✅ Other users in the same zip code receive push notifications

### If Issues Persist:
1. Check Firebase Console > Functions > Logs for detailed error messages
2. Verify FCM tokens are valid and registered for test users
3. Ensure devices have notification permissions enabled
4. Check that the app is registered with APNs (Apple Push Notification service)

## Additional Notes

- The function now includes comprehensive logging for debugging
- All error messages are captured and logged with full stack traces
- The APNS configuration ensures iOS devices receive notifications properly
- Badge count is set to 1 for each notification

## Files Modified
- `functions/index.js` - Updated Cloud Function with better error handling and FCM compliance
- Deployed to Firebase project: `ongrandma1`

## Next Steps
Test the notification functionality and monitor the logs. If any errors occur, they will now be logged with much more detail in the Firebase Console.


