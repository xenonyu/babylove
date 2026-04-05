import Foundation
import SwiftUI

struct Baby: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var birthDate: Date
    var gender: Gender
    var photoData: Data?

    enum Gender: String, Codable, CaseIterable {
        case boy, girl, other

        var displayName: String {
            switch self {
            case .boy:   return NSLocalizedString("Boy", comment: "")
            case .girl:  return NSLocalizedString("Girl", comment: "")
            case .other: return NSLocalizedString("Other", comment: "")
            }
        }

        var icon: String {
            switch self {
            case .boy:   return "👦"
            case .girl:  return "👧"
            case .other: return "🧒"
            }
        }

        var color: String {
            switch self {
            case .boy:   return "#7EC8EA"
            case .girl:  return "#EAAEB3"
            case .other: return "#B3AAEA"
            }
        }
    }

    // MARK: - Age Helpers

    /// Primary age components (year, month, remaining days).
    /// NOTE: `.weekOfYear` is intentionally excluded — including it causes
    /// `.day` to return only the remainder after whole weeks are subtracted,
    /// which makes the displayed day count wrong for babies older than 1 month.
    var ageComponents: DateComponents {
        Calendar.current.dateComponents([.year, .month, .day], from: birthDate, to: Date())
    }

    var ageText: String {
        let c = ageComponents
        let yr = c.year ?? 0
        let mo = c.month ?? 0
        let dy = c.day ?? 0

        if yr > 0 {
            return mo > 0 ? "\(yr)y \(mo)m" : "\(yr) year\(yr > 1 ? "s" : "")"
        } else if mo > 0 {
            return dy > 0 ? "\(mo)m \(dy)d" : "\(mo) month\(mo > 1 ? "s" : "")"
        } else if dy >= 7 {
            // For babies under 1 month, show weeks (computed from total days)
            let wk = dy / 7
            let remDays = dy % 7
            if remDays > 0 {
                return "\(wk) week\(wk > 1 ? "s" : "") \(remDays)d"
            }
            return "\(wk) week\(wk > 1 ? "s" : "")"
        } else {
            return "\(dy) day\(dy != 1 ? "s" : "")"
        }
    }

    var ageInDays: Int {
        Calendar.current.dateComponents([.day], from: birthDate, to: Date()).day ?? 0
    }

    var ageInMonths: Int {
        let c = Calendar.current.dateComponents([.month], from: birthDate, to: Date())
        return c.month ?? 0
    }
}
