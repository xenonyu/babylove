import Foundation

// MARK: - WHO Child Growth Standards (0–24 months)
// Source: WHO Multicentre Growth Reference Study (2006)
// Percentiles: P3, P15, P50, P85, P97

/// A single row of WHO percentile data at a given month.
struct WHOPercentileRow {
    let month: Int
    let p3: Double
    let p15: Double
    let p50: Double
    let p85: Double
    let p97: Double
}

/// Container for WHO growth standard data for one metric + gender combination.
struct WHOGrowthTable {
    let rows: [WHOPercentileRow]

    /// Interpolate a percentile value at a fractional month age.
    func value(atMonth age: Double, percentile: WHOPercentile) -> Double? {
        guard !rows.isEmpty else { return nil }
        let clamped = max(0, min(Double(rows.last!.month), age))
        let lower = Int(clamped)
        let upper = min(lower + 1, rows.last!.month)
        let frac = clamped - Double(lower)

        guard let lo = rows.first(where: { $0.month == lower }),
              let hi = rows.first(where: { $0.month == upper }) else { return nil }

        let loVal = lo.value(for: percentile)
        let hiVal = hi.value(for: percentile)
        return loVal + (hiVal - loVal) * frac
    }

    /// Age range covered.
    var maxMonth: Int { rows.last?.month ?? 24 }
}

enum WHOPercentile: CaseIterable {
    case p3, p15, p50, p85, p97

    var label: String {
        switch self {
        case .p3:  return "3rd"
        case .p15: return "15th"
        case .p50: return "50th"
        case .p85: return "85th"
        case .p97: return "97th"
        }
    }
}

extension WHOPercentileRow {
    func value(for p: WHOPercentile) -> Double {
        switch p {
        case .p3:  return p3
        case .p15: return p15
        case .p50: return p50
        case .p85: return p85
        case .p97: return p97
        }
    }
}

// MARK: - WHO Data Provider

enum WHOGrowthData {
    /// Returns the appropriate table for the given metric and gender.
    static func table(metric: String, isBoy: Bool) -> WHOGrowthTable {
        switch metric {
        case "weight": return isBoy ? boysWeight : girlsWeight
        case "height": return isBoy ? boysHeight : girlsHeight
        case "head":   return isBoy ? boysHead   : girlsHead
        default:       return isBoy ? boysWeight : girlsWeight
        }
    }

