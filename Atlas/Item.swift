//
//  Item.swift
//  Atlas
//
//  Overview: Sample SwiftData item storing a timestamp.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
