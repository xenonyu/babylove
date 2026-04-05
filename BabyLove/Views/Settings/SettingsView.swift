import SwiftUI
import CoreData
import UniformTypeIdentifiers
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showEditBaby = false
    @State private var showResetAlert = false
    @State private var showExportShare = false
    @State private var exportFileURL: URL?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showExportError = false

    // Feeding reminder state
    @State private var feedingReminderEnabled = NotificationManager.shared.isEnabled
    @State private var feedingReminderInterval = NotificationManager.shared.intervalMinutes
    @State private var notificationDenied = false

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
                                    BabyAvatarView(baby: baby, size: 50)
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

                    // Feeding reminders
                    Section {
                        Toggle(isOn: $feedingReminderEnabled) {
                            Label("Feeding Reminders", systemImage: "bell.badge.fill")
                        }
                        .tint(.blFeeding)
                        .onChange(of: feedingReminderEnabled) { _, enabled in
                            Task { @MainActor in
                                if enabled {
                                    let granted = await NotificationManager.shared.requestPermission()
                                    if granted {
                                        NotificationManager.shared.isEnabled = true
                                        // Schedule from now if turning on
                                        NotificationManager.shared.scheduleFeedingReminder()
                                    } else {
                                        feedingReminderEnabled = false
                                        notificationDenied = true
                                    }
                                } else {
                                    NotificationManager.shared.isEnabled = false
                                }
                            }
                        }

                        if feedingReminderEnabled {
                            Picker(selection: $feedingReminderInterval) {
                                ForEach(NotificationManager.ReminderInterval.options) { opt in
                                    Text(opt.label).tag(opt.id)
                                }
                            } label: {
                                Label("Interval", systemImage: "clock.arrow.circlepath")
                            }
                            .onChange(of: feedingReminderInterval) { _, newVal in
                                NotificationManager.shared.intervalMinutes = newVal
                                // Re-schedule with new interval
                                NotificationManager.shared.scheduleFeedingReminder()
                            }
                        }
                    } header: {
                        Text("Reminders")
                    } footer: {
                        Text(feedingReminderEnabled
                             ? "You'll get a reminder after each feeding based on the interval above."
                             : "Get notified when it's time for the next feeding.")
                    }

                    // Data export
                    Section {
                        Button {
                            exportAllData()
                        } label: {
                            HStack {
                                Label("Export All Data (CSV)", systemImage: "square.and.arrow.up")
                                Spacer()
                                if isExporting {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                        .disabled(isExporting)
                    } header: {
                        Text("Data")
                    } footer: {
                        Text("Export all records as CSV files. Share with your pediatrician or save as a backup.")
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
            .task {
                // Sync toggle with actual notification permission
                let status = await NotificationManager.shared.authorizationStatus()
                if status == .denied && feedingReminderEnabled {
                    feedingReminderEnabled = false
                    NotificationManager.shared.isEnabled = false
                }
            }
        }
        .sheet(isPresented: $showEditBaby) {
            EditBabyView()
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .alert("Reset All Data?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Haptic.warning()
                resetAllData()
            }
        } message: {
            Text("This will permanently delete all tracking records and baby profiles. This action cannot be undone.")
        }
        .alert("Notifications Disabled", isPresented: $notificationDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable notifications in Settings to receive feeding reminders.")
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "An unknown error occurred.")
        }
    }

    // MARK: - Export

    private func exportAllData() {
        isExporting = true
        let ctx = PersistenceController.shared.container.viewContext
        let unit = appState.measurementUnit
        let babyName = appState.currentBaby?.name ?? "Baby"
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]

        do {
            // Build CSV content with all record types in one file
            var csv = "Record Type,Date,Time,Details,Notes\n"

            // Feeding records
            let feedReq: NSFetchRequest<CDFeedingRecord> = CDFeedingRecord.fetchRequest()
            feedReq.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            let feedings = try ctx.fetch(feedReq)
            for r in feedings {
                let date = r.timestamp.map { dateFormatter.string(from: $0) } ?? ""
                let time = r.timestamp?.formatted(date: .omitted, time: .shortened) ?? ""
                let feedType = FeedType(rawValue: r.feedType ?? "")?.displayName ?? r.feedType ?? ""
                var details = [feedType]
                if r.durationMinutes > 0 { details.append("\(r.durationMinutes) min") }
                if r.amountML > 0 {
                    let val = unit.volumeFromML(r.amountML)
                    details.append(unit == .metric ? "\(Int(val)) \(unit.volumeLabel)" : String(format: "%.1f %@", val, unit.volumeLabel))
                }
                if let side = r.breastSide, !side.isEmpty {
                    details.append(BreastSide(rawValue: side)?.displayName ?? side)
                }
                let notes = csvEscape(r.notes)
                csv += "Feeding,\(date),\(time),\(csvEscape(details.joined(separator: "; "))),\(notes)\n"
            }

            // Sleep records
            let sleepReq: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
            sleepReq.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: true)]
            let sleeps = try ctx.fetch(sleepReq)
            for r in sleeps {
                let date = r.startTime.map { dateFormatter.string(from: $0) } ?? ""
                let startTime = r.startTime?.formatted(date: .omitted, time: .shortened) ?? ""
                var details = [String]()
                if let loc = r.location, let sl = SleepLocation(rawValue: loc) {
                    details.append(sl.displayName)
                }
                if let s = r.startTime, let e = r.endTime {
                    let mins = Int(e.timeIntervalSince(s) / 60)
                    let h = mins / 60, m = mins % 60
                    details.append(h > 0 ? "\(h)h \(m)m" : "\(m)m")
                    details.append("End: \(e.formatted(date: .omitted, time: .shortened))")
                } else {
                    details.append("Ongoing")
                }
                let notes = csvEscape(r.notes)
                csv += "Sleep,\(date),\(startTime),\(csvEscape(details.joined(separator: "; "))),\(notes)\n"
            }

            // Diaper records
            let diaperReq: NSFetchRequest<CDDiaperRecord> = CDDiaperRecord.fetchRequest()
            diaperReq.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            let diapers = try ctx.fetch(diaperReq)
            for r in diapers {
                let date = r.timestamp.map { dateFormatter.string(from: $0) } ?? ""
                let time = r.timestamp?.formatted(date: .omitted, time: .shortened) ?? ""
                let dType = DiaperType(rawValue: r.diaperType ?? "")?.displayName ?? r.diaperType ?? ""
                let notes = csvEscape(r.notes)
                csv += "Diaper,\(date),\(time),\(dType),\(notes)\n"
            }

            // Growth records
            let growthReq: NSFetchRequest<CDGrowthRecord> = CDGrowthRecord.fetchRequest()
            growthReq.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            let growths = try ctx.fetch(growthReq)
            for r in growths {
                let date = r.date.map { dateFormatter.string(from: $0) } ?? ""
                var details = [String]()
                if r.weightKG > 0 {
                    let w = unit.weightFromKG(r.weightKG)
                    details.append(String(format: "%.2f %@", w, unit.weightLabel))
                }
                if r.heightCM > 0 {
                    let h = unit.lengthFromCM(r.heightCM)
                    details.append(String(format: "%.1f %@ height", h, unit.heightLabel))
                }
                if r.headCircumferenceCM > 0 {
                    let hc = unit.lengthFromCM(r.headCircumferenceCM)
                    details.append(String(format: "%.1f %@ head", hc, unit.heightLabel))
                }
                let notes = csvEscape(r.notes)
                csv += "Growth,\(date),,\(csvEscape(details.joined(separator: "; "))),\(notes)\n"
            }

            // Milestones
            let mileReq: NSFetchRequest<CDMilestone> = CDMilestone.fetchRequest()
            mileReq.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            let milestones = try ctx.fetch(mileReq)
            for r in milestones {
                let date = r.date.map { dateFormatter.string(from: $0) } ?? ""
                let title = csvEscape(r.title)
                let cat = MilestoneCategory(rawValue: r.category ?? "")?.displayName ?? r.category ?? ""
                let status = r.isCompleted ? "Completed" : "In Progress"
                let notes = csvEscape(r.notes)
                csv += "Milestone,\(date),,\(title) [\(cat)] (\(status)),\(notes)\n"
            }

            // Write to temp file
            let fileName = "\(babyName)_BabyLove_Export_\(Self.fileDate()).csv"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)

            exportFileURL = tempURL
            isExporting = false
            showExportShare = true

        } catch {
            isExporting = false
            exportError = error.localizedDescription
            showExportError = true
        }
    }

    private func csvEscape(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func fileDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func resetAllData() {
        // 1. Cancel all pending notifications and reset reminder state
        NotificationManager.shared.isEnabled = false  // cancels pending + writes UserDefaults
        feedingReminderEnabled = false
        feedingReminderInterval = 180

        // 2. Clear baby profile from UserDefaults
        UserDefaults.standard.removeObject(forKey: "currentBaby")
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")

        // 3. Batch-delete CoreData entities and merge into viewContext
        //    NSBatchDeleteRequest bypasses the MOC — without merging,
        //    @FetchRequest views hold stale objects that crash when faulted.
        let container = PersistenceController.shared.container
        let ctx = container.viewContext
        for entity in ["CDFeedingRecord", "CDSleepRecord", "CDDiaperRecord", "CDGrowthRecord", "CDMilestone"] {
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            let delete = NSBatchDeleteRequest(fetchRequest: req)
            delete.resultType = .resultTypeObjectIDs
            do {
                let result = try container.persistentStoreCoordinator.execute(delete, with: ctx) as? NSBatchDeleteResult
                if let objectIDs = result?.result as? [NSManagedObjectID], !objectIDs.isEmpty {
                    let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: objectIDs]
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [ctx])
                }
            } catch {
                // Fallback: reset the entire context if merge fails
                ctx.reset()
            }
        }

        // 4. Navigate to onboarding
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
    @State private var photoData: Data?
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                Form {
                    // Photo section
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                // Current photo or placeholder
                                if let photoData, let uiImage = UIImage(data: photoData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 96, height: 96)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.blPrimary.opacity(0.3), lineWidth: 2)
                                        )
                                } else {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: gender.color).opacity(0.2))
                                            .frame(width: 96, height: 96)
                                        Text(gender.icon)
                                            .font(.system(size: 44))
                                    }
                                }

                                PhotosPicker(selection: $selectedPhoto,
                                             matching: .images,
                                             photoLibrary: .shared()) {
                                    HStack(spacing: 6) {
                                        Image(systemName: photoData != nil ? "arrow.triangle.2.circlepath.camera" : "camera.fill")
                                            .font(.system(size: 13, weight: .medium))
                                        Text(photoData != nil ? "Change Photo" : "Add Photo")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundColor(.blPrimary)
                                }

                                if photoData != nil {
                                    Button {
                                        withAnimation(.spring(response: 0.3)) {
                                            photoData = nil
                                            selectedPhoto = nil
                                        }
                                    } label: {
                                        Text("Remove Photo")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.blTextTertiary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }

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
                        baby.photoData = photoData
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
                    photoData = baby.photoData
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task {
                    if let newItem,
                       let data = try? await newItem.loadTransferable(type: Data.self) {
                        // Compress to JPEG to keep UserDefaults size reasonable
                        if let uiImage = UIImage(data: data),
                           let compressed = uiImage.jpegData(compressionQuality: 0.6) {
                            await MainActor.run {
                                withAnimation(.spring(response: 0.3)) {
                                    photoData = compressed
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Share Sheet (UIKit bridge)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
