import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var page = 0
    @State private var babyName = ""
    @State private var birthDate = Date()
    @State private var gender: Baby.Gender = .girl
    @State private var showDatePicker = false
    @FocusState private var isNameFieldFocused: Bool

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
                    Button(page == 0 ? "Get Started" : "Continue") {
                        isNameFieldFocused = false
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            page += 1
                        }
                    }
                    .buttonStyle(BLPrimaryButton())
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                    .disabled(page == 1 && babyName.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    Button("Start Logging 💛") {
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
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Text("🍼")
                .font(.system(size: 80))
            Text("Welcome to\nBabyLove")
                .font(.system(size: 34, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.blTextPrimary)
            Text("The simplest way to track\nyour baby's precious moments.")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .foregroundColor(.blTextSecondary)
                .padding(.horizontal, 32)
        }
    }

    private var babyInfoPage: some View {
        VStack(spacing: 28) {
            Text("Tell us about your baby")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.blTextPrimary)

            // Name field
            VStack(alignment: .leading, spacing: 8) {
                Text("Baby's Name")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blTextSecondary)
                TextField("e.g. Emma, Oliver…", text: $babyName)
                    .font(.system(size: 17))
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { isNameFieldFocused = false }
                    .padding(16)
                    .background(Color.blSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 32)

            // Birthday
            VStack(alignment: .leading, spacing: 8) {
                Text("Birthday")
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
            .sheet(isPresented: $showDatePicker) {
                DatePickerSheet(date: $birthDate)
            }

            // Gender
            VStack(alignment: .leading, spacing: 8) {
                Text("Gender")
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
            Text("All set!")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.blTextPrimary)
            Text("Ready to start tracking\n\(babyName.isEmpty ? "your baby" : babyName)'s journey 💛")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .foregroundColor(.blTextSecondary)
                .padding(.horizontal, 32)
        }
    }
}

// MARK: - Date Picker Sheet
struct DatePickerSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            DatePicker("Birthday", selection: $date,
                       in: ...Date(),
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Select Birthday")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
