import Foundation

// MARK: - Feed Type
enum FeedType: String, CaseIterable, Codable {
    case breast  = "breast"
    case formula = "formula"
    case solid   = "solid"
    case pump    = "pump"

    var displayName: String {
        switch self {
        case .breast:  return "Breast"
        case .formula: return "Formula"
        case .solid:   return "Solid"
        case .pump:    return "Pumped"
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
        case .left:  return "Left"
        case .right: return "Right"
        case .both:  return "Both"
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
        case .wet:   return "Wet"
        case .dirty: return "Dirty"
        case .both:  return "Both"
        case .dry:   return "Dry"
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
        case .social:    return "Social"
        case .motor:     return "Motor"
        case .language:  return "Language"
        case .cognitive: return "Cognitive"
        case .health:    return "Health"
        case .custom:    return "Custom"
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
        case .crib:     return "Crib"
        case .bassinet: return "Bassinet"
        case .bed:      return "Parent's Bed"
        case .stroller: return "Stroller"
        case .carrier:  return "Carrier"
        case .other:    return "Other"
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
