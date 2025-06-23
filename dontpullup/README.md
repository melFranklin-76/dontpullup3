# Don't Pull Up

A location-based incident reporting iOS application that allows users to report and view incidents on a map.

## About

Don't Pull Up is an iOS app that enables users to:
- Report incidents with video evidence
- View incidents on an interactive map
- Filter incidents by type (Verbal, Physical, Emergency)
- Receive notifications about nearby incidents

## Key Features

- **Map-based Interface**: View and filter incidents on an interactive map
- **Incident Reporting**: Long-press to place a pin and upload video evidence
- **200-foot Restriction**: Safety feature limiting pin placement to user's vicinity
- **Push Notifications**: Receive alerts about incidents in your zip code area
- **User Authentication**: Sign up with email, password, and zip code

## Technical Stack

- Swift & SwiftUI
- Firebase (Authentication, Firestore, Storage, Cloud Messaging)
- MapKit for map interface
- AVFoundation for video handling

## Getting Started

For developers taking over this project, please refer to the `DEVELOPER_HANDOFF.md` file for detailed information about the codebase structure, architecture, and development guidelines.

## Requirements

- iOS 16.0+
- Xcode 14.0+
- Firebase project with proper configuration 