# RouteGuard Weather

RouteGuard Weather is a SwiftUI app I built to check weather conditions along a driving route.  
It uses Apple’s MapKit to calculate routes between two locations and then checks the weather at several points along the trip using data from the OpenWeather API.

## How it works
- Enter a start and destination city.
- The app finds the route using MapKit.
- It samples a few points along the route (about every 30 miles).
- For each point, it fetches the current weather and flags any severe conditions like heavy rain or thunderstorms.
- The route and weather icons are displayed on the map, with a list of all weather points below.

## Tech stack
- **SwiftUI** for the interface  
- **MapKit** for routes and maps  
- **CoreLocation** for coordinates  
- **URLSession + Codable** for API calls and JSON parsing  
- **OpenWeather One Call API** for live weather data

## Setup
1. Create a free account on [OpenWeather](https://openweathermap.org/api) and get an API key.  
2. Add your key in `ContentView.swift`:
   ```swift
   private let weatherAPIKey = "YOUR_API_KEY_HERE"
   
Build and run the project on an iPhone simulator or your Mac.

Notes

Works on both macOS and iOS.

If no API key is added, the app uses simulated weather data for testing.

Built with Xcode 16 and Swift 6.
