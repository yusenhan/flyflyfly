//
//  Item.swift
//  flyflyfly
//
//  Created by Hanson Han on 3/2/26.
//

import Foundation

// @Model // Removed SwiftData usage to support macOS 13.0
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
