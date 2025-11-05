# Geographic Filtering Test Plan
## Don't Pull Up - Performance Optimization Testing

**Date:** $(date)
**Feature:** Geographic Filtering for Pin Queries
**Status:** Ready for Testing

---

## 🎯 Test Objectives

Verify that geographic filtering:
1. ✅ Only loads pins within the specified radius
2. ✅ Reduces network bandwidth usage
3. ✅ Improves initial load time
4. ✅ Automatically refreshes when map region changes
5. ✅ Handles edge cases correctly

---

## 📋 Pre-Test Checklist

- [ ] App builds without errors
- [ ] Firebase connection is working
- [ ] Test device has location permissions enabled
- [ ] Test device has network connectivity
- [ ] Firestore database has pins at various locations

---

## 🧪 Test Cases

### Test 1: Initial Load Performance
**Objective:** Verify pins load only for current region

**Steps:**
1. Launch app fresh (clear app data first)
2. Grant location permissions
3. Wait for map to center on user location
4. Observe console logs

**Expected Results:**
- Console shows: `[FirestorePins] Querying pins in region: lat [...], lon [...]`
- Console shows: `[MapViewModel] Loading pins from Firestore for region centered at ...`
- Only pins within ~50km radius are loaded
- Initial load time < 3 seconds (if < 500 pins)

**Console Logs to Check:**
```
[FirestorePins] Querying pins in region: lat [minLat, maxLat], lon [minLon, maxLon]
[MapViewModel] Loading pins from Firestore for region centered at CLLocationCoordinate2D(...)
[MapViewModel] Successfully loaded X pins in region
```

**Pass Criteria:**
- ✅ Query includes geographic bounds
- ✅ Loaded pin count is reasonable (< 500)
- ✅ Load time is acceptable

---

### Test 2: Map Panning - Auto Refresh
**Objective:** Verify pins refresh when map region changes

**Steps:**
1. Load initial pins (from Test 1)
2. Pan map to a different location (> 1km away)
3. Wait 2-3 seconds
4. Observe console logs

**Expected Results:**
- Console shows: `[MapViewModel] Loading pins from Firestore for region centered at ...`
- New pins appear for the new region
- Old pins disappear (if outside new region)

**Console Logs to Check:**
```
[MapViewModel] Region unchanged, skipping reload  // Should NOT appear if moved significantly
[MapViewModel] Loading pins from Firestore for region centered at CLLocationCoordinate2D(...)
```

**Pass Criteria:**
- ✅ Pins refresh automatically when panning
- ✅ No "Region unchanged" log when moving significantly
- ✅ Pin count updates appropriately

---

### Test 3: Zoom In/Out Performance
**Objective:** Verify pin loading adjusts to zoom level

**Steps:**
1. Start with zoomed out view (city level)
2. Zoom in to street level
3. Zoom out again
4. Observe console logs and pin count

**Expected Results:**
- Pin count may change based on visible area
- Radius calculation adjusts based on map span
- No excessive reloads (throttling works)

**Pass Criteria:**
- ✅ Radius adjusts to zoom level
- ✅ Throttling prevents excessive queries
- ✅ Performance remains smooth

---

### Test 4: Edge Cases

#### 4a: No User Location
**Steps:**
1. Disable location permissions
2. Launch app
3. Observe pin loading

**Expected Results:**
- Uses map center as query center
- Still loads pins (just uses default region)
- No crashes

#### 4b: Very Few Pins in Region
**Steps:**
1. Pan to remote area with few pins
2. Observe loading

**Expected Results:**
- Loads successfully even with 0-5 pins
- No errors or crashes
- Console shows correct query

#### 4c: Many Pins in Region
**Steps:**
1. Pan to dense urban area
2. Observe loading

**Expected Results:**
- Limits to 500 pins max
- Loads within reasonable time
- Performance remains acceptable

---

### Test 5: Network Performance
**Objective:** Measure bandwidth improvement

**Before Optimization (Baseline):**
- Load all pins: Could be 1000+ pins = several MB
- Load time: 5-10 seconds for large datasets

**After Optimization (Expected):**
- Load regional pins: ~50-200 pins = < 500KB
- Load time: 1-3 seconds

