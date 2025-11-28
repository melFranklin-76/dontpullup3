# Setting Up In-App Purchases for Don't Pull Up

This document provides instructions for configuring the in-app purchase for premium zip code access in App Store Connect.

## Product Configuration

1. **Sign in to App Store Connect**: https://appstoreconnect.apple.com

2. **Navigate to your app**: Select "Don't Pull Up" from your apps list

3. **Go to In-App Purchases**: Click on the "In-App Purchases" tab

4. **Add a new In-App Purchase**:
   - Click the "+" button
   - Select "Non-Consumable" as the type

5. **Configure the product**:
   - **Reference Name**: "Zip Code Upgrade" (internal name only)
   - **Product ID**: `com.dontpullup.zipcode.unlock` (must match the ID used in code)
   - **Cleared for Sale**: Yes
   - **Price Tier**: Tier 1 ($0.99 USD)

6. **Add localizations**:
   - **Display Name**: "Premium Access"
   - **Description**: "Unlock access to incidents across all zip codes"
   - Add any additional languages as needed

7. **Review Information**:
   - **Review Notes**: "This purchase unlocks the ability to view and receive notifications for incidents outside the user's home zip code."
   - **Screenshot**: Upload a screenshot of the purchase screen

8. **Save and submit** for review along with your app update

## Testing In-App Purchases

### Sandbox Testing

1. **Create sandbox testers**:
   - Go to "Users and Access" in App Store Connect
   - Select "Sandbox" tab
   - Add test accounts with valid email addresses

2. **Testing on device**:
   - Sign out of your regular Apple ID on the test device
   - Launch the app and attempt to make a purchase
   - You'll be prompted to sign in with an App Store account
   - Use your sandbox tester credentials
   - Complete the purchase flow (no actual charges will be made)

3. **Testing in simulator**:
   - The app is configured to use test mode in DEBUG builds
   - This will simulate successful purchases without contacting the App Store

### StoreKit Configuration Testing

For local testing during development:

1. Create a StoreKit configuration file in Xcode:
   - File > New > File > StoreKit Configuration File
   - Add your product with the ID `com.dontpullup.app.zipcode_upgrade`
   - Set price tier, name, and description

2. Enable StoreKit testing in your scheme:
   - Edit your scheme
   - In the Run phase, select "Options" tab
   - Set "StoreKit Configuration" to your configuration file

## Implementation Details

The app uses StoreKit 2 API to handle in-app purchases. Key files:

- `PremiumManager.swift`: Handles all StoreKit interactions
- `PremiumView.swift`: UI for the purchase screen

The product ID is defined in `PremiumManager.swift` as `zipCodeUnlockProductID`.

## Troubleshooting

- **Missing Products**: Ensure the product ID in code matches exactly what's in App Store Connect
- **Sandbox Issues**: Make sure your sandbox tester account is properly set up and not already used
- **Receipt Validation**: The app uses StoreKit 2's built-in receipt validation

## App Store Guidelines Compliance

The implementation follows Apple's guidelines for in-app purchases:

- Clear disclosure of what the purchase provides
- Proper handling of restore purchases functionality
- Appropriate error handling and user feedback
- No misleading information about the purchase

## Support

For issues with the implementation, contact the development team at support@dontpullup.com 