    // MARK: - Boys Weight (kg)
    static let boysWeight = WHOGrowthTable(rows: [
        WHOPercentileRow(month: 0,  p3: 2.5, p15: 2.9, p50: 3.3, p85: 3.9, p97: 4.4),
        WHOPercentileRow(month: 1,  p3: 3.4, p15: 3.9, p50: 4.5, p85: 5.1, p97: 5.8),
        WHOPercentileRow(month: 2,  p3: 4.3, p15: 4.9, p50: 5.6, p85: 6.3, p97: 7.1),
        WHOPercentileRow(month: 3,  p3: 5.0, p15: 5.7, p50: 6.4, p85: 7.2, p97: 7.9),
        WHOPercentileRow(month: 4,  p3: 5.6, p15: 6.2, p50: 7.0, p85: 7.8, p97: 8.6),
        WHOPercentileRow(month: 5,  p3: 6.0, p15: 6.7, p50: 7.5, p85: 8.4, p97: 9.2),
        WHOPercentileRow(month: 6,  p3: 6.4, p15: 7.1, p50: 7.9, p85: 8.8, p97: 9.7),
        WHOPercentileRow(month: 7,  p3: 6.7, p15: 7.4, p50: 8.3, p85: 9.2, p97: 10.2),
        WHOPercentileRow(month: 8,  p3: 6.9, p15: 7.7, p50: 8.6, p85: 9.6, p97: 10.5),
        WHOPercentileRow(month: 9,  p3: 7.1, p15: 7.9, p50: 8.9, p85: 9.9, p97: 10.9),
        WHOPercentileRow(month: 10, p3: 7.4, p15: 8.1, p50: 9.2, p85: 10.2, p97: 11.2),
        WHOPercentileRow(month: 11, p3: 7.6, p15: 8.4, p50: 9.4, p85: 10.5, p97: 11.5),
        WHOPercentileRow(month: 12, p3: 7.7, p15: 8.6, p50: 9.6, p85: 10.8, p97: 11.8),
        WHOPercentileRow(month: 13, p3: 7.9, p15: 8.8, p50: 9.9, p85: 11.0, p97: 12.1),
        WHOPercentileRow(month: 14, p3: 8.1, p15: 9.0, p50: 10.1, p85: 11.3, p97: 12.4),
        WHOPercentileRow(month: 15, p3: 8.3, p15: 9.2, p50: 10.3, p85: 11.5, p97: 12.7),
        WHOPercentileRow(month: 16, p3: 8.4, p15: 9.4, p50: 10.5, p85: 11.7, p97: 12.9),
        WHOPercentileRow(month: 17, p3: 8.6, p15: 9.6, p50: 10.7, p85: 12.0, p97: 13.2),
        WHOPercentileRow(month: 18, p3: 8.8, p15: 9.8, p50: 10.9, p85: 12.2, p97: 13.4),
        WHOPercentileRow(month: 19, p3: 8.9, p15: 10.0, p50: 11.1, p85: 12.4, p97: 13.7),
        WHOPercentileRow(month: 20, p3: 9.1, p15: 10.1, p50: 11.3, p85: 12.7, p97: 13.9),
        WHOPercentileRow(month: 21, p3: 9.2, p15: 10.3, p50: 11.5, p85: 12.9, p97: 14.2),
        WHOPercentileRow(month: 22, p3: 9.4, p15: 10.5, p50: 11.8, p85: 13.1, p97: 14.4),
        WHOPercentileRow(month: 23, p3: 9.5, p15: 10.7, p50: 12.0, p85: 13.3, p97: 14.7),
        WHOPercentileRow(month: 24, p3: 9.7, p15: 10.8, p50: 12.2, p85: 13.6, p97: 14.9),
    ])

    // MARK: - Girls Weight (kg)
    static let girlsWeight = WHOGrowthTable(rows: [
        WHOPercentileRow(month: 0,  p3: 2.4, p15: 2.8, p50: 3.2, p85: 3.7, p97: 4.2),
        WHOPercentileRow(month: 1,  p3: 3.2, p15: 3.6, p50: 4.2, p85: 4.8, p97: 5.5),
        WHOPercentileRow(month: 2,  p3: 3.9, p15: 4.5, p50: 5.1, p85: 5.8, p97: 6.6),
        WHOPercentileRow(month: 3,  p3: 4.5, p15: 5.2, p50: 5.8, p85: 6.6, p97: 7.5),
        WHOPercentileRow(month: 4,  p3: 5.0, p15: 5.7, p50: 6.4, p85: 7.3, p97: 8.2),
        WHOPercentileRow(month: 5,  p3: 5.4, p15: 6.1, p50: 6.9, p85: 7.8, p97: 8.8),
        WHOPercentileRow(month: 6,  p3: 5.7, p15: 6.5, p50: 7.3, p85: 8.2, p97: 9.3),
        WHOPercentileRow(month: 7,  p3: 6.0, p15: 6.8, p50: 7.6, p85: 8.6, p97: 9.8),
        WHOPercentileRow(month: 8,  p3: 6.3, p15: 7.0, p50: 7.9, p85: 9.0, p97: 10.2),
        WHOPercentileRow(month: 9,  p3: 6.5, p15: 7.3, p50: 8.2, p85: 9.3, p97: 10.5),
        WHOPercentileRow(month: 10, p3: 6.7, p15: 7.5, p50: 8.5, p85: 9.6, p97: 10.9),
        WHOPercentileRow(month: 11, p3: 6.9, p15: 7.7, p50: 8.7, p85: 9.9, p97: 11.2),
        WHOPercentileRow(month: 12, p3: 7.0, p15: 7.9, p50: 8.9, p85: 10.1, p97: 11.5),
        WHOPercentileRow(month: 13, p3: 7.2, p15: 8.1, p50: 9.2, p85: 10.4, p97: 11.8),
        WHOPercentileRow(month: 14, p3: 7.4, p15: 8.3, p50: 9.4, p85: 10.6, p97: 12.1),
        WHOPercentileRow(month: 15, p3: 7.6, p15: 8.5, p50: 9.6, p85: 10.9, p97: 12.4),
        WHOPercentileRow(month: 16, p3: 7.7, p15: 8.7, p50: 9.8, p85: 11.1, p97: 12.6),
        WHOPercentileRow(month: 17, p3: 7.9, p15: 8.9, p50: 10.0, p85: 11.4, p97: 12.9),
        WHOPercentileRow(month: 18, p3: 8.1, p15: 9.1, p50: 10.2, p85: 11.6, p97: 13.2),
        WHOPercentileRow(month: 19, p3: 8.2, p15: 9.2, p50: 10.4, p85: 11.8, p97: 13.5),
        WHOPercentileRow(month: 20, p3: 8.4, p15: 9.4, p50: 10.6, p85: 12.1, p97: 13.7),
        WHOPercentileRow(month: 21, p3: 8.6, p15: 9.6, p50: 10.9, p85: 12.3, p97: 14.0),
        WHOPercentileRow(month: 22, p3: 8.7, p15: 9.8, p50: 11.1, p85: 12.5, p97: 14.3),
        WHOPercentileRow(month: 23, p3: 8.9, p15: 10.0, p50: 11.3, p85: 12.8, p97: 14.6),
        WHOPercentileRow(month: 24, p3: 9.0, p15: 10.2, p50: 11.5, p85: 13.0, p97: 14.8),
    ])

