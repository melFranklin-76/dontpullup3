# Quick Test Guide - Geographic Filtering

## 🚀 Quick Start Testing

### Step 1: Build & Run
```bash
# Open in Xcode and run on simulator or device
# Or use command line:
xcodebuild -project dontpullup.xcodeproj -scheme Dontpullup -destination 'generic/platform=iOS' build
```

### Step 2: Watch Console Logs
Look for these key messages when app starts:

✅ **Expected Good Logs:**
```
[FirestorePins] Querying pins in region: lat [min, max], lon [min, max]
[MapViewModel] Loading pins from Firestore for region centered at CLLocationCoordinate2D(...)
[MapViewModel] Successfully loaded X pins in region
```

❌ **Bad Logs (Should NOT appear):**
```
[MapViewModel] Loading pins from Firestore  // Without "for region" = old code
[MapViewModel] Found X pins  // Without "in region" = old code
```

### Step 3: Test Scenarios

#### Scenario A: Initial Load
1. Launch app
2. Grant location permission
3. Check console: Should see geographic query bounds
4. Verify: Only pins near you are loaded

#### Scenario B: Pan Map
1. Pan map to different city (drag map)
2. Wait 2-3 seconds
3. Check console: Should see new query with new bounds
4. Verify: Pins update for new region

#### Scenario C: Zoom
1. Zoom in (pinch)
2. Zoom out (pinch)
3. Check console: Radius should adjust
4. Verify: Pin count may change

### Step 4: Performance Check

**What to Measure:**
- Initial load time: Should be < 3 seconds
- Network transfer: Should be < 500KB (check in Network instrument)
- Pin count: Should be < 500 pins

**Before vs After:**
- Before: Loads ALL pins globally (could be 1000+)
- After: Loads only regional pins (~50-200)

---

## 🔍 Debug Commands

### Check if geographic filtering is working:
```bash
# Search logs for geographic query
grep "Querying pins in region" logs.txt

# Check if old code still exists (should NOT find these)
grep "getAllPins\|addSnapshotListener.*pins" dontpullup/ViewModels/MapViewModel.swift
```

### Verify implementation:
```bash
# Check FirestorePins has new method
grep "getPinsInRegion" dontpullup/Services/FirestorePins.swift

# Check MapViewModel uses it
grep "getPinsInRegion\|refreshPinsForCurrentRegion" dontpullup/ViewModels/MapViewModel.swift
```

---

## ✅ Success Indicators

You'll know it's working if:
1. ✅ Console shows "Querying pins in region" with bounds
2. ✅ Loaded pin count is reasonable (< 500)
3. ✅ Pins refresh when panning map
4. ✅ Faster initial load time
5. ✅ Lower network usage

---

## 🐛 Common Issues

**Issue:** Still loading all pins
- Check: Console should say "for region centered at"
- Fix: Verify `loadPins()` calls `getPinsInRegion()`

**Issue:** No pins loading
- Check: Firebase connection
- Check: Location permissions
- Check: Console for errors

**Issue:** Too many reloads
- Check: Console for "Region unchanged" message
- Fix: Increase `minimumRegionChangeThreshold` if needed

---

## 📊 Expected Performance

### Before Optimization:
- Network: 2-5 MB (all pins)
- Load time: 5-10 seconds
- Pins loaded: 1000+ (all globally)

### After Optimization:
- Network: < 500 KB (regional)
- Load time: 1-3 seconds  
- Pins loaded: 50-200 (regional only)

---

**Ready to test!** Run the app and check console logs.

