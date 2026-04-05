import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let ctrl = PersistenceController(inMemory: true)
        let ctx = ctrl.container.viewContext
        // Insert sample data for previews
        let feed = CDFeedingRecord(context: ctx)
        feed.id = UUID()
        feed.timestamp = Date()
        feed.feedType = FeedType.breast.rawValue
        feed.durationMinutes = 15
        try? ctx.save()
        return ctrl
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "BabyLove")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("CoreData store failed to load: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func save() {
        let ctx = container.viewContext
        guard ctx.hasChanges else { return }
        try? ctx.save()
    }
}
