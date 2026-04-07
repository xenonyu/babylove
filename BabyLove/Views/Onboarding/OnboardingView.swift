import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var page = 0
    @State private var babyName = ""
    @State private var birthDate = Date()
    @State private var gender: Baby.Gender = .girl
    @State private var showDatePicker = false
    @FocusState private var isNameFieldFocused: Bool

    // Staggered entry animation states
    @State private var showEmoji = false
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showFeatures = false

    var body: some View {
        ZStack {
            Color.blBackground.ignoresSafeArea()
                .onTapGesture { isNameFieldFocused = false }

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<3) { i in
                        Capsule()
                            .fill(i == page ? Color.blPrimary : Color.blPrimary.opacity(0.2))
                            .frame(width: i == page ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.4), value: page)
                    }
                }
                .padding(.top, 60)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(format: NSLocalizedString("a11y.onboarding.step %lld %lld", comment: ""), page + 1, 3))

                if page == 1 {
                    // Page 1 uses ScrollView so the keyboard doesn't hide the
                    // gender picker or Continue button on smaller screens.
                    ScrollView {
                        Spacer(minLength: 32)
                        babyInfoPage
                        Spacer(minLength: 32)
                    }
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    Spacer()

                    switch page {
                    case 0:  welcomePage
                    default: allSetPage
                    }

                    Spacer()
                }

                // Next button
                if page < 2 {
                    Button(page == 0
                           ? String(localized: "onboarding.getStarted")
                           : String(localized: "onboarding.continue")) {
                        isNameFieldFocused = false
                        resetAnimationStates()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            page += 1
                        }
                        triggerEntryAnimations()
                    }
                    .buttonStyle(BLPrimaryButton())
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                    .disabled(page == 1 && babyName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(page == 1 && babyName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                } else {
                    Button(String(localized: "onboarding.startLogging")) {
                        let baby = Baby(name: babyName.trimmingCharacters(in: .whitespaces),
                                        birthDate: birthDate,
                                        gender: gender)
                        appState.completeOnboarding(with: baby)
                    }
                    .buttonStyle(BLPrimaryButton())
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                }
            }
        }
        .onAppear { triggerEntryAnimations() }
    }

    // MARK: - Animation Helpers

    private func resetAnimationStates() {
        showEmoji = false
        showTitle = false
        showSubtitle = false
        showFeatures = false
    }

    private func triggerEntryAnimations() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.15)) {
            showEmoji = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.35)) {
            showTitle = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.55)) {
            showSubtitle = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.75)) {
            showFeatures = true
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Text("🍼")
                .font(.system(size: 80))
                .scaleEffect(showEmoji ? 1.0 : 0.3)
                .opacity(showEmoji ? 1 : 0)

            Text("onboarding.welcomeTitle")
                .font(.system(size: 34, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.blTextPrimary)
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 12)

            Text("onboarding.welcomeSubtitle")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .foregroundColor(.blTextSecondary)
                .padding(.horizontal, 32)
                .opacity(showSubtitle ? 1 : 0)
                .offset(y: showSubtitle ? 0 : 12)

            // Feature highlights
            VStack(spacing: 14) {
                featureRow(icon: "bolt.fill", text: String(localized: "onboarding.feature1"), color: .blFeeding)
                featureRow(icon: "chart.line.uptrend.xyaxis", text: String(localized: "onboarding.feature2"), color: .blGrowth)
                featureRow(icon: "lock.shield.fill", text: String(localized: "onboarding.feature3"), color: .blDiaper)
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
            .opacity(showFeatures ? 1 : 0)
            .offset(y: showFeatures ? 0 : 16)
        }
    }

    /// Compact feature highlight row for welcome page
    @ViewBuilder
    private func featureRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(color)
            }
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.blTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var babyInfoPage: some View {
        VStack(spacing: 28) {
            Text("onboarding.tellUs")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.blTextPrimary)

            // Name field
            VStack(alignment: .leading, spacing: 8) {
                Text("onboarding.babyName")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blTextSecondary)
                TextField(String(localized: "onboarding.namePlaceholder"), text: $babyName)
                    .font(.system(size: 17))
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { isNameFieldFocused = false }
                    .padding(16)
                    .background(Color.blSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(String(localized: "common.done")) {
                                isNameFieldFocused = false
                            }
                            .font(.system(size: 16, weight: .semibold))
                        }
                    }
            }
            .padding(.horizontal, 32)

            // Birthday
            VStack(alignment: .leading, spacing: 8) {
                Text("onboarding.birthday")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blTextSecondary)
                Button {
                    showDatePicker.toggle()
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.blPrimary)
                        Text(birthDate.formatted(date: .long, time: .omitted))
                            .foregroundColor(.blTextPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(.blTextTertiary)
                    }
                    .padding(16)
                    .background(Color.blSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, 32)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(format: NSLocalizedString("a11y.onboarding.birthday %@", comment: ""), birthDate.formatted(date: .long, time: .omitted)))
            .accessibilityHint(NSLocalizedString("a11y.onboarding.birthdayHint", comment: ""))
            .sheet(isPresented: $showDatePicker) {
                DatePickerSheet(date: $birthDate)
            }

            // Gender
            VStack(alignment: .leading, spacing: 8) {
                Text("onboarding.gender")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blTextSecondary)
                    .padding(.horizontal, 32)
                HStack(spacing: 12) {
                    ForEach(Baby.Gender.allCases, id: \.self) { g in
                        Button {
                            withAnimation(.spring(response: 0.3)) { gender = g }
                        } label: {
                            VStack(spacing: 6) {
                                Text(g.icon)
                                    .font(.system(size: 28))
                                Text(g.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(gender == g ? .white : .blTextPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(gender == g ? Color.blPrimary : Color.blSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(g.displayName)
                        .accessibilityAddTraits(gender == g ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 32)
            }
        }
    }

    private var allSetPage: some View {
        VStack(spacing: 20) {
            Text("🎉")
                .font(.system(size: 80))
                .scaleEffect(showEmoji ? 1.0 : 0.3)
                .opacity(showEmoji ? 1 : 0)

            Text("onboarding.allSet")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.blTextPrimary)
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 12)

            Text(String(localized: "onboarding.readyToTrack \(babyName.isEmpty ? String(localized: "onboarding.yourBaby") : babyName)"))
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .foregroundColor(.blTextSecondary)
                .padding(.horizontal, 32)
                .opacity(showSubtitle ? 1 : 0)
                .offset(y: showSubtitle ? 0 : 12)

            // Summary of what they'll be able to do
            VStack(spacing: 10) {
                allSetFeature(icon: "drop.fill", text: String(localized: "onboarding.track.feeding"), color: .blFeeding)
                allSetFeature(icon: "moon.zzz.fill", text: String(localized: "onboarding.track.sleep"), color: .blSleep)
                allSetFeature(icon: "oval.fill", text: String(localized: "onboarding.track.diaper"), color: .blDiaper)
                allSetFeature(icon: "chart.bar.fill", text: String(localized: "onboarding.track.growth"), color: .blGrowth)
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
            .opacity(showFeatures ? 1 : 0)
            .offset(y: showFeatures ? 0 : 16)
        }
    }

    /// Compact feature item for the "All Set" page
    @ViewBuilder
    private func allSetFeature(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.blDiaper)
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.blTextSecondary)
            Spacer()
        }
    }
}

// MARK: - Date Picker Sheet
struct DatePickerSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(String(localized: "onboarding.birthday"), selection: $date,
                       in: ...Date(),
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle(String(localized: "onboarding.selectBirthday"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "common.done")) { dismiss() }
                    }
                }
        }
    }
}
