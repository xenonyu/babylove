import SwiftUI
import CoreData

struct MemoryView: View {
    @Environment(\.managedObjectContext) var ctx
    @StateObject private var vm = TrackViewModel(context: PersistenceController.shared.container.viewContext)
    @State private var showAddMilestone = false

    @FetchRequest(
        entity: CDMilestone.entity(),
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
    ) private var milestones: FetchedResults<CDMilestone>

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()

                if milestones.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(milestones) { m in
                                MilestoneCard(milestone: m)
                                    .padding(.horizontal, 20)
                            }
                            Spacer(minLength: 100)
                        }
                        .padding(.top, 16)
                    }
                }
            }
            .navigationTitle("Memories")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddMilestone = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.blPrimary)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddMilestone) {
            AddMilestoneView(vm: vm)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Text("💛")
                .font(.system(size: 64))
            Text("Start capturing memories")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.blTextPrimary)
            Text("Record milestones, first moments,\nand everything in between.")
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .foregroundColor(.blTextSecondary)
                .padding(.horizontal, 40)
            Button("Add First Milestone") { showAddMilestone = true }
                .buttonStyle(BLPrimaryButton())
                .frame(width: 240)
        }
    }
}

// MARK: - Milestone Card
struct MilestoneCard: View {
    let milestone: CDMilestone
    private var category: MilestoneCategory {
        MilestoneCategory(rawValue: milestone.category ?? "") ?? .custom
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Category icon
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: category.color).opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: category.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(Color(hex: category.color))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(milestone.title ?? "")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blTextPrimary)
                    Spacer()
                    Text(category.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: category.color))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: category.color).opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(milestone.date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "")
                    .font(.system(size: 13))
                    .foregroundColor(.blTextSecondary)

                if let notes = milestone.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 14))
                        .foregroundColor(.blTextSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(16)
        .blCard()
    }
}

// MARK: - Add Milestone
struct AddMilestoneView: View {
    @ObservedObject var vm: TrackViewModel
    @Environment(\.dismiss) var dismiss

    @State private var title    = ""
    @State private var category: MilestoneCategory = .social
    @State private var date     = Date()
    @State private var notes    = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        // Title
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Milestone", systemImage: "star.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            TextField("e.g. First smile, First steps…", text: $title)
                                .font(.system(size: 17))
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        // Category
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Category", systemImage: "tag.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(MilestoneCategory.allCases, id: \.self) { c in
                                    Button {
                                        withAnimation(.spring(response: 0.3)) { category = c }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: c.icon)
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(category == c ? .white : Color(hex: c.color))
                                            Text(c.displayName)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(category == c ? .white : .blTextPrimary)
                                                .multilineTextAlignment(.center)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(category == c ? Color(hex: c.color) : Color.blSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Date
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Date", systemImage: "calendar")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .tint(.blPrimary)
                                .labelsHidden()
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Notes", systemImage: "note.text")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            TextField("Describe this special moment…", text: $notes, axis: .vertical)
                                .lineLimit(3...6)
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button("Save Milestone ⭐️") {
                            vm.addMilestone(title: title, category: category, date: date, notes: notes)
                            dismiss()
                        }
                        .buttonStyle(BLPrimaryButton())
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .padding(.top, 8)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Add Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
