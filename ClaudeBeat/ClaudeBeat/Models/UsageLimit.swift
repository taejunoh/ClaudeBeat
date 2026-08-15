import Foundation

/// One entry of the usage endpoint's `limits` array.
///
/// This array superseded the per-model `seven_day_*` fields, which the API now sends as
/// null. `scope.surface` is deliberately not decoded: it has only ever been observed as
/// null, so its real type is unknown, and declaring the wrong one would drop the entry.
struct UsageLimit: Decodable, Sendable {
    let kind: String
    let percent: Double
    let severity: String?
    let resetsAt: Date?
    let scope: LimitScope?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case kind
        case percent
        case severity
        case resetsAt = "resets_at"
        case scope
        case isActive = "is_active"
    }

    init(
        kind: String,
        percent: Double,
        severity: String? = nil,
        resetsAt: Date? = nil,
        scope: LimitScope? = nil,
        isActive: Bool = false
    ) {
        self.kind = kind
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
        self.scope = scope
        self.isActive = isActive
    }

    // `kind` is the one required field: an entry without it cannot be routed, so letting
    // the decode throw lets LossyArray drop just that element.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        percent = try container.decodeIfPresent(Double.self, forKey: .percent) ?? 0
        severity = try container.decodeIfPresent(String.self, forKey: .severity)
        resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        scope = try container.decodeIfPresent(LimitScope.self, forKey: .scope)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
    }
}

struct LimitScope: Decodable, Sendable {
    let model: LimitModel?

    init(model: LimitModel?) {
        self.model = model
    }
}

struct LimitModel: Decodable, Sendable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }

    init(displayName: String?) {
        self.displayName = displayName
    }
}
