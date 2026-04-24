import SwiftUI
import MapKit

// A lightweight wrapper to host map-related content.
// Updated for macOS 13 compatibility using MKCoordinateRegion.
public struct MapContentView<Content: View>: View {
    @Binding public var region: MKCoordinateRegion
    public let content: Content

    public init(region: Binding<MKCoordinateRegion>, @ViewBuilder content: () -> Content) {
        self._region = region
        self.content = content()
    }

    public var body: some View {
        content
    }
}