    // MARK: - Boys Height (cm)
    static let boysHeight = WHOGrowthTable(rows: [
        WHOPercentileRow(month: 0,  p3: 46.1, p15: 47.9, p50: 49.9, p85: 51.8, p97: 53.7),
        WHOPercentileRow(month: 1,  p3: 50.8, p15: 52.5, p50: 54.7, p85: 56.7, p97: 58.6),
        WHOPercentileRow(month: 2,  p3: 53.7, p15: 55.7, p50: 58.4, p85: 60.3, p97: 62.4),
        WHOPercentileRow(month: 3,  p3: 56.7, p15: 58.5, p50: 61.4, p85: 63.2, p97: 65.5),
        WHOPercentileRow(month: 4,  p3: 59.0, p15: 60.7, p50: 63.9, p85: 65.6, p97: 68.0),
        WHOPercentileRow(month: 5,  p3: 61.0, p15: 62.8, p50: 65.9, p85: 67.9, p97: 70.1),
        WHOPercentileRow(month: 6,  p3: 63.0, p15: 64.4, p50: 67.6, p85: 69.8, p97: 71.9),
        WHOPercentileRow(month: 7,  p3: 64.8, p15: 66.3, p50: 69.2, p85: 71.3, p97: 73.5),
        WHOPercentileRow(month: 8,  p3: 66.2, p15: 67.8, p50: 70.6, p85: 73.0, p97: 75.0),
        WHOPercentileRow(month: 9,  p3: 67.5, p15: 69.2, p50: 72.0, p85: 74.2, p97: 76.5),
        WHOPercentileRow(month: 10, p3: 68.7, p15: 70.3, p50: 73.3, p85: 75.6, p97: 77.9),
        WHOPercentileRow(month: 11, p3: 69.9, p15: 71.5, p50: 74.5, p85: 76.9, p97: 79.2),
        WHOPercentileRow(month: 12, p3: 71.0, p15: 72.6, p50: 75.7, p85: 78.1, p97: 80.5),
        WHOPercentileRow(month: 13, p3: 72.1, p15: 73.6, p50: 76.9, p85: 79.3, p97: 81.8),
        WHOPercentileRow(month: 14, p3: 73.1, p15: 74.7, p50: 78.0, p85: 80.5, p97: 83.0),
        WHOPercentileRow(month: 15, p3: 74.1, p15: 75.8, p50: 79.1, p85: 81.7, p97: 84.2),
        WHOPercentileRow(month: 16, p3: 75.0, p15: 76.8, p50: 80.2, p85: 82.8, p97: 85.4),
        WHOPercentileRow(month: 17, p3: 76.0, p15: 77.8, p50: 81.2, p85: 83.9, p97: 86.5),
        WHOPercentileRow(month: 18, p3: 76.9, p15: 78.8, p50: 82.3, p85: 85.0, p97: 87.7),
        WHOPercentileRow(month: 19, p3: 77.7, p15: 79.7, p50: 83.2, p85: 86.0, p97: 88.8),
        WHOPercentileRow(month: 20, p3: 78.6, p15: 80.6, p50: 84.2, p85: 87.0, p97: 89.8),
        WHOPercentileRow(month: 21, p3: 79.4, p15: 81.5, p50: 85.1, p85: 88.0, p97: 90.9),
        WHOPercentileRow(month: 22, p3: 80.2, p15: 82.4, p50: 86.0, p85: 89.0, p97: 91.9),
        WHOPercentileRow(month: 23, p3: 81.0, p15: 83.3, p50: 86.9, p85: 89.9, p97: 92.9),
        WHOPercentileRow(month: 24, p3: 81.7, p15: 84.1, p50: 87.8, p85: 90.9, p97: 93.9),
    ])

