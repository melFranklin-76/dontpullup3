# Premium Features - Quick Reference Guide

## 🎯 Three Access Levels

### 1. **FREE** (Default)
**What You Get:**
- ✅ View all pins on the map
- ✅ Watch videos from your **home zip code** (where you registered)
- ✅ Watch videos from your **current location** (while you're there)
- ✅ Drop pins anywhere
- ✅ Unlimited pin creation

**Example:**
- Home: 53216
- Traveling in: 53212
- Can watch: 53216 videos + 53212 videos (while in 53212)
- Leave 53212 → lose access to 53212 videos

---

### 2. **PAY-PER-ZIP** ($0.99 each)
**What You Get:**
- ✅ Everything from FREE tier
- ✅ **Permanent access** to purchased zip codes
- ✅ Keep access even when not in that area
- ✅ No monthly fees

**Example:**
- Home: 53216
- Purchases: 10001 (NYC), 90210 (LA)
- Can watch: 53216 + 10001 + 90210 + current location
- Access to 10001 and 90210 **never expires**

**Best For:**
- Users with 2-5 specific areas they care about
- Example: Home + Work + Family's neighborhood
- Cost: ~$2-5 one-time vs $60/year for premium

---

### 3. **PREMIUM UNLIMITED** ($4.99/month or $39.99/year)
**What You Get:**
- ✅ Watch videos from **ANY zip code**
- ✅ Change your notification zip code anytime
- ✅ No restrictions whatsoever

**Best For:**
- Frequent travelers
- Users who want full access
- People interested in multiple cities

---

## 🛒 How to Purchase

### Individual Zip Code:

**Method 1: From Video Alert**
1. Tap a locked video pin
2. See alert: "This video is in zip code 10001..."
3. Tap "Unlock Zip 10001 ($0.99)"
4. Complete purchase
5. Video plays immediately

**Method 2: From Premium View**
1. Tap Profile → Premium button
2. Tap "Unlock Zip Codes"
3. Enter zip code (e.g., "10001")
4. Tap "Unlock for $0.99"
5. Complete purchase

**Method 3: From Zip Code Purchase View**
1. Navigate to Zip Code Purchase screen
2. See your current unlocked areas
3. Enter new zip code
4. Purchase

### Premium Unlimited:

1. Tap Profile → Premium button (or from video alert)
2. Tap "Upgrade Now" ($4.99)
3. Complete subscription
4. All areas instantly unlocked

---

## 📱 UI Locations

### Where You'll See Purchase Options:

1. **Video Alert** (when tapping locked video)
   - Shows zip code of the video
   - Options to unlock that zip or go premium

2. **Premium View**
   - Two-tier option display
   - Compare individual vs unlimited

3. **Zip Code Purchase View**
   - Dedicated screen for managing zip purchases
   - Shows all unlocked areas
   - Add new zip codes

4. **Profile View**
   - Lists all unlocked areas:
     - 🏠 Home zip
     - ✓ Purchased zips
     - ⭐ Premium badge (if unlimited)

---

## 💡 Smart Recommendations

The app suggests the right option based on usage:

- **Watching 1st locked video** → "Unlock this zip for $0.99"
- **Watching 3rd different locked zip** → "You've unlocked 2 zips. Upgrade to Premium for unlimited access?"
- **Frequent traveler** → "Save money with Premium - you've tried to access 5+ different areas"

---

## 🔐 Access Rules

### Non-Premium User Can Watch Videos When:
1. Pin is in **home zip code** ✅
2. Pin is in **purchased zip code** ✅
3. Pin is in **current GPS location zip code** ✅

### Premium User Can Watch:
- **ALL videos, everywhere** ✅

### Examples:

**User: Free tier, Home 53216, Currently in 53212**
- Pin in 53216 → ✅ (home)
- Pin in 53212 → ✅ (current location)
- Pin in 10001 → ⛔ (locked)

**User: Purchased [10001], Home 53216, Currently in 53212**
- Pin in 53216 → ✅ (home)
- Pin in 53212 → ✅ (current location)
- Pin in 10001 → ✅ (purchased)
- Pin in 90210 → ⛔ (locked)

**User: Premium, Home 53216, Currently in 53212**
- Pin anywhere → ✅ (premium = unlimited)

---

## 💰 Pricing Strategy

### Individual Zip Code: $0.99
**Revenue Calculation:**
- 1,000 users × 3 zips each = $2,970
- One-time revenue
- Low barrier to entry

### Premium Unlimited: $4.99/month
**Revenue Calculation:**
- 1,000 subscribers = $4,990/month = $59,880/year
- Recurring revenue
- Higher lifetime value

### Mixed Strategy:
- 70% free users
- 20% buy 1-3 zips ($0.99-2.97 each)
- 10% upgrade to premium ($4.99/mo)

**Example Revenue (10K users):**
- 7,000 free = $0
- 2,000 buy avg 2 zips = $3,980
- 1,000 premium @ $4.99/mo = $4,990/month = $59,880/year
- **Total Year 1: ~$63,860**

---

## 🧪 Testing in Debug Mode

Since `forceTestMode = true` in debug builds:

1. Tap locked video
2. Tap "Unlock Zip 10001 ($0.99)"
3. Wait 1 second (simulated)
4. Zip code automatically unlocked (no real payment)
5. Video plays

This lets you test the full flow without App Store Connect setup.

---

## ✅ What's Already Implemented

- [x] User model with purchasedZipCodes array
- [x] Video access logic checking purchased zips
- [x] Purchase flow for individual zip codes
- [x] Premium unlimited purchase flow
- [x] UI alerts with purchase options
- [x] Zip Code Purchase View
- [x] Updated Premium View (two-tier)
- [x] Profile showing purchased zips
- [x] Firestore integration
- [x] Test mode for development

## 🚀 Next Steps for Production

1. **App Store Connect:**
   - Create IAP products
   - Set up pricing tiers
   - Submit for review

2. **Add to Info.plist:**
   ```xml
   <key>SKAdNetworkItems</key>
   <array>
     <!-- StoreKit configuration -->
   </array>
   ```

3. **Test with Sandbox:**
   - Create test accounts in App Store Connect
   - Test real purchase flow
   - Verify receipts

4. **Polish:**
   - Add purchase success animations
   - Show "3 zips purchased - upgrade to premium?" prompts
   - Analytics tracking

---

## 🎨 UI/UX Highlights

**Smart Defaults:**
- Alert shows the exact zip code being blocked
- One-tap purchase for that specific zip
- Clear pricing ($0.99 vs $4.99)

**User-Friendly:**
- See all unlocked areas in one place
- Can't accidentally re-purchase same zip
- Clear benefits for each tier

**Flexible:**
- Start free
- Add zips as needed
- Upgrade to unlimited later
- No forced subscriptions

This creates a **freemium funnel** that converts users naturally based on their usage patterns.

