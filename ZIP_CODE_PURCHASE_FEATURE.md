# Zip Code Purchase Feature - Implementation Summary

## Overview
Users can now purchase individual zip codes for permanent video access, or upgrade to Premium for unlimited access.

## User Experience Flow

### 1. **Watching a Locked Video**

When a non-premium user taps a pin in a zip code they don't have access to:

```
┌─────────────────────────────────┐
│       Video Locked              │
├─────────────────────────────────┤
│ This video is in zip code       │
│ 10001. Unlock this area or      │
│ upgrade to Premium for          │
│ unlimited access.               │
├─────────────────────────────────┤
│ [Unlock Zip 10001 ($0.99)]     │
│ [Premium Unlimited ($4.99)]     │
│ [Cancel]                        │
└─────────────────────────────────┘
```

**3 Options:**
- **Unlock Zip 10001 ($0.99)** - One-time purchase for that specific area
- **Premium Unlimited ($4.99)** - Subscription for all areas
- **Cancel** - Close the alert

### 2. **Zip Code Purchase View**

Accessed via:
- Alert when watching locked video → "Unlock Zip..." button
- Premium View → "Unlock Zip Codes" button
- Profile → Can see purchased zip codes

**Layout:**
```
┌─────────────────────────────────────┐
│        🗺️  Unlock Zip Codes         │
│                                     │
│  Get permanent access to videos     │
│  in specific areas                  │
│                                     │
│  ┌─ Your Unlocked Areas ──────────┐│
│  │ 🏠 53216          Home         ││
│  │ ✓  10001          Unlocked     ││
│  │ ✓  53212          Unlocked     ││
│  └────────────────────────────────┘│
│                                     │
│  ┌─ Unlock a New Area ────────────┐│
│  │ Enter a zip code to unlock      │
│  │ videos from that area           │
│  │ permanently                     │
│  │                                 │
│  │ [Enter Zip Code: _____]        ││
│  │                                 │
│  │ [🔓 Unlock for $0.99]          ││
│  │                                 │
│  │ One-time purchase • Permanent   ││
│  └────────────────────────────────┘│
│                                     │
│  ─── OR ───                         │
│                                     │
│  [⭐ Upgrade to Premium]            │
│  Watch videos from all areas        │
│  $4.99/month                        │
└─────────────────────────────────────┘
```

### 3. **Premium View (Updated)**

Now shows two options:

```
┌─────────────────────────────────────┐
│     ⭐ Premium Upgrade               │
│                                     │
│     Choose your access level        │
│                                     │
│  ┌─ Option 1: Individual Areas ──┐ │
│  │ 🗺️  Unlock specific zip codes  │ │
│  │ 💲 $0.99 per zip code          │ │
│  │ ✓  One-time purchase           │ │
│  │                                │ │
│  │ [Unlock Zip Codes]             │ │
│  └────────────────────────────────┘ │
│                                     │
│              OR                     │
│                                     │
│  ┌─ Option 2: Premium Unlimited ─┐ │
│  │ 🌎 Watch videos from ALL areas │ │
│  │ 🗺️  Change your zip code       │ │
│  │ 🔔 Multiple area notifications │ │
│  │                                │ │
│  │        $4.99                   │ │
│  │ [Upgrade Now]                  │ │
│  └────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### 4. **Profile View (Updated)**

Shows unlocked areas:

```
┌─ Your Location ───────────────────┐
│                                   │
│ Unlocked Areas:                   │
│ 🏠 53216 (Home)                   │
│ ✓  10001                          │
│ ✓  53212                          │
│ ⭐ All Areas (Premium)  [if premium]
│                                   │
│ Enter your zip code to receive    │
│ notifications...                  │
└───────────────────────────────────┘
```

## Technical Implementation

### Data Model

**UserProfile (User.swift)**
```swift
struct UserProfile {
  var isPremium: Bool              // Unlimited access subscription
  var originalZipCode: String       // Home zip (always accessible)
  var purchasedZipCodes: [String]   // Individually purchased zips
  
