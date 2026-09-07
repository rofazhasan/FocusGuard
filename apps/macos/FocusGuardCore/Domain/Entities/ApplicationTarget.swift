import Foundation

public struct ApplicationTarget: Identifiable, Codable, Equatable {
    public let id: UUID
    public let bundleIdentifier: String
    public let displayName: String
    public let executablePath: String?
    public let iconMetadata: String?

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        executablePath: String? = nil,
        iconMetadata: String? = nil
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.displayName = displayName
        self.executablePath = executablePath
        self.iconMetadata = iconMetadata
    }
}