    // MARK: - Girls Height (cm)
    static let girlsHeight = WHOGrowthTable(rows: [
        WHOPercentileRow(month: 0,  p3: 45.4, p15: 47.2, p50: 49.1, p85: 51.0, p97: 52.9),
        WHOPercentileRow(month: 1,  p3: 49.8, p15: 51.5, p50: 53.7, p85: 55.6, p97: 57.6),
        WHOPercentileRow(month: 2,  p3: 53.0, p15: 54.7, p50: 57.1, p85: 59.1, p97: 61.1),
        WHOPercentileRow(month: 3,  p3: 55.6, p15: 57.4, p50: 59.8, p85: 62.0, p97: 64.0),
        WHOPercentileRow(month: 4,  p3: 57.8, p15: 59.6, p50: 62.1, p85: 64.3, p97: 66.4),
        WHOPercentileRow(month: 5,  p3: 59.6, p15: 61.5, p50: 64.0, p85: 66.2, p97: 68.5),
        WHOPercentileRow(month: 6,  p3: 61.2, p15: 63.0, p50: 65.7, p85: 68.0, p97: 70.3),
        WHOPercentileRow(month: 7,  p3: 62.7, p15: 64.5, p50: 67.3, p85: 69.6, p97: 72.0),
        WHOPercentileRow(month: 8,  p3: 64.0, p15: 65.8, p50: 68.7, p85: 71.1, p97: 73.5),
        WHOPercentileRow(month: 9,  p3: 65.3, p15: 67.1, p50: 70.1, p85: 72.6, p97: 75.0),
        WHOPercentileRow(month: 10, p3: 66.5, p15: 68.4, p50: 71.5, p85: 73.9, p97: 76.4),
        WHOPercentileRow(month: 11, p3: 67.7, p15: 69.6, p50: 72.8, p85: 75.3, p97: 77.8),
        WHOPercentileRow(month: 12, p3: 68.9, p15: 70.8, p50: 74.0, p85: 76.6, p97: 79.2),
        WHOPercentileRow(month: 13, p3: 70.0, p15: 71.9, p50: 75.2, p85: 77.8, p97: 80.5),
        WHOPercentileRow(month: 14, p3: 71.0, p15: 73.0, p50: 76.4, p85: 79.1, p97: 81.7),
        WHOPercentileRow(month: 15, p3: 72.0, p15: 74.0, p50: 77.5, p85: 80.2, p97: 83.0),
        WHOPercentileRow(month: 16, p3: 73.0, p15: 75.1, p50: 78.6, p85: 81.4, p97: 84.2),
        WHOPercentileRow(month: 17, p3: 74.0, p15: 76.1, p50: 79.7, p85: 82.5, p97: 85.4),
        WHOPercentileRow(month: 18, p3: 74.9, p15: 77.0, p50: 80.7, p85: 83.6, p97: 86.5),
        WHOPercentileRow(month: 19, p3: 75.8, p15: 78.0, p50: 81.7, p85: 84.7, p97: 87.6),
        WHOPercentileRow(month: 20, p3: 76.7, p15: 78.9, p50: 82.7, p85: 85.7, p97: 88.7),
        WHOPercentileRow(month: 21, p3: 77.5, p15: 79.9, p50: 83.7, p85: 86.7, p97: 89.8),
        WHOPercentileRow(month: 22, p3: 78.4, p15: 80.8, p50: 84.6, p85: 87.7, p97: 90.8),
        WHOPercentileRow(month: 23, p3: 79.2, p15: 81.7, p50: 85.5, p85: 88.7, p97: 91.9),
        WHOPercentileRow(month: 24, p3: 80.0, p15: 82.5, p50: 86.4, p85: 89.6, p97: 92.9),
    ])

