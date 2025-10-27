import SwiftUI
import MapKit
import Combine

// MARK: - API Configuration
private let weatherAPIKey = "Your_API_Key" // Replace with your OpenWeather API key

// MARK: - Weather API Models
struct WeatherResponse: Codable {
    let current: Current
    
    struct Current: Codable {
        let temp: Double
        let weather: [Condition]
    }
    
    struct Condition: Codable {
        let main: String
        let description: String
    }
}

// MARK: - Models
struct RouteWeatherPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let locationName: String
    let weatherCondition: String
    let hasWarning: Bool
    let warningDescription: String?
}

// MARK: - ViewModel
@MainActor
class RouteWeatherViewModel: ObservableObject {
    @Published var startLocation: String = ""
    @Published var endLocation: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var route: MKRoute?
    @Published var weatherPoints: [RouteWeatherPoint] = []
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 29.8833, longitude: -97.9414), // San Marcos, TX
        span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
    )
    
    func findRouteAndWeather() async {
        guard !startLocation.isEmpty, !endLocation.isEmpty else {
            errorMessage = "Please enter both locations"
            return
        }
        
        isLoading = true
        errorMessage = nil
        weatherPoints = []
        
        do {
            // Step 1: Geocode locations
            let startCoordinate = try await geocodeLocation(startLocation)
            let endCoordinate = try await geocodeLocation(endLocation)
            
            // Step 2: Calculate route
            let calculatedRoute = try await calculateRoute(from: startCoordinate, to: endCoordinate)
            self.route = calculatedRoute
            
            // Update map region to show route
            let routeBounds = calculatedRoute.polyline.boundingMapRect
            mapRegion = MKCoordinateRegion(routeBounds)
            
            // Step 3: Get points along route
            let routePoints = getPointsAlongRoute(calculatedRoute)
            
            // Step 4: Fetch weather for each point
            var weatherData: [RouteWeatherPoint] = []
            
            for (index, point) in routePoints.enumerated() {
                let weatherPoint = await fetchWeatherForPoint(point, index: index)
                weatherData.append(weatherPoint)
            }
            
            self.weatherPoints = weatherData
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func geocodeLocation(_ locationString: String) async throws -> CLLocationCoordinate2D {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(locationString)
        
        guard let coordinate = placemarks.first?.location?.coordinate else {
            throw NSError(domain: "RouteGuard", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find location: \(locationString)"])
        }
        
        return coordinate
    }
    
    private func calculateRoute(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        
        guard let route = response.routes.first else {
            throw NSError(domain: "RouteGuard", code: 2, userInfo: [NSLocalizedDescriptionKey: "No route found"])
        }
        
        return route
    }
    
    private func getPointsAlongRoute(_ route: MKRoute) -> [CLLocationCoordinate2D] {
        let polyline = route.polyline
        var points: [CLLocationCoordinate2D] = []
        
        // Get start point
        let startPoint = polyline.coordinate
        points.append(startPoint)
        
        // Sample points approximately every 30 miles (48 km)
        let totalDistance = route.distance // in meters
        let samplingInterval: CLLocationDistance = 48000 // 30 miles in meters
        var currentDistance: CLLocationDistance = samplingInterval
        
        while currentDistance < totalDistance {
            // Find point at this distance
            if let point = getCoordinateAt(distance: currentDistance, along: polyline) {
                points.append(point)
            }
            currentDistance += samplingInterval
        }
        
        // Get end point
        let endIndex = polyline.pointCount - 1
        let endPoint = polyline.points()[endIndex].coordinate
        points.append(endPoint)
        
        return points
    }
    
    private func getCoordinateAt(distance: CLLocationDistance, along polyline: MKPolyline) -> CLLocationCoordinate2D? {
        let pointCount = polyline.pointCount
        let points = polyline.points()
        
        var accumulatedDistance: CLLocationDistance = 0
        
        for i in 0..<(pointCount - 1) {
            let startCoord = points[i].coordinate
            let endCoord = points[i + 1].coordinate
            
            let segmentDistance = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
                .distance(from: CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude))
            
            if accumulatedDistance + segmentDistance >= distance {
                // The target distance falls within this segment
                let ratio = (distance - accumulatedDistance) / segmentDistance
                let lat = startCoord.latitude + (endCoord.latitude - startCoord.latitude) * ratio
                let lon = startCoord.longitude + (endCoord.longitude - startCoord.longitude) * ratio
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            
            accumulatedDistance += segmentDistance
        }
        
        return nil
    }
    
    private func fetchWeatherForPoint(_ coordinate: CLLocationCoordinate2D, index: Int) async -> RouteWeatherPoint {
        // Check if API key is still the placeholder
        if weatherAPIKey.isEmpty || weatherAPIKey == "YOUR_API_KEY_HERE" || weatherAPIKey == "f8cd7196a53fbf7c964c7b6d52af2cd8" {
            // Return simulated data if no valid API key
            let conditions = ["Clear", "Cloudy", "Light Rain", "Thunderstorm", "Heavy Rain"]
            let randomCondition = conditions.randomElement()!
            let randomTemp = Int.random(in: 50...85)
            let hasWarning = randomCondition.contains("Thunder") || randomCondition.contains("Heavy")
            
            return RouteWeatherPoint(
                coordinate: coordinate,
                locationName: "Point \(index + 1)",
                weatherCondition: "\(randomCondition) • \(randomTemp)°F",
                hasWarning: hasWarning,
                warningDescription: hasWarning ? "⚠️ Simulated: \(randomCondition)" : nil
            )
        }
        
        // Real API call
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        let urlString = "https://api.openweathermap.org/data/3.0/onecall?lat=\(lat)&lon=\(lon)&exclude=minutely,alerts&units=imperial&appid=\(weatherAPIKey)"
        
        print("🌤️ Fetching weather for point \(index + 1): \(urlString)")
        
        guard let url = URL(string: urlString) else {
            return RouteWeatherPoint(
                coordinate: coordinate,
                locationName: "Point \(index + 1)",
                weatherCondition: "Unavailable",
                hasWarning: true,
                warningDescription: "❌ Invalid URL"
            )
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // Check for HTTP errors
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 API Response Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 401 {
                    return RouteWeatherPoint(
                        coordinate: coordinate,
                        locationName: "Point \(index + 1)",
                        weatherCondition: "API Key Invalid",
                        hasWarning: true,
                        warningDescription: "⚠️ Check your OpenWeather API key"
                    )
                } else if httpResponse.statusCode != 200 {
                    return RouteWeatherPoint(
                        coordinate: coordinate,
                        locationName: "Point \(index + 1)",
                        weatherCondition: "API Error \(httpResponse.statusCode)",
                        hasWarning: true,
                        warningDescription: "⚠️ Failed to fetch weather"
                    )
                }
            }
            
            let weatherResponse = try JSONDecoder().decode(WeatherResponse.self, from: data)
            
            let condition = weatherResponse.current.weather.first?.main ?? "Unknown"
            let temperature = weatherResponse.current.temp
            let description = weatherResponse.current.weather.first?.description.capitalized ?? ""
            
            // Determine if this is a hazardous condition
            let hazardConditions = ["Thunderstorm", "Snow", "Squall", "Tornado"]
            let hasWarning = hazardConditions.contains(condition) ||
                             description.lowercased().contains("heavy rain") ||
                             description.lowercased().contains("extreme")
            
            print("✅ Weather fetched: \(condition), \(Int(temperature))°F")
            
            return RouteWeatherPoint(
                coordinate: coordinate,
                locationName: "Point \(index + 1)",
                weatherCondition: "\(condition) • \(Int(temperature))°F",
                hasWarning: hasWarning,
                warningDescription: hasWarning ? "⚠️ Hazard: \(condition)" : nil
            )
        } catch {
            print("❌ Weather fetch failed for point \(index + 1): \(error.localizedDescription)")
            return RouteWeatherPoint(
                coordinate: coordinate,
                locationName: "Point \(index + 1)",
                weatherCondition: "Error fetching weather",
                hasWarning: true,
                warningDescription: "⚠️ Network error: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject private var viewModel = RouteWeatherViewModel()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Input Fields
                VStack(spacing: 15) {
                    TextField("Start Location (e.g., San Marcos, TX)", text: $viewModel.startLocation)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                    
                    TextField("Destination (e.g., Austin, TX)", text: $viewModel.endLocation)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                    
                    Button(action: {
                        Task {
                            await viewModel.findRouteAndWeather()
                        }
                    }) {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Check Route Weather")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(viewModel.isLoading)
                }
                .padding()
                
                // Error Message
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                // Map View - Cross-platform compatible
                if viewModel.route != nil {
                    #if os(iOS)
                    Map(coordinateRegion: $viewModel.mapRegion, annotationItems: viewModel.weatherPoints) { point in
                        MapAnnotation(coordinate: point.coordinate) {
                            VStack {
                                Image(systemName: point.hasWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                    .foregroundColor(point.hasWarning ? .red : .green)
                                    .font(.title2)
                                    .background(Circle().fill(.white).frame(width: 30, height: 30))
                            }
                        }
                    }
                    .frame(height: 300)
                    .cornerRadius(15)
                    .padding(.horizontal)
                    #else
                    // macOS uses the newer Map API
                    Map(position: .constant(.region(viewModel.mapRegion))) {
                        ForEach(viewModel.weatherPoints) { point in
                            Annotation(point.locationName, coordinate: point.coordinate) {
                                VStack {
                                    Image(systemName: point.hasWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                        .foregroundColor(point.hasWarning ? .red : .green)
                                        .font(.title2)
                                        .background(Circle().fill(.white).frame(width: 30, height: 30))
                                }
                            }
                        }
                    }
                    .frame(height: 300)
                    .cornerRadius(15)
                    .padding(.horizontal)
                    #endif
                }
                
                // Weather Points List
                if !viewModel.weatherPoints.isEmpty {
                    ScrollView {
                        VStack(spacing: 12) {
                            Text("Weather Along Route")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            ForEach(viewModel.weatherPoints) { point in
                                HStack {
                                    Image(systemName: point.hasWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                        .foregroundColor(point.hasWarning ? .red : .green)
                                    
                                    VStack(alignment: .leading) {
                                        Text(point.locationName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(point.weatherCondition)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if let warning = point.warningDescription {
                                            Text(warning)
                                                .font(.caption2)
                                                .foregroundColor(.red)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(point.hasWarning ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                                .cornerRadius(10)
                            }
                        }
                        .padding()
                    }
                }
                
                Spacer()
            }
            .navigationTitle("RouteGuard Weather")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

#Preview {
    ContentView()
}
