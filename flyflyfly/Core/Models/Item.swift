//
//  Item.swift
//  flyflyfly

import Foundation

// @Model // Removed SwiftData usage to support macOS 13.0
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
