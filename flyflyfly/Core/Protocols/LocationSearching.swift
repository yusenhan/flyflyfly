import Foundation
import Combine
import MapKit

@MainActor
protocol LocationSearching: AnyObject {
    var objectWillChange: ObservableObjectPublisher { get }
    var completions: [MKLocalSearchCompletion] { get set }
    var completerError: String? { get }
    func updateQuery(_ query: String, region: MKCoordinateRegion?)
    func clearSuggestions()
    func search(for query: String, region: MKCoordinateRegion?) async throws -> [MKMapItem]
    func search(for completion: MKLocalSearchCompletion, region: MKCoordinateRegion?) async throws -> [MKMapItem]
}
