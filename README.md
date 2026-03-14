# LibreFang iOS App

LibreFang is an iOS companion application designed to monitor and manage your LibreFang server. It provides a comprehensive dashboard to track your agents, monitor API usage, and keep your budget under control.

## Features

*   **Dashboard Overview**: View live statistics on running agents, total configured agents, and today's total spend.
*   **Connection Monitoring**: Real-time health indicators showing whether the app is successfully connected to your LibreFang server.
*   **Budget Tracking**: Detailed gauges for hourly, daily, and monthly spending relative to your configured limits. Receive warnings when you are approaching your spending thresholds.
*   **Top Spenders Identification**: A breakdown of which agents have incurred the highest costs today.
*   **A2A Network Summary**: See how many external agents are connected via the A2A network.
*   **Agent Management**: Preview and manage your running AI agents, including identifying them by their assigned emoji identities.
*   **Offline Support**: Visual banners to alert you when your device loses internet connectivity, preventing stale data from causing confusion.

## Getting Started

1.  Open `librefang-ios.xcodeproj` in Xcode.
2.  Select your target simulator or physical iOS device.
3.  Configure your App settings (such as setting up the LibreFang Server URL).
4.  Build and run the project `(Cmd + R)`.

## Requirements

*   iOS 16.0+
*   Xcode 15.0+
*   Swift 5.9+

## Architecture

The project is built using modern SwiftUI architecture:
*   `Models`: Core data structures corresponding to the LibreFang server representations (e.g., `Agent`, `BudgetOverview`).
*   `ViewModels`: Controllers handling data fetching and state management (`DashboardViewModel`).
*   `Views`: SwiftUI views for the presentation layer (`OverviewView`, `AgentsView`, `SettingsView`, etc.).
*   `Services`: Network monitoring, LibreFang client API, and haptic feedback utilities.