    // MARK: - Boys Head Circumference (cm)
    static let boysHead = WHOGrowthTable(rows: [
        WHOPercentileRow(month: 0,  p3: 32.1, p15: 33.2, p50: 34.5, p85: 35.7, p97: 36.9),
        WHOPercentileRow(month: 1,  p3: 34.9, p15: 35.8, p50: 37.3, p85: 38.4, p97: 39.6),
        WHOPercentileRow(month: 2,  p3: 36.8, p15: 37.8, p50: 39.1, p85: 40.3, p97: 41.5),
        WHOPercentileRow(month: 3,  p3: 38.1, p15: 39.1, p50: 40.5, p85: 41.7, p97: 42.9),
        WHOPercentileRow(month: 4,  p3: 39.2, p15: 40.1, p50: 41.6, p85: 42.8, p97: 44.0),
        WHOPercentileRow(month: 5,  p3: 40.1, p15: 40.9, p50: 42.6, p85: 43.6, p97: 44.9),
        WHOPercentileRow(month: 6,  p3: 40.9, p15: 41.7, p50: 43.3, p85: 44.4, p97: 45.8),
        WHOPercentileRow(month: 7,  p3: 41.5, p15: 42.3, p50: 44.0, p85: 45.0, p97: 46.4),
        WHOPercentileRow(month: 8,  p3: 42.0, p15: 42.9, p50: 44.5, p85: 45.6, p97: 47.0),
        WHOPercentileRow(month: 9,  p3: 42.5, p15: 43.3, p50: 45.0, p85: 46.1, p97: 47.4),
        WHOPercentileRow(month: 10, p3: 42.9, p15: 43.7, p50: 45.4, p85: 46.6, p97: 47.9),
        WHOPercentileRow(month: 11, p3: 43.2, p15: 44.1, p50: 45.8, p85: 46.9, p97: 48.3),
        WHOPercentileRow(month: 12, p3: 43.5, p15: 44.4, p50: 46.1, p85: 47.2, p97: 48.6),
        WHOPercentileRow(month: 13, p3: 43.8, p15: 44.6, p50: 46.3, p85: 47.5, p97: 48.8),
        WHOPercentileRow(month: 14, p3: 44.0, p15: 44.9, p50: 46.6, p85: 47.8, p97: 49.1),
        WHOPercentileRow(month: 15, p3: 44.2, p15: 45.1, p50: 46.8, p85: 48.0, p97: 49.3),
        WHOPercentileRow(month: 16, p3: 44.4, p15: 45.3, p50: 47.0, p85: 48.2, p97: 49.5),
        WHOPercentileRow(month: 17, p3: 44.6, p15: 45.5, p50: 47.2, p85: 48.4, p97: 49.7),
        WHOPercentileRow(month: 18, p3: 44.7, p15: 45.7, p50: 47.4, p85: 48.6, p97: 49.9),
        WHOPercentileRow(month: 19, p3: 44.9, p15: 45.8, p50: 47.5, p85: 48.7, p97: 50.0),
        WHOPercentileRow(month: 20, p3: 45.0, p15: 46.0, p50: 47.7, p85: 48.9, p97: 50.2),
        WHOPercentileRow(month: 21, p3: 45.2, p15: 46.1, p50: 47.8, p85: 49.1, p97: 50.4),
        WHOPercentileRow(month: 22, p3: 45.3, p15: 46.3, p50: 48.0, p85: 49.2, p97: 50.5),
        WHOPercentileRow(month: 23, p3: 45.4, p15: 46.4, p50: 48.1, p85: 49.3, p97: 50.7),
        WHOPercentileRow(month: 24, p3: 45.5, p15: 46.5, p50: 48.3, p85: 49.5, p97: 50.8),
    ])

