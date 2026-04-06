import Foundation

// MARK: - Feed Type
enum FeedType: String, CaseIterable, Codable {
    case breast  = "breast"
    case formula = "formula"
    case solid   = "solid"
    case pump    = "pump"

    var displayName: String {
        switch self {
        case .breast:  return String(localized: "feedType.breast")
        case .formula: return String(localized: "feedType.formula")
        case .solid:   return String(localized: "feedType.solid")
        case .pump:    return String(localized: "feedType.pump")
        }
    }

    var icon: String {
        switch self {
        case .breast:  return "drop.fill"
        case .formula: return "cross.vial.fill"
        case .solid:   return "fork.knife"
        case .pump:    return "drop.halffull"
        }
    }
}

// MARK: - Breast Side
enum BreastSide: String, CaseIterable, Codable {
    case left  = "left"
    case right = "right"
    case both  = "both"

    var displayName: String {
        switch self {
        case .left:  return String(localized: "breastSide.left")
        case .right: return String(localized: "breastSide.right")
        case .both:  return String(localized: "breastSide.both")
        }
    }
}

// MARK: - Diaper Type
enum DiaperType: String, CaseIterable, Codable {
    case wet   = "wet"
    case dirty = "dirty"
    case both  = "both"
    case dry   = "dry"

    var displayName: String {
        switch self {
        case .wet:   return String(localized: "diaperType.wet")
        case .dirty: return String(localized: "diaperType.dirty")
        case .both:  return String(localized: "diaperType.both")
        case .dry:   return String(localized: "diaperType.dry")
        }
    }

    var icon: String {
        switch self {
        case .wet:   return "💧"
        case .dirty: return "💩"
        case .both:  return "💧💩"
        case .dry:   return "✓"
        }
    }
}

// MARK: - Milestone Category
enum MilestoneCategory: String, CaseIterable, Codable {
    case social    = "social"
    case motor     = "motor"
    case language  = "language"
    case cognitive = "cognitive"
    case health    = "health"
    case custom    = "custom"

    var displayName: String {
        switch self {
        case .social:    return String(localized: "milestone.social")
        case .motor:     return String(localized: "milestone.motor")
        case .language:  return String(localized: "milestone.language")
        case .cognitive: return String(localized: "milestone.cognitive")
        case .health:    return String(localized: "milestone.health")
        case .custom:    return String(localized: "milestone.custom")
        }
    }

    var icon: String {
        switch self {
        case .social:    return "heart.fill"
        case .motor:     return "figure.walk"
        case .language:  return "bubble.left.fill"
        case .cognitive: return "brain.head.profile"
        case .health:    return "cross.fill"
        case .custom:    return "star.fill"
        }
    }

    var color: String {
        switch self {
        case .social:    return "#FF7B6B"
        case .motor:     return "#4BAEE8"
        case .language:  return "#9B8EC4"
        case .cognitive: return "#F5A623"
        case .health:    return "#55C189"
        case .custom:    return "#7EC8C8"
        }
    }
}

// MARK: - Preset Milestones
struct PresetMilestone: Identifiable {
    let id = UUID()
    let titleKey: String
    let category: MilestoneCategory
    let ageRangeMonths: String  // e.g. "1-3" for display

    /// Localized title for display
    var title: String { String(localized: String.LocalizationValue(titleKey)) }

    /// Parsed minimum age in months from ageRangeMonths string
    var ageMin: Int {
        let parts = ageRangeMonths.split(separator: "-")
        return Int(parts.first ?? "0") ?? 0
    }

    /// Parsed maximum age in months from ageRangeMonths string
    var ageMax: Int {
        let parts = ageRangeMonths.split(separator: "-")
        return Int(parts.last ?? "24") ?? 24
    }

    /// Age relevance relative to the baby's current age
    enum AgeRelevance: Int, Comparable {
        case current = 0   // Baby is within the milestone's age range
        case upcoming = 1  // Baby hasn't reached this age range yet
        case past = 2      // Baby has passed this age range

        static func < (lhs: AgeRelevance, rhs: AgeRelevance) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Determine how relevant this milestone is for a baby of the given age
    func relevance(forBabyAgeMonths age: Int) -> AgeRelevance {
        if age >= ageMin && age <= ageMax { return .current }
        if age < ageMin { return .upcoming }
        return .past
    }