**Test Steps:**
1. Use Network instrument in Xcode
2. Clear app data
3. Launch app and load pins
4. Record network transfer size
5. Compare with previous baseline

**Pass Criteria:**
- ✅ Network transfer < 1MB for initial load
- ✅ Reduced bandwidth usage by 50%+ (if had many pins before)

---

### Test 6: Query Validation
**Objective:** Verify query bounds are correct

**Steps:**
1. Note your current location
2. Load pins
3. Check console logs for query bounds
4. Verify pins are within expected radius

**Console Log Example:**
```
[FirestorePins] Querying pins in region: lat [40.5622, 40.7622], lon [-74.2266, -73.7866]
```

**Manual Verification:**
- Calculate expected bounds: center ± (radiusKm / 111.0)
- Verify console logs match expected bounds
- Verify loaded pins are within 50km radius

**Pass Criteria:**
- ✅ Query bounds are mathematically correct
- ✅ All loaded pins are within radius
- ✅ No pins outside radius are loaded

---

## 🔍 Debugging Tips

### Check Console Logs
Look for these key messages:
- `[FirestorePins] Querying pins in region:` - Shows query bounds
- `[MapViewModel] Loading pins from Firestore for region centered at:` - Shows center point
- `[MapViewModel] Region unchanged, skipping reload` - Throttling working
- `[MapViewModel] Successfully loaded X pins in region` - Final count

### Common Issues

**Issue:** Pins not loading
- Check Firebase connection
- Verify location permissions
- Check console for errors

**Issue:** Too many reloads
- Check `minimumRegionChangeThreshold` is working
- Verify throttling logic

**Issue:** Wrong pins loaded
- Check query bounds calculation
- Verify distance filtering is working
- Check Firestore data structure

---

## 📊 Performance Metrics

### Before Optimization (Baseline)
- Initial load: All pins globally
- Network transfer: 2-5 MB (with 1000+ pins)
- Load time: 5-10 seconds
- Memory: High (all pins in memory)

### After Optimization (Target)
- Initial load: Regional pins only
- Network transfer: < 500 KB (regional subset)
- Load time: 1-3 seconds
- Memory: Lower (only visible pins)

### Success Criteria
- ✅ 50%+ reduction in network transfer
- ✅ 50%+ reduction in load time
- ✅ Smooth panning without lag
- ✅ No crashes or errors

---

## 🚀 Running the Tests

### Option 1: Manual Testing
1. Build and run app on device
2. Follow test cases above
3. Observe console logs
4. Verify behavior matches expected results

### Option 2: Automated Testing (Future)
- Create unit tests for `getPinsInRegion()`
- Test query bounds calculation
- Test distance filtering logic

---

## 📝 Test Results Template

```
Test Date: ___________
Device: ___________
iOS Version: ___________
App Version: ___________

Test 1: Initial Load
- [ ] Pass
- [ ] Fail
- Notes: ___________

Test 2: Map Panning
- [ ] Pass
- [ ] Fail
- Notes: ___________

Test 3: Zoom Performance
- [ ] Pass
- [ ] Fail
- Notes: ___________

Test 4: Edge Cases
- [ ] Pass
- [ ] Fail
- Notes: ___________

Test 5: Network Performance
- Before: _____ MB
- After: _____ MB
- Improvement: _____ %

Test 6: Query Validation
- [ ] Pass
- [ ] Fail
- Notes: ___________

Overall Status: [ ] Pass [ ] Fail
Issues Found: ___________
```

---

## ✅ Sign-Off

Once all tests pass:
- [ ] Performance improvement verified
- [ ] No regressions introduced
- [ ] Ready for production
- [ ] Documented any issues

---

## 🔧 Quick Fixes

If issues are found:

**Issue:** Query not filtering correctly
- Check `getPinsInRegion()` logic
- Verify Firestore query syntax
- Check distance calculation

**Issue:** Excessive reloads
- Increase `minimumRegionChangeThreshold`
- Add debouncing to region changes

**Issue:** Missing pins
- Increase default radius
- Check query bounds calculation

---

**Ready to test!** Run through these test cases and report any issues.

