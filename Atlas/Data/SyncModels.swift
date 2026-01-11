import Foundation
import SwiftData

@Model
final class SyncOutboxItem {
    @Attribute(.unique) var id: UUID
    var table: String
    var operation: String // "upsert" | "delete"
    var payloadJSON: String
    var createdAt: Date
    var retryCount: Int
    var lastError: String?

    init(
        id: UUID = UUID(),
        table: String,
        operation: String,
        payloadJSON: String,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.table = table
        self.operation = operation
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastError = lastError
    }
}
