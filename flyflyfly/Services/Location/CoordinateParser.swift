import CoreLocation
import Foundation

enum CoordinateParser {
    private static let coordinatePattern = #"^(?i)(-?\d{1,3}(?:\.\d+)?)\s*[,，\s]\s*(-?\d{1,3}(?:\.\d+)?)$"#

    private static let coordinateRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: coordinatePattern)
    }()

    static func isCoordinateLike(_ text: String) -> Bool {
        match(in: text) != nil
    }

    static func parse(_ text: String) -> CLLocationCoordinate2D? {
        guard let match = match(in: text) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let nsText = trimmed as NSString
        let latString = nsText.substring(with: match.range(at: 1))
        let lonString = nsText.substring(with: match.range(at: 2))

        guard let latitude = Double(latString), let longitude = Double(lonString) else {
            return nil
        }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private static func match(in text: String) -> NSTextCheckingResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let coordinateRegex else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return coordinateRegex.firstMatch(in: trimmed, range: range)
    }
}
