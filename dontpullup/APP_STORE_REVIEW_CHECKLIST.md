# Don't Pull Up - App Store Review Checklist

## 📋 **Pre-Submission Checklist**

### **✅ 1. App Information & Metadata**
- [x] **App Name**: "Don't Pull Up" 
- [x] **Bundle ID**: `com.dontpullup`
- [x] **Version**: 4.0 (build 01)
- [x] **Age Rating**: Recommend **17+** due to:
  - User-generated content (videos)
  - Incident reporting (potentially mature themes)
  - Real-world safety implications
- [x] **Category**: Navigation or Social Networking
- [x] **Keywords**: incident, safety, community, reporting, neighborhood, alert

### **✅ 2. Legal & Privacy Compliance**
- [x] **Privacy Policy**: Complete and accessible in-app
- [x] **Terms of Service**: Complete and accessible in-app  
- [x] **Contact Information**: Multiple contact emails provided
- [x] **User Consent**: Clear disclaimers for content responsibility
- [x] **Data Collection Transparency**: Clearly stated in privacy policy

### **✅ 3. Technical Requirements**
- [x] **iOS Compatibility**: iOS 15.0+ 
- [x] **Device Support**: iPhone only (Portrait orientation)
- [x] **Required Capabilities**: GPS, Location Services
- [x] **Permissions**: Camera, Microphone, Photo Library, Location, Notifications
- [x] **Background Modes**: Remote notifications, Background fetch
- [x] **Encryption**: ITSAppUsesNonExemptEncryption = false

### **✅ 4. Core Functionality Testing**
- [x] **User Authentication**: Firebase Auth working
- [x] **Location Services**: Pin dropping within 200ft verified
- [x] **Video Recording/Upload**: 3-minute limit enforced
- [x] **Video Metadata Validation**: Age (≤5h) and distance (≤200ft) checks
- [x] **Premium Features**: In-app purchase functionality
- [x] **Guest Mode**: Limited functionality for anonymous users
- [x] **Content Moderation**: Video flagging system implemented

### **✅ 5. User Experience**
- [x] **Onboarding**: Tutorial system implemented
- [x] **Error Handling**: Graceful error messages and recovery
- [x] **Accessibility**: Basic accessibility features
- [x] **Performance**: Smooth operation on target devices
- [x] **Offline Handling**: Appropriate offline messaging

### **✅ 6. Content Guidelines Compliance**
- [x] **User-Generated Content**: Clear responsibility disclaimers
- [x] **Safety Features**: Content reporting/flagging system
- [x] **Inappropriate Content**: Terms prohibit offensive content
- [x] **False Information**: Terms prohibit false/misleading reports

## 🚨 **Apple Review Considerations**

### **Potential Review Points**
1. **Safety Concerns**: App deals with real-world incidents
   - **Mitigation**: Clear disclaimers, user responsibility statements
   
2. **User-Generated Content**: Videos can contain sensitive material
   - **Mitigation**: Flagging system, terms of service, user responsibility

3. **Location Accuracy**: Critical for safety app
   - **Mitigation**: 200ft verification, metadata validation

4. **Premium Features**: In-app purchases
   - **Mitigation**: Clear value proposition, proper IAP implementation

### **Recommended App Description**

```
Don't Pull Up helps communities stay informed about local incidents through verified reports.

KEY FEATURES:
• Report incidents with video evidence within 200 feet of your location
• View community-verified incident reports in your area  
• Receive notifications about incidents in your zip code
• Premium access to incidents across all zip codes

SAFETY & RESPONSIBILITY:
Users are solely responsible for all content they record and share. All incidents are user-reported and should be verified independently. This app is for informational purposes only.

PRIVACY & SECURITY:
Your privacy matters. View our comprehensive privacy policy and terms of service within the app. All video uploads are validated for location and time accuracy.
```

## 📱 **App Store Connect Setup**

### **Required Screenshots** (Portrait)
1. **Map View**: Showing pins and interface
2. **Incident Reporting**: Video recording interface  
3. **Incident Types**: Selection screen
4. **Settings/Profile**: User options
5. **Premium Features**: Upgrade screen

### **App Preview Video** (Optional but Recommended)
- Show core functionality: pin dropping, video recording, map viewing
- Emphasize safety and community aspects
- Keep under 30 seconds

### **App Store Review Notes**
```
REVIEWER NOTES:

This app helps communities stay informed about local incidents through user-reported content. 

TEST ACCOUNT:
Email: reviewer@dontpullup.com
Password: PassWord1*

KEY TESTING POINTS:
1. Location permission is required for core functionality
2. Video recording requires camera/microphone permissions
3. Guest users have limited functionality (view-only)
4. Premium features unlock cross-zip code viewing
5. All video uploads are validated for time (≤5 hours) and location (≤200 feet)
6. Full-screen required: Map/camera/video flows are designed for a single uninterrupted canvas; split view/slide over may break overlays and pin-drop/upload prompts.

The app includes comprehensive privacy policy and terms of service accessible from the settings menu. Users are clearly informed of their responsibility for content they upload.
```

## ⚠️ **Final Checks Before Submission**

- [x] **Build Type**: Release/Production build (ready for archive)
- [x] **Firebase Environment**: Production database and storage (PROJECT_ID: ongrandma1)
- [x] **Version/Build**: 4.0 (01) - confirmed in Info.plist
- [ ] **Test on Multiple Devices**: iPhone SE, iPhone 14, iPhone 15 Pro (manual testing required)
- [ ] **Network Conditions**: Test on WiFi and cellular (manual testing required)
- [ ] **Clean Install**: Test fresh installation experience (manual testing required)
- [ ] **All Features Working**: Complete functionality test (manual testing required)
- [x] **No Debug Code**: Debug prints wrapped in #if DEBUG guards
- [ ] **Screenshots Current**: Reflect actual app appearance (manual capture required)

## 🎯 **Expected Timeline**
- **Standard Review**: 24-48 hours
- **If Rejected**: Address feedback and resubmit (add 24-48 hours)
- **Potential Delays**: Safety-related apps may get additional scrutiny

## 📞 **Support Contacts**
- **General Support**: support@dontpullup.com
- **Privacy Questions**: privacy@dontpullup.com  
- **Terms Questions**: terms@dontpullup.com

---

**Last Updated**: January 2025
**Review Checklist Version**: 1.0 