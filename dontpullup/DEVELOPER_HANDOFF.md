# Don't Pull Up - Developer Handoff Document

## Project Overview
"Don't Pull Up" is an iOS application that allows users to report and view incidents on a map. Users can place pins at their current location, categorize incidents (Verbal, Physical, Emergency), and attach videos as evidence.

## Core Architecture

### App Structure
The app follows a clean architecture with clear separation of concerns:
- **Models**: Data structures like `Pin` and `IncidentType`
- **Views**: SwiftUI views for UI components
- **ViewModels**: Business logic and state management
- **Services**: Firebase integration and other external services
- **Authentication**: User management and authentication

### Key Files and Their Responsibilities

#### App Entry Points
- `App/DontpullupApp.swift`: Main app entry point, initializes Firebase and core services
- `App/AppDelegate.swift`: Handles Firebase configuration, notifications, and app lifecycle
- `SceneDelegate.swift`: Scene lifecycle management

#### Authentication
- `Authentication/AuthenticationManager.swift`: Centralized Firebase Auth management
- `Authentication/AuthState.swift`: Observable authentication state for the app

#### Models
- `Models/Pin.swift`: Represents incident pins with coordinates, type, and video URL
- `Models/IncidentType.swift`: Enum for incident types (Verbal, Physical, Emergency)
- `Models/User.swift`: User data model with profile information

#### ViewModels
- `ViewModels/MapViewModel.swift`: Core logic for map interactions, pin management, and location services
- `ViewModels/AuthViewModel.swift`: Authentication flow management

#### Views
- `Views/RootView.swift`: Main container view that handles auth state routing
- `Views/MapView.swift`: Map interface with pin display and interaction
- `Views/MainTabView.swift`: Main app interface after authentication
- `Views/SimplifiedReportFlow.swift`: User flow for reporting incidents

#### Services
- `Services/FirebaseManager.swift`: Centralized Firebase service
- `Services/NotificationManager.swift`: Push notification handling
- `Services/NetworkMonitor.swift`: Internet connectivity monitoring

## Firebase Integration

### Authentication
- Email/password authentication
- Anonymous authentication for quick access
- User profiles stored in Firestore with email and zip code

### Firestore Collections
- `pins`: Stores incident reports with location, type, and video URL
- `users`: User profiles with zip code and FCM token for notifications

### Storage
- Videos are stored in Firebase Storage under `videos/` with UUID filenames

### Cloud Messaging
- Push notifications for nearby incidents based on zip code

## Key Features & User Flow

### User Journey
1. **Onboarding**: First-time users see a tutorial explaining app functionality
2. **Authentication**: Users sign up with email, password, and zip code
3. **Map Interface**: Main screen shows the map with incident pins
4. **Reporting**: Users can report incidents by long-pressing on the map
5. **Notifications**: Users receive alerts about nearby incidents

### Map Interface
- MapKit integration with custom pin annotations
- 200-foot radius restriction for pin placement (safety feature)
- Filter pins by incident type using the side buttons
- Toggle between standard and satellite map views
- "My Pins" filter to show only user's own reports

### Incident Reporting Flow
1. Long-press to drop a pin (must be within 200 feet of user location)
2. Select incident type (Verbal, Physical, Emergency)
3. Select video from photo library or record live video  (max 3 minutes)
4. Upload with progress indicator
5. Pin appears on the map after successful upload

### User Authentication
- Sign up with email, password, and zip code
- Sign in with existing credentials
- Anonymous access for limited functionality
- User profiles stored in Firestore

### Notifications
- Receive alerts about nearby incidents
- Notifications based on zip code proximity
- FCM token management for push notifications

## Development Guidelines

### Code Style
- Follow Swift naming conventions (camelCase for variables, PascalCase for types)
- Use descriptive variable and function names
- Add comments for complex logic

### SwiftUI Best Practices
- Use `@MainActor` for UI-related code
- Wrap async calls in `Task {}` for SwiftUI Button handlers
- Use `[weak self]` in closures to prevent retain cycles
- Use proper error handling with do-catch blocks for Firebase operations

### Firebase Operations
- Always use async/await for Firebase operations (not withCheckedThrowingContinuation)
- Use do-catch blocks for all Firebase calls
- Print errors for debugging: `print("Error: \(error)")`

### Error Handling
- Use `do-catch` for functions that can throw errors
- Avoid force-unwrapping (`!`); use optional binding (`if let`, `guard let`)

### Location Services
- Request location only when needed, not continuously
- Handle permission states gracefully
- Provide clear error messages for location issues

## Testing Requirements
- Test authentication flows (sign up, sign in)
- Verify pin placement within 200-foot radius
- Test video uploads with various file sizes
- Verify notifications are working correctly
- Test offline behavior with NetworkMonitor

## Technical Challenges & Performance Considerations

### Memory Management
- Video handling can be memory-intensive; ensure proper cleanup
- Use `[weak self]` in all closures to prevent retain cycles
- Monitor memory usage during video uploads

### Network Considerations
- The app includes a `NetworkMonitor` to detect connectivity changes
- Implement graceful degradation when offline
- Cache map data when possible to reduce data usage

### Location Accuracy
- GPS accuracy varies by device and environment
- The 200-foot restriction uses `CLLocationDistance` for consistency
- Test in various environments to ensure reliable performance

### Firebase Optimization
- Batch Firestore operations when possible
- Use efficient queries with proper indexing
- Implement pagination for large data sets

## Known Issues and Limitations
- Video uploads require stable internet connection
- Location accuracy may vary based on device and environment
- Maximum video length is restricted to 3 minutes
- Pins can only be placed within 200 feet of user location
- Debug overlays may appear in development builds

## Future Development
- Implement account deletion (already stubbed in AuthenticationManager)
- Enhance notification filtering
- Add more robust offline support
- Improve video compression for faster uploads
- Implement caching for better offline experience
- Add unit and UI tests for core functionality

## Build and Deployment
- Target iOS 16.6+
- Ensure all required permissions are in Info.plist:
  - `NSLocationWhenInUseUsageDescription`
  - `NSPhotoLibraryUsageDescription`
  - `UIBackgroundModes` for notifications

## File Structure and Organization

### Core Files
The app is organized with a clear separation of concerns:

```
dontpullup/
  |- App/                    # App lifecycle and configuration
  |- Authentication/         # Auth management
  |- Models/                 # Data models
  |- Services/               # External services integration
  |- Utils/                  # Utility classes and extensions
  |- ViewModels/             # Business logic
  |- Views/                  # UI components
```

### Essential Files
- `App/AppDelegate.swift`: Firebase setup and push notification configuration
- `Authentication/AuthenticationManager.swift`: User authentication and profile management
- `Models/Pin.swift`: Core data model for incident pins
- `ViewModels/MapViewModel.swift`: Main business logic for the map interface
- `Views/MapView.swift`: Map UI implementation
- `Views/RootView.swift`: Main navigation controller

## Important Rules to Follow
1. Never use withCheckedThrowingContinuation; use async/await for Firebase operations
2. Use do-catch for all Firebase calls (Auth, Firestore, Storage)
3. Centralize Firebase Auth in AuthenticationManager.swift
4. Wrap SwiftUI async calls in Task {}
5. Use [weak self] in closures
6. Never use await on viewModel properties (e.g., viewModel.showAlert = true)
7. Add comments for complex logic
8. Maintain the existing file structure and naming conventions

## Quick Reference

### Important Constants
- Pin drop limit: 200 feet (~61 meters)
- Maximum video length: 3 minutes
- Minimum iOS version: 16.6+

### Common Tasks
- **Adding a new view**: Create a new SwiftUI view in the Views directory
- **Firebase operations**: Use the FirebaseManager singleton for Firestore access
- **Authentication**: Use AuthenticationManager.shared for all auth operations
- **Location updates**: Access through MapViewModel's location services
- **Error handling**: Always use do-catch with proper error messages

### Debugging Tips
- Check console logs for Firebase authentication issues
- Monitor network connectivity with NetworkMonitor
- Test location features in physical devices when possible
- Use Firebase console to verify data is being stored correctly
