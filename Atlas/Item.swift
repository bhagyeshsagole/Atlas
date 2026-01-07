//
//  Item.swift
//  Atlas
//
//  What this file is:
//  - Simple sample SwiftData model that stores a timestamp (unused placeholder).
//
//  Where it’s used:
//  - Included in the project template; not referenced by current screens.
//
//  Called from:
//  - Only present in previews/tests if you choose to use it; listed in `AtlasApp.modelTypes`.
//
//  Key concepts:
//  - Demonstrates `@Model` usage for SwiftData with a single stored property.
//
//  Safe to change:
//  - Remove or repurpose for your own model once you update `modelTypes` in `AtlasApp`.
//
//  NOT safe to change:
//  - Leaving it in `modelTypes` while deleting the class will break SwiftData schema compilation.
//
//  Common bugs / gotchas:
//  - If you keep it unused, it still takes schema slots; remove from `modelTypes` when deleting.
//
//  DEV MAP:
//  - See: DEV_MAP.md → A) App Entry + Navigation
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
