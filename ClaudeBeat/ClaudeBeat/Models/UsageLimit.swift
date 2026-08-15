import Foundation

/// One entry of the usage endpoint's `limits` array.
///
/// This array superseded the per-model `seven_day_*` fields, which the API now sends as
/// null. `scope.surface` is deliberately not decoded: it has only ever been observed as
/// null, so its real type is unknown, and declaring the wrong one would drop the entry.
struct UsageLimit: Decodable, Sendable {
    let kind: String
    let percent: Double
    let resetsAt: Date?
    let scope: LimitScope?

    enum CodingKeys: String, CodingKey {
        case kind
        case percent
        case resetsAt = "resets_at"
        case scope
    }

    init(
        kind: String,
        percent: Double,
        resetsAt: Date? = nil,
        scope: LimitScope? = nil
    ) {
        self.kind = kind
        self.percent = percent
        self.resetsAt = resetsAt
        self.scope = scope
    }

    // `kind` is the one required field: an entry without it cannot be routed, so letting
    // the decode throw lets LossyArray drop just that element.
    //
    // Every other field degrades instead of throwing: `decodeIfPresent` alone only
    // covers a missing key or JSON null, but a *type* mismatch still throws, and inside
    // LossyArray a throw drops the whole entry. `try?` around each decodeIfPresent turns
    // that throw into nil too, at the cost of a double optional (T??) that we flatten by
    // hand — `?? nil` collapses it to T? without silently coercing a real nil-vs-0
    // ambiguity, then `?? 0` supplies the field's own default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        let decodedPercent = (try? container.decodeIfPresent(Double.self, forKey: .percent)) ?? nil
        percent = decodedPercent ?? 0
        resetsAt = (try? container.decodeIfPresent(Date.self, forKey: .resetsAt)) ?? nil
        scope = (try? container.decodeIfPresent(LimitScope.self, forKey: .scope)) ?? nil
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
