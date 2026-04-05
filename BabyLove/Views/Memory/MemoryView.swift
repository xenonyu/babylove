import SwiftUI
import CoreData

struct MemoryView: View {
    @Environment(\.managedObjectContext) var ctx
    @StateObject private var vm = TrackViewModel(context: PersistenceController.shared.container.viewContext)
    @State private var showAddMilestone = false
    @State private var milestoneToEdit: CDMilestone?
    @State private var milestoneToDelete: CDMilestone?
    @State private var selectedFilter: MilestoneFilter = .all

    enum MilestoneFilter: Hashable {
        case all
        case category(MilestoneCategory)

        var label: String {
            switch self {
            case .all: return "All"
            case .category(let c): return c.displayName
            }
        }

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .category(let c): return c.icon
            }
        }

        var color: Color {
            switch self {
            case .all: return .blPrimary
            case .category(let c): return Color(hex: c.color)
            }
        }

        static var allFilters: [MilestoneFilter] {
            [.all] + MilestoneCategory.allCases.map { .category($0) }
        }
    }

    @FetchRequest(
        entity: CDMilestone.entity(),
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
    ) private var milestones: FetchedResults<CDMilestone>

    private var filteredMilestones: [CDMilestone] {
        switch selectedFilter {
        case .all:
            return Array(milestones)
        case .category(let cat):
            return milestones.filter { $0.category == cat.rawValue }
        }
    }

    /// Summary counts for the header
    private var achievedCount: Int {
        filteredMilestones.filter { $0.isCompleted }.count
    }
    private var upcomingCount: Int {
        filteredMilestones.filter { !$0.isCompleted }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()

                if milestones.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Category filter chips
                            categoryFilterBar
                                .padding(.horizontal, 20)

                            // Summary counts
                            if !filteredMilestones.isEmpty {
                                HStack(spacing: 16) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.blDiaper)
                                        Text("\(achievedCount) Achieved")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.blTextSecondary)
                                    }
                                    HStack(spacing: 4) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 12))
                                            .foregroundColor(.blGrowth)
                                        Text("\(upcomingCount) Upcoming")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.blTextSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                            }

                            // Milestones list
                            if filteredMilestones.isEmpty {
                                noResultsState
                            } else {
                                LazyVStack(spacing: 16) {
                                    ForEach(filteredMilestones, id: \.objectID) { m in
                                        MilestoneCard(milestone: m) {
                                            withAnimation(.spring(response: 0.35)) {
                                                vm.toggleMilestoneCompleted(m, in: ctx)
                                            }
                                        }
                                            .padding(.horizontal, 20)
                                            .contextMenu {
                                                Button {
                                                    milestoneToEdit = m
                                                } label: {
                                                    Label("Edit", systemImage: "pencil")
                                                }
                                                Button(role: .destructive) {
                                                    milestoneToDelete = m
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
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
        .sheet(item: $milestoneToEdit) { record in
            AddMilestoneView(vm: vm, editingRecord: record)
        }
        .alert("Delete Milestone?", isPresented: Binding(
            get: { milestoneToDelete != nil },
            set: { if !$0 { milestoneToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { milestoneToDelete = nil }
            Button("Delete", role: .destructive) {
                if let m = milestoneToDelete {
                    withAnimation { vm.deleteObject(m, in: ctx) }
                }
                milestoneToDelete = nil
            }
        } message: {
            Text("This memory will be permanently removed.")
        }
    }

    // MARK: - Category Filter Bar

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MilestoneFilter.allFilters, id: \.self) { filter in
                    let isSelected = selectedFilter == filter
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedFilter = filter
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: filter.icon)
                                .font(.system(size: 12, weight: .medium))
                            Text(filter.label)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(isSelected ? .white : filter.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isSelected ? filter.color : filter.color.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - No Results for Filter

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedFilter.icon)
                .font(.system(size: 36))
                .foregroundColor(selectedFilter.color.opacity(0.4))
            Text("No \(selectedFilter.label.lowercased()) milestones yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blTextSecondary)
            Button {
                showAddMilestone = true
            } label: {
                Text("Add One")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(selectedFilter.color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Empty State (no milestones at all)

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
    @ObservedObject var milestone: CDMilestone
    var onToggleCompleted: (() -> Void)?

    private var category: MilestoneCategory {
        MilestoneCategory(rawValue: milestone.category ?? "") ?? .custom
    }

    private var isCompleted: Bool { milestone.isCompleted }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Completion toggle button
            Button {
                onToggleCompleted?()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: category.color).opacity(isCompleted ? 0.2 : 0.08))
                        .frame(width: 52, height: 52)
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : category.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Color(hex: category.color).opacity(isCompleted ? 1.0 : 0.5))
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(milestone.title ?? "")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isCompleted ? .blTextPrimary : .blTextSecondary)
                        .strikethrough(!isCompleted, color: .blTextSecondary.opacity(0.4))
                    Spacer()
                    Text(isCompleted ? "Achieved" : "Upcoming")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isCompleted ? Color(hex: category.color) : .blTextSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((isCompleted ? Color(hex: category.color) : Color.blTextSecondary).opacity(0.12))
                        .clipShape(Capsule())
                }

                HStack(spacing: 6) {
                    Text(category.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: category.color))

                    Text("·")
                        .foregroundColor(.blTextSecondary)

                    Text(milestone.date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "")
                        .font(.system(size: 13))
                        .foregroundColor(.blTextSecondary)
                }

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
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    /// When non-nil, we are editing an existing record
    var editingRecord: CDMilestone?

    @State private var title       = ""
    @State private var category: MilestoneCategory = .social
    @State private var date        = Date()
    @State private var notes       = ""
    @State private var isCompleted = true

    private var isEditing: Bool { editingRecord != nil }

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

                        // Status
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Status", systemImage: "flag.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            HStack(spacing: 12) {
                                statusButton(label: "Achieved", icon: "checkmark.circle.fill", selected: isCompleted) {
                                    withAnimation(.spring(response: 0.3)) { isCompleted = true }
                                }
                                statusButton(label: "Upcoming", icon: "clock", selected: !isCompleted) {
                                    withAnimation(.spring(response: 0.3)) { isCompleted = false }
                                }
                            }
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

                        Button(isEditing ? "Update Milestone ⭐️" : "Save Milestone ⭐️") {
                            if let record = editingRecord {
                                vm.updateMilestone(record, title: title, category: category, date: date, notes: notes, isCompleted: isCompleted)
                                appState.showToast("Milestone updated", icon: "pencil.circle.fill")
                            } else {
                                vm.addMilestone(title: title, category: category, date: date, notes: notes, isCompleted: isCompleted)
                                appState.showToast("Milestone saved", icon: "star.fill")
                            }
                            dismiss()
                        }
                        .buttonStyle(BLPrimaryButton())
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .padding(.top, 8)
                    }
                    .padding(24)
                }
            }
            .navigationTitle(isEditing ? "Edit Milestone" : "Add Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { populateFromRecord() }
        }
    }

    private func populateFromRecord() {
        guard let r = editingRecord else { return }
        title = r.title ?? ""
        category = MilestoneCategory(rawValue: r.category ?? "") ?? .custom
        date = r.date ?? Date()
        notes = r.notes ?? ""
        isCompleted = r.isCompleted
    }

    private func statusButton(label: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(label)
                    .font(.system(size: 15, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(selected ? Color.blPrimary.opacity(0.12) : Color.blSurface)
            .foregroundColor(selected ? .blPrimary : .blTextSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.blPrimary.opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
