import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var hasCompletedOnboarding: Bool
    @Published var currentBaby: Baby?
    @Published var measurementUnit: MeasurementUnit = .metric

    private let babyKey = "currentBaby"
    private let onboardingKey = "hasCompletedOnboarding"
    private let unitKey = "measurementUnit"

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if let data = UserDefaults.standard.data(forKey: "currentBaby"),
           let baby = try? JSONDecoder().decode(Baby.self, from: data) {
            self.currentBaby = baby
        }
        let unitRaw = UserDefaults.standard.string(forKey: "measurementUnit") ?? MeasurementUnit.metric.rawValue
        self.measurementUnit = MeasurementUnit(rawValue: unitRaw) ?? .metric
    }

    func completeOnboarding(with baby: Baby) {
        saveBaby(baby)
        UserDefaults.standard.set(true, forKey: onboardingKey)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            hasCompletedOnboarding = true
        }
    }

    func saveBaby(_ baby: Baby) {
        if let data = try? JSONEncoder().encode(baby) {
            UserDefaults.standard.set(data, forKey: babyKey)
        }
        currentBaby = baby
    }

    func setMeasurementUnit(_ unit: MeasurementUnit) {
        measurementUnit = unit
        UserDefaults.standard.set(unit.rawValue, forKey: unitKey)
    }
}

enum MeasurementUnit: String, CaseIterable {
    case metric   = "metric"
    case imperial = "imperial"

    var weightLabel: String  { self == .metric ? "kg"  : "lbs" }
    var heightLabel: String  { self == .metric ? "cm"  : "in"  }
    var volumeLabel: String  { self == .metric ? "ml"  : "oz"  }

    var displayName: String {
        switch self {
        case .metric:   return "Metric (kg, cm)"
        case .imperial: return "Imperial (lbs, in)"
        }
    }
}