    static let all: [PresetMilestone] = [
        // Social
        PresetMilestone(titleKey: "preset.firstSmile", category: .social, ageRangeMonths: "1-2"),
        PresetMilestone(titleKey: "preset.laughedOutLoud", category: .social, ageRangeMonths: "3-4"),
        PresetMilestone(titleKey: "preset.strangerAnxiety", category: .social, ageRangeMonths: "6-9"),
        PresetMilestone(titleKey: "preset.wavedByeBye", category: .social, ageRangeMonths: "9-12"),
        PresetMilestone(titleKey: "preset.playedPeekaboo", category: .social, ageRangeMonths: "6-9"),
        // Motor
        PresetMilestone(titleKey: "preset.heldHeadUp", category: .motor, ageRangeMonths: "1-3"),
        PresetMilestone(titleKey: "preset.rolledOver", category: .motor, ageRangeMonths: "3-5"),
        PresetMilestone(titleKey: "preset.satWithoutSupport", category: .motor, ageRangeMonths: "5-7"),
        PresetMilestone(titleKey: "preset.crawled", category: .motor, ageRangeMonths: "6-10"),
        PresetMilestone(titleKey: "preset.pulledToStand", category: .motor, ageRangeMonths: "8-12"),
        PresetMilestone(titleKey: "preset.firstSteps", category: .motor, ageRangeMonths: "9-15"),
        PresetMilestone(titleKey: "preset.graspedToy", category: .motor, ageRangeMonths: "3-5"),
        // Language
        PresetMilestone(titleKey: "preset.firstCoo", category: .language, ageRangeMonths: "1-3"),
        PresetMilestone(titleKey: "preset.babbled", category: .language, ageRangeMonths: "4-6"),
        PresetMilestone(titleKey: "preset.saidFirstWord", category: .language, ageRangeMonths: "10-14"),
        PresetMilestone(titleKey: "preset.respondedToName", category: .language, ageRangeMonths: "5-7"),
        // Cognitive
        PresetMilestone(titleKey: "preset.followedObject", category: .cognitive, ageRangeMonths: "1-3"),
        PresetMilestone(titleKey: "preset.foundHiddenToy", category: .cognitive, ageRangeMonths: "6-9"),
        PresetMilestone(titleKey: "preset.pointedAtObjects", category: .cognitive, ageRangeMonths: "9-12"),
        PresetMilestone(titleKey: "preset.stackedBlocks", category: .cognitive, ageRangeMonths: "12-18"),
        // Health
        PresetMilestone(titleKey: "preset.firstTooth", category: .health, ageRangeMonths: "4-10"),
        PresetMilestone(titleKey: "preset.sleptThroughNight", category: .health, ageRangeMonths: "3-6"),
        PresetMilestone(titleKey: "preset.startedSolidFoods", category: .health, ageRangeMonths: "4-6"),
        PresetMilestone(titleKey: "preset.firstHaircut", category: .health, ageRangeMonths: "6-12"),
    ]

    static func forCategory(_ category: MilestoneCategory) -> [PresetMilestone] {
        all.filter { $0.category == category }
    }

    /// Returns milestones for a category, sorted by age relevance:
    /// current (in range) first, then upcoming, then past.
    /// Within each group, sorted by ageMin ascending.
    static func forCategory(_ category: MilestoneCategory, babyAgeMonths: Int) -> [PresetMilestone] {
        all.filter { $0.category == category }
            .sorted { a, b in
                let ra = a.relevance(forBabyAgeMonths: babyAgeMonths)
                let rb = b.relevance(forBabyAgeMonths: babyAgeMonths)
                if ra != rb { return ra < rb }
                return a.ageMin < b.ageMin
            }
    }
}

// MARK: - Sleep Location
enum SleepLocation: String, CaseIterable, Codable {
    case crib    = "crib"
    case bassinet = "bassinet"
    case bed     = "bed"
    case stroller = "stroller"
    case carrier = "carrier"
    case other   = "other"

    var displayName: String {
        switch self {
        case .crib:     return String(localized: "sleep.crib")
        case .bassinet: return String(localized: "sleep.bassinet")
        case .bed:      return String(localized: "sleep.bed")
        case .stroller: return String(localized: "sleep.stroller")
        case .carrier:  return String(localized: "sleep.carrier")
        case .other:    return String(localized: "sleep.other")
        }
    }

    var icon: String {
        switch self {
        case .crib:     return "🛏"
        case .bassinet: return "🧺"
        case .bed:      return "🛌"
        case .stroller: return "🛒"
        case .carrier:  return "🫂"
        case .other:    return "💤"
        }
    }
}

// MARK: - Duration Formatting

/// Human-readable duration from raw minutes.
/// Returns "Xh Ym" for ≥60 min, "X min" otherwise.
/// Compact variant (for tight layouts): "Xh Ym" / "Xm".
enum DurationFormat {
    /// Standard: "45 min", "1h 30m", "2h"
    static func standard(_ minutes: Int16) -> String {
        let m = Int(minutes)
        guard m >= 60 else { return "\(m) min" }
        let h = m / 60, rem = m % 60
        return rem > 0 ? "\(h)h \(rem)m" : "\(h)h"
    }

    /// Compact: "45m", "1h 30m", "2h"
    static func compact(_ minutes: Int16) -> String {
        let m = Int(minutes)
        guard m >= 60 else { return "\(m)m" }
        let h = m / 60, rem = m % 60
        return rem > 0 ? "\(h)h \(rem)m" : "\(h)h"
    }
}