    // MARK: - Girls Head Circumference (cm)
    static let girlsHead = WHOGrowthTable(rows: [
        WHOPercentileRow(month: 0,  p3: 31.5, p15: 32.5, p50: 33.9, p85: 35.1, p97: 36.2),
        WHOPercentileRow(month: 1,  p3: 34.2, p15: 35.0, p50: 36.5, p85: 37.7, p97: 38.9),
        WHOPercentileRow(month: 2,  p3: 35.8, p15: 36.8, p50: 38.3, p85: 39.5, p97: 40.7),
        WHOPercentileRow(month: 3,  p3: 37.1, p15: 38.1, p50: 39.5, p85: 40.8, p97: 42.0),
        WHOPercentileRow(month: 4,  p3: 38.1, p15: 39.1, p50: 40.6, p85: 41.8, p97: 43.0),
        WHOPercentileRow(month: 5,  p3: 38.9, p15: 39.9, p50: 41.5, p85: 42.7, p97: 43.8),
        WHOPercentileRow(month: 6,  p3: 39.6, p15: 40.6, p50: 42.2, p85: 43.4, p97: 44.6),
        WHOPercentileRow(month: 7,  p3: 40.2, p15: 41.2, p50: 42.8, p85: 44.1, p97: 45.3),
        WHOPercentileRow(month: 8,  p3: 40.7, p15: 41.7, p50: 43.4, p85: 44.6, p97: 45.8),
        WHOPercentileRow(month: 9,  p3: 41.2, p15: 42.2, p50: 43.8, p85: 45.1, p97: 46.3),
        WHOPercentileRow(month: 10, p3: 41.5, p15: 42.6, p50: 44.2, p85: 45.5, p97: 46.7),
        WHOPercentileRow(month: 11, p3: 41.9, p15: 42.9, p50: 44.6, p85: 45.9, p97: 47.1),
        WHOPercentileRow(month: 12, p3: 42.2, p15: 43.3, p50: 44.9, p85: 46.3, p97: 47.5),
        WHOPercentileRow(month: 13, p3: 42.4, p15: 43.5, p50: 45.2, p85: 46.5, p97: 47.7),
        WHOPercentileRow(month: 14, p3: 42.7, p15: 43.8, p50: 45.4, p85: 46.8, p97: 48.0),
        WHOPercentileRow(month: 15, p3: 42.9, p15: 44.0, p50: 45.7, p85: 47.0, p97: 48.3),
        WHOPercentileRow(month: 16, p3: 43.1, p15: 44.2, p50: 45.9, p85: 47.2, p97: 48.5),
        WHOPercentileRow(month: 17, p3: 43.3, p15: 44.4, p50: 46.1, p85: 47.5, p97: 48.7),
        WHOPercentileRow(month: 18, p3: 43.5, p15: 44.6, p50: 46.2, p85: 47.7, p97: 48.9),
        WHOPercentileRow(month: 19, p3: 43.6, p15: 44.7, p50: 46.4, p85: 47.8, p97: 49.1),
        WHOPercentileRow(month: 20, p3: 43.8, p15: 44.9, p50: 46.6, p85: 48.0, p97: 49.3),
        WHOPercentileRow(month: 21, p3: 43.9, p15: 45.0, p50: 46.7, p85: 48.1, p97: 49.4),
        WHOPercentileRow(month: 22, p3: 44.1, p15: 45.2, p50: 46.9, p85: 48.3, p97: 49.6),
        WHOPercentileRow(month: 23, p3: 44.2, p15: 45.3, p50: 47.0, p85: 48.5, p97: 49.8),
        WHOPercentileRow(month: 24, p3: 44.3, p15: 45.4, p50: 47.2, p85: 48.6, p97: 49.9),
    ])
}
