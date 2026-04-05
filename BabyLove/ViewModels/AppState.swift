import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var hasCompletedOnboarding: Bool
    @Published var currentBaby: Baby?
    @Published var measurementUnit: MeasurementUnit = .metric

    /// Toast notification state — set via showToast() to display a brief success message
    @Published var toastMessage: String?
    @Published var toastIcon: String?
    @Published var toastColor: Color?

    /// Tracks the current toast so stale dismiss tasks don't cancel a newer toast
    private var currentToastID: UUID?

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

    /// Show a brief toast notification with an optional SF Symbol icon.
    /// The toast auto-dismisses after 2 seconds.
    ///
    /// Uses a unique ID per toast so that rapid successive calls don't
    /// cause an earlier dismiss-task to prematurely clear a newer toast.
    @MainActor
    func showToast(_ message: String, icon: String = "checkmark.circle.fill", color: Color = .blPrimary) {
        let id = UUID()
        currentToastID = id
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toastMessage = message
            toastIcon = icon
            toastColor = color
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            // Only dismiss if no newer toast has replaced this one
            guard self?.currentToastID == id else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self?.toastMessage = nil
                self?.toastIcon = nil
                self?.toastColor = nil
            }
        }
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

    // MARK: - Unit Conversion (storage is always metric)

    /// Convert user-entered weight to kg for storage
    func weightToKG(_ value: Double) -> Double {
        self == .metric ? value : value / 2.20462
    }

    /// Convert stored kg to display unit
    func weightFromKG(_ kg: Double) -> Double {
        self == .metric ? kg : kg * 2.20462
    }

    /// Convert user-entered length to cm for storage
    func lengthToCM(_ value: Double) -> Double {
        self == .metric ? value : value * 2.54
    }

    /// Convert stored cm to display unit
    func lengthFromCM(_ cm: Double) -> Double {
        self == .metric ? cm : cm / 2.54
    }

    /// Convert user-entered volume to ml for storage
    func volumeToML(_ value: Double) -> Double {
        self == .metric ? value : value * 29.5735
    }

    /// Convert stored ml to display unit
    func volumeFromML(_ ml: Double) -> Double {
        self == .metric ? ml : ml / 29.5735
    }
}
