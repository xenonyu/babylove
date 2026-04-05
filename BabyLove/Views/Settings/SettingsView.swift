import SwiftUI
import CoreData

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showEditBaby = false
    @State private var showResetAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                List {
                    // Baby profile
                    Section {
                        if let baby = appState.currentBaby {
                            Button {
                                showEditBaby = true
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: baby.gender.color).opacity(0.2))
                                            .frame(width: 50, height: 50)
                                        Text(baby.gender.icon)
                                            .font(.system(size: 24))
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(baby.name)
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundColor(.blTextPrimary)
                                        Text("\(baby.ageText) old")
                                            .font(.system(size: 14))
                                            .foregroundColor(.blTextSecondary)
                                        Text(baby.birthDate.formatted(date: .long, time: .omitted))
                                            .font(.system(size: 12))
                                            .foregroundColor(.blTextTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(.blTextTertiary)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    } header: {
                        Text("Baby Profile")
                    }

                    // Units
                    Section {
                        Picker("Units", selection: Binding(
                            get: { appState.measurementUnit },
                            set: { appState.setMeasurementUnit($0) }
                        )) {
                            ForEach(MeasurementUnit.allCases, id: \.self) { u in
                                Text(u.displayName).tag(u)
                            }
                        }
                    } header: {
                        Text("Measurements")
                    }

                    // App info
                    Section {
                        HStack {
                            Label("Version", systemImage: "info.circle")
                            Spacer()
                            Text("1.0.0")
                                .foregroundColor(.blTextSecondary)
                        }
                        if let privacyURL = URL(string: "https://babylove.app/privacy") {
                            Link(destination: privacyURL) {
                                Label("Privacy Policy", systemImage: "hand.raised.fill")
                            }
                        }
                    } header: {
                        Text("About")
                    }

                    // Danger zone
                    Section {
                        Button(role: .destructive) {
                            showResetAlert = true
                        } label: {
                            Label("Reset All Data", systemImage: "trash.fill")
                        }
                    } header: {
                        Text("Danger Zone")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showEditBaby) {
            EditBabyView()
        }
        .alert("Reset All Data?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetAllData()
            }
        } message: {
            Text("This will permanently delete all tracking records and baby profiles. This action cannot be undone.")
        }
    }

    private func resetAllData() {
        UserDefaults.standard.removeObject(forKey: "currentBaby")
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        // Clear CoreData
        let container = PersistenceController.shared.container
        let ctx = container.viewContext
        for entity in ["CDFeedingRecord", "CDSleepRecord", "CDDiaperRecord", "CDGrowthRecord", "CDMilestone"] {
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            let delete = NSBatchDeleteRequest(fetchRequest: req)
            try? container.persistentStoreCoordinator.execute(delete, with: ctx)
        }
        withAnimation {
            appState.hasCompletedOnboarding = false
            appState.currentBaby = nil
        }
    }
}

// MARK: - Edit Baby
struct EditBabyView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var birthDate: Date = Date()
    @State private var gender: Baby.Gender = .girl

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                Form {
                    Section("Baby's Name") {
                        TextField("Name", text: $name)
                    }
                    Section("Birthday") {
                        DatePicker("Birthday", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    }
                    Section("Gender") {
                        Picker("Gender", selection: $gender) {
                            ForEach(Baby.Gender.allCases, id: \.self) { g in
                                Text("\(g.icon) \(g.displayName)").tag(g)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var baby = appState.currentBaby ?? Baby(name: name, birthDate: birthDate, gender: gender)
                        baby.name = name
                        baby.birthDate = birthDate
                        baby.gender = gender
                        appState.saveBaby(baby)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let baby = appState.currentBaby {
                    name = baby.name
                    birthDate = baby.birthDate
                    gender = baby.gender
                }
            }
        }
    }
}
