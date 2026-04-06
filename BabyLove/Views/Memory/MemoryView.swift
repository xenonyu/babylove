import SwiftUI
import CoreData

struct MemoryView: View {
    @EnvironmentObject var appState: AppState
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
            case .all: return String(localized: "memory.filterAll")
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

    /// Group milestones by month (e.g. "April 2026") for timeline display
    private var groupedByMonth: [(key: String, milestones: [CDMilestone])] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        var dict: [String: [CDMilestone]] = [:]
        var order: [String] = []
        for m in filteredMilestones {
            let date = m.date ?? Date.distantPast
            let key = fmt.string(from: date)
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(m)
        }
        // Sort months by the actual date of their first milestone (already sorted desc from FetchRequest)
        return order.map { (key: $0, milestones: dict[$0]!) }
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
                                        Text("memory.achieved \(achievedCount)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.blTextSecondary)
                                    }
                                    HStack(spacing: 4) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 12))
                                            .foregroundColor(.blGrowth)
                                        Text("memory.upcoming \(upcomingCount)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.blTextSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                            }

                            // Milestones timeline
                            if filteredMilestones.isEmpty {
                                noResultsState
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(groupedByMonth.enumerated()), id: \.element.key) { sectionIdx, section in
                                        // Month header
                                        HStack(spacing: 10) {
                                            Circle()
                                                .fill(Color.blPrimary)
                                                .frame(width: 10, height: 10)
                                            Text(section.key)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.blPrimary)
                                            Rectangle()
                                                .fill(Color.blPrimary.opacity(0.2))
                                                .frame(height: 1)
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.top, sectionIdx == 0 ? 4 : 20)
                                        .padding(.bottom, 12)

                                        ForEach(Array(section.milestones.enumerated()), id: \.element.objectID) { idx, m in
                                            let isLast = (idx == section.milestones.count - 1) && (sectionIdx == groupedByMonth.count - 1)
                                            timelineRow(milestone: m, isLastGlobal: isLast)
                                        }
                                    }
                                }
                            }

                            Spacer(minLength: 100)
                        }
                        .padding(.top, 16)
                    }
                }
            }
            .navigationTitle(String(localized: "memory.title"))
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
        .alert(String(localized: "memory.deleteTitle"), isPresented: Binding(
            get: { milestoneToDelete != nil },
            set: { if !$0 { milestoneToDelete = nil } }
        )) {
            Button(String(localized: "common.cancel"), role: .cancel) { milestoneToDelete = nil }
            Button(String(localized: "memory.delete"), role: .destructive) {
                Haptic.warning()
                if let m = milestoneToDelete {
                    let success = vm.deleteObject(m, in: ctx)
                    if success {
                        withAnimation { /* row removed */ }
                        appState.showToast(String(localized: "memory.deleted"), icon: "trash.fill", color: .blPrimary)
                    } else {
                        Haptic.error()
                        appState.showToast(String(localized: "common.deleteFailed"), icon: "exclamationmark.triangle.fill", color: .red)
                    }
                }
                milestoneToDelete = nil
            }
        } message: {
            Text("memory.deleteMessage")
        }
    }

    // MARK: - Timeline Row

    @ViewBuilder
    private func timelineRow(milestone m: CDMilestone, isLastGlobal: Bool) -> some View {
        let cat = MilestoneCategory(rawValue: m.category ?? "") ?? .custom
        let catColor = Color(hex: cat.color)

        HStack(alignment: .top, spacing: 0) {
            // Timeline connector (left gutter)
            VStack(spacing: 0) {
                // Dot
                ZStack {
                    Circle()
                        .fill(m.isCompleted ? catColor : catColor.opacity(0.3))
                        .frame(width: 12, height: 12)
                    if m.isCompleted {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(width: 20)

                // Vertical line (hidden for last item)
                if !isLastGlobal {
                    Rectangle()
                        .fill(catColor.opacity(0.18))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 20)
            .padding(.leading, 24)

            // Card
            MilestoneCard(milestone: m, baby: appState.currentBaby) {
                Haptic.medium()
                withAnimation(.spring(response: 0.35)) {
                    vm.toggleMilestoneCompleted(m, in: ctx)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { milestoneToEdit = m }
            .contextMenu {
                Button {
                    milestoneToEdit = m
                } label: {
                    Label(String(localized: "memory.edit"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    milestoneToDelete = m
                } label: {
                    Label(String(localized: "memory.delete"), systemImage: "trash")
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 20)
            .padding(.bottom, 12)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Category Filter Bar

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MilestoneFilter.allFilters, id: \.self) { filter in
                    let isSelected = selectedFilter == filter
                    Button {
                        Haptic.selection()
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
            Text(String(format: String(localized: "memory.noMilestones"), selectedFilter.label.lowercased()))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blTextSecondary)
            Button {
                showAddMilestone = true
            } label: {
                Text("memory.addOne")
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
            Text("memory.emptyTitle")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.blTextPrimary)
            Text("memory.emptySubtitle")
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .foregroundColor(.blTextSecondary)
                .padding(.horizontal, 40)
            Button(String(localized: "memory.addFirst")) { showAddMilestone = true }
                .buttonStyle(BLPrimaryButton())
                .frame(width: 240)
        }
    }
}

// MARK: - Milestone Card
struct MilestoneCard: View {
    @ObservedObject var milestone: CDMilestone
    var baby: Baby?
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
                        .strikethrough(isCompleted, color: .blTextSecondary.opacity(0.4))
                    Spacer()
                    Text(isCompleted ? String(localized: "memory.achievedBadge") : String(localized: "memory.upcomingBadge"))
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

                    // Baby's age at this milestone
                    if let baby, let date = milestone.date {
                        Text(baby.ageText(at: date))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: category.color))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: category.color).opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                if let notes = milestone.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
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
    @State private var isCompleted = false
    @State private var showSuggestions = false

    private var isEditing: Bool { editingRecord != nil }

    /// Baby's current age in months (nil if no baby profile)
    private var babyAgeMonths: Int? {
        appState.currentBaby?.ageInMonths
    }

    /// Suggestions for the currently selected category, sorted by age relevance
    private var currentSuggestions: [PresetMilestone] {
        if let age = babyAgeMonths {
            return PresetMilestone.forCategory(category, babyAgeMonths: age)
        }
        return PresetMilestone.forCategory(category)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        // Title with suggestions
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(String(localized: "memory.milestone"), systemImage: "star.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.blTextSecondary)
                                Spacer()
                                if !isEditing {
                                    Button {
                                        withAnimation(.spring(response: 0.3)) {
                                            showSuggestions.toggle()
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: showSuggestions ? "lightbulb.fill" : "lightbulb")
                                                .font(.system(size: 12, weight: .medium))
                                            Text("memory.suggestions")
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                        .foregroundColor(showSuggestions ? .blPrimary : .blTextTertiary)
                                    }
                                }
                            }
                            TextField(String(localized: "memory.placeholder"), text: $title)
                                .font(.system(size: 17))
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            // Preset suggestions chips
                            if showSuggestions && !isEditing {
                                suggestionsGrid
                            }
                        }

                        // Category
                        VStack(alignment: .leading, spacing: 10) {
                            Label(String(localized: "memory.category"), systemImage: "tag.fill")
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
                            Label(String(localized: "memory.date"), systemImage: "calendar")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            DatePicker(String(localized: "memory.milestoneDate"), selection: $date, in: ...Date(), displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .tint(.blPrimary)
                                .labelsHidden()
                                .accessibilityLabel(String(localized: "memory.milestoneDate"))
                        }

                        // Status
                        VStack(alignment: .leading, spacing: 10) {
                            Label(String(localized: "memory.status"), systemImage: "flag.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            HStack(spacing: 12) {
                                statusButton(label: String(localized: "memory.achievedBadge"), icon: "checkmark.circle.fill", selected: isCompleted) {
                                    withAnimation(.spring(response: 0.3)) { isCompleted = true }
                                }
                                statusButton(label: String(localized: "memory.upcomingBadge"), icon: "clock", selected: !isCompleted) {
                                    withAnimation(.spring(response: 0.3)) { isCompleted = false }
                                }
                            }
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 10) {
                            Label(String(localized: "memory.notes"), systemImage: "note.text")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            TextField(String(localized: "memory.notesPlaceholder"), text: $notes, axis: .vertical)
                                .lineLimit(3...6)
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button(isEditing ? String(localized: "memory.update") : String(localized: "memory.save")) {
                            var ok = false
                            if let record = editingRecord {
                                ok = vm.updateMilestone(record, title: title, category: category, date: date, notes: notes, isCompleted: isCompleted)
                                appState.showToast(ok ? String(localized: "memory.updated") : String(localized: "memory.saveFailed"),
                                                   icon: ok ? "pencil.circle.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blPrimary : .red)
                            } else {
                                ok = vm.addMilestone(title: title, category: category, date: date, notes: notes, isCompleted: isCompleted)
                                appState.showToast(ok ? String(localized: "memory.saved") : String(localized: "memory.saveFailed"),
                                                   icon: ok ? "star.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blPrimary : .red)
                            }
                            if ok { Haptic.success(); dismiss() } else { Haptic.error() }
                        }
                        .buttonStyle(BLPrimaryButton())
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .padding(.top, 8)
                    }
                    .padding(24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? String(localized: "memory.editTitle") : String(localized: "memory.addTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(String(localized: "common.done")) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blPrimary)
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

    // MARK: - Suggestions Grid

    private var suggestionsGrid: some View {
        let age = babyAgeMonths
        return VStack(alignment: .leading, spacing: 8) {
            // Age context hint
            if let age {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("memory.sortedForAge \(age)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.blTextTertiary)
            }

            if currentSuggestions.isEmpty {
                Text("memory.noSuggestions")
                    .font(.system(size: 13))
                    .foregroundColor(.blTextTertiary)
                    .padding(.vertical, 4)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(currentSuggestions) { preset in
                        let isSelected = title == preset.title
                        let relevance = age.map { preset.relevance(forBabyAgeMonths: $0) }
                        let isCurrent = relevance == .current
                        let isPast = relevance == .past
                        let catColor = Color(hex: category.color)

                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                title = preset.title
                                showSuggestions = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                // Show a star for age-appropriate milestones
                                if isCurrent {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                }
                                Text(preset.title)
                                    .font(.system(size: 13, weight: isCurrent ? .semibold : .medium))
                                Text(preset.ageRangeMonths + String(localized: "preset.ageMonths"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(
                                        isSelected ? .white.opacity(0.7) :
                                        isPast ? catColor.opacity(0.3) :
                                        catColor.opacity(0.6)
                                    )
                            }
                            .foregroundColor(
                                isSelected ? .white :
                                isPast ? catColor.opacity(0.4) :
                                catColor
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? catColor :
                                isCurrent ? catColor.opacity(0.18) :
                                catColor.opacity(isPast ? 0.05 : 0.1)
                            )
                            .clipShape(Capsule())
                            .overlay(
                                isCurrent && !isSelected ?
                                Capsule().strokeBorder(catColor.opacity(0.35), lineWidth: 1) : nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
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