  // Helper function
  func hasAccessToZipCode(_ zipCode: String) -> Bool {
    // Returns true if: isPremium OR zipCode == originalZipCode OR purchasedZipCodes.contains(zipCode)
  }
}
```

### Video Access Logic

**MapViewModel.canWatchVideo()**
```
1. Get user profile
2. If isPremium → ✅ Allow
3. If pin.zipCode == originalZipCode → ✅ Allow
4. If purchasedZipCodes.contains(pin.zipCode) → ✅ Allow
5. Get current GPS location
6. Reverse geocode → currentZipCode
7. If pin.zipCode == currentZipCode → ✅ Allow
8. Otherwise → ⛔ Block (show purchase options)
```

### Purchase Flow

**Individual Zip Code:**
1. User taps "Unlock Zip 10001 ($0.99)"
2. StoreKit processes payment
3. On success: Add "10001" to `purchasedZipCodes` array in Firestore
4. Reload user profile
5. User can now watch videos from zip 10001 forever

**Premium Unlimited:**
1. User taps "Premium Unlimited ($4.99)"
2. StoreKit processes subscription
3. On success: Set `isPremium = true` in Firestore
4. User can now watch all videos everywhere

### StoreKit Products

**App Store Connect Setup Needed:**

1. **Individual Zip Code Unlock**
   - Product ID: `com.dontpullup.app.zipcode_single`
   - Type: Non-consumable (one-time purchase)
   - Price: $0.99
   - Description: "Unlock videos from a specific zip code"

2. **Premium Unlimited**
   - Product ID: `com.dontpullup.app.premium_unlimited`
   - Type: Auto-renewable subscription
   - Price: $4.99/month (or $39.99/year)
   - Description: "Unlimited access to videos from all areas"

## Firestore Schema

**users/{userId}**
```json
{
  "id": "user123",
  "email": "user@example.com",
  "zipCode": "53216",
  "originalZipCode": "53216",
  "isPremium": false,
  "purchasedZipCodes": ["10001", "53212", "90210"],
  "fcmToken": "...",
  "createdAt": "...",
  "lastActive": "..."
}
```

## Access Matrix

| User Type | Home Zip | Current Zip | Purchased Zips | Can Access |
|-----------|----------|-------------|----------------|------------|
| Free | 53216 | 53212 | [] | 53216, 53212 |
| Purchased | 53216 | 53212 | [10001, 90210] | 53216, 53212, 10001, 90210 |
| Premium | 53216 | 53212 | [any] | ALL |

## Revenue Model

### Free Tier:
- Home zip code access (always)
- Current location access (while in that zip)
- Unlimited pin viewing
- Can drop pins anywhere

### Pay-Per-Zip ($0.99 each):
- All free tier features
- Permanent access to specific purchased zip codes
- Good for users with 2-3 areas they care about
- Example: Home + Work + Parents' neighborhood

### Premium Unlimited ($4.99/month):
- All features everywhere
- Unlimited zip code access
- Can change notification zip code anytime
- Best for users who travel or want full access

## Example Scenarios

**Scenario 1: College Student**
- Home: 02138 (Cambridge, MA)
- School: 10027 (NYC)
- Purchases: 10027 for $0.99
- Access: Can watch videos from Cambridge (home) + NYC (purchased) + wherever they currently are

**Scenario 2: Traveler**
- Home: 90210 (LA)
- Travels frequently
- Upgrades to Premium for $4.99/month
- Access: Can watch videos from anywhere in the US

**Scenario 3: Local User**
- Home: 53216 (Milwaukee)
- Rarely leaves area
- Free tier works perfectly
- Access: Can watch videos from 53216 + current location (usually same)

## Testing Checklist

- [ ] Create new user in zip 53216
- [ ] Try to watch video from zip 10001 (should be blocked)
- [ ] Purchase zip 10001
- [ ] Confirm can now watch 10001 videos
- [ ] Profile shows purchased zip codes
- [ ] Sign out and back in - purchases persist
- [ ] Upgrade to premium - all areas unlocked
- [ ] Test restore purchases

## Files Modified

1. **Models/User.swift** - Added `purchasedZipCodes` array
2. **ViewModels/MapViewModel.swift** - Updated `canWatchVideo()` logic
3. **Services/PremiumManager.swift** - Added `purchaseZipCode()` function
4. **Views/MapView.swift** - Updated video access alert with purchase options
5. **Views/PremiumView.swift** - Added two-tier option display
6. **Views/ZipCodePurchaseView.swift** - NEW: Dedicated zip code purchase interface
7. **Views/ProfileView.swift** - Display purchased zip codes
8. **Views/MainTabView.swift** - Added sheet for ZipCodePurchaseView

## Next Steps

1. **App Store Connect Setup:**
   - Create the two IAP products
   - Submit for review
   - Test with sandbox account

2. **UI Polish:**
   - Add animations for successful purchases
   - Toast notifications when zip code is unlocked
   - Confetti or celebration effect

3. **Analytics:**
   - Track which zip codes are most purchased
   - Monitor premium vs individual zip conversions
   - A/B test pricing

4. **Marketing:**
   - Highlight the flexibility in app description
   - "Buy just what you need, or get unlimited access"

