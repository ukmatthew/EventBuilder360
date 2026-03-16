import SwiftUI
import Foundation
import Combine

struct EventRecord: Identifiable, Decodable, Hashable {
    let id: Int64
    let createdAt: Date
    let name: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let createdAtRaw = try container.decode(String.self, forKey: .createdAt)

        if let parsed = DateParsers.iso8601WithFractional.date(from: createdAtRaw) ?? DateParsers.iso8601.date(from: createdAtRaw) {
            createdAt = parsed
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "Could not parse created_at date: \(createdAtRaw)"
            )
        }
    }
}

struct SupabaseEnvironment {
    let url: URL
    let publishableKey: String
}

enum EnvLoader {
    static func readKeyValues() -> [String: String] {
        var merged = ProcessInfo.processInfo.environment

        for candidate in candidateEnvContents() {
            let parsed = parseEnv(contents: candidate)
            for (key, value) in parsed {
                merged[key] = value
            }
        }

        return merged
    }

    private static func candidateEnvContents() -> [String] {
        var files: [String] = []
        let resourceNames = [".env", "env"]

        for resourceName in resourceNames {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: nil),
               let content = try? String(contentsOf: url) {
                files.append(content)
            }
        }

        if let bundleResources = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: nil) {
            for fileURL in bundleResources where fileURL.lastPathComponent == ".env" {
                if let content = try? String(contentsOf: fileURL) {
                    files.append(content)
                }
            }
        }

        for fileURL in candidateFileSystemEnvURLs() {
            if let content = try? String(contentsOf: fileURL) {
                files.append(content)
            }
        }

        return files
    }

    private static func candidateFileSystemEnvURLs() -> [URL] {
        var urls: [URL] = []

        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        urls.append(currentDirectoryURL.appendingPathComponent(".env"))
        urls.append(currentDirectoryURL.appendingPathComponent("env"))

        // In local development, #filePath points into the project tree.
        // .../eventBuilder360/eventBuilder360/ContentView.swift -> repo root is two levels up.
        let sourceURL = URL(fileURLWithPath: #filePath)
        let repoRootURL = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        urls.append(repoRootURL.appendingPathComponent(".env"))
        urls.append(repoRootURL.appendingPathComponent("env"))
        urls.append(repoRootURL.appendingPathComponent("eventBuilder360/.env"))
        urls.append(repoRootURL.appendingPathComponent("eventBuilder360/env"))

        return urls
    }

    private static func parseEnv(contents: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
        return values
    }
}

enum SupabaseConfig {
    static func load() throws -> SupabaseEnvironment {
        let values = EnvLoader.readKeyValues()

        guard let rawURL = values["SUPABASE_URL"], let url = URL(string: rawURL) else {
            throw ConfigError.missing("SUPABASE_URL")
        }
        guard let publishable = values["SUPABASE_PUBLISHABLE_KEY"], !publishable.isEmpty else {
            throw ConfigError.missing("SUPABASE_PUBLISHABLE_KEY")
        }
        return SupabaseEnvironment(url: url, publishableKey: publishable)
    }

    enum ConfigError: LocalizedError {
        case missing(String)

        var errorDescription: String? {
            switch self {
            case .missing(let key):
                return "Missing \(key). Add it to environment vars or bundle .env."
            }
        }
    }
}

struct SupabaseEventService {
    func fetchEvents() async throws -> [EventRecord] {
        let config = try SupabaseConfig.load()
        let endpoint = config.url
            .appending(path: "rest/v1/events")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "id,created_at,name"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ])

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([EventRecord].self, from: data)
    }
}

struct EventActivityRecord: Identifiable, Decodable, Hashable {
    let id: Int64
    let eventID: Int64
    let createdAt: Date
    let title: String
    let activityDescription: String
    let startTimeLocal: Date
    let endTimeLocal: Date?
    let timezone: String
    let locationName: String
    let speakers: String
    let activityType: String
    let roomCapacity: Int
    let registeredUsers: Int
    let scannedInUsers: Int
    let queueLength: Int

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case createdAt = "created_at"
        case title
        case activityDescription = "description"
        case startTimeLocal = "start_time_local"
        case endTimeLocal = "end_time_local"
        case timezone
        case locationName = "location_name"
        case speakers
        case activityType = "activity_type"
        case roomCapacity = "room_capacity"
        case registeredUsers = "registered_users"
        case scannedInUsers = "scanned_in_users"
        case queueLength = "queue_length"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        eventID = try container.decode(Int64.self, forKey: .eventID)
        title = try container.decode(String.self, forKey: .title)
        activityDescription = try container.decodeIfPresent(String.self, forKey: .activityDescription) ?? ""
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone) ?? TimeZone.current.identifier
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName) ?? "TBD"
        speakers = try container.decodeIfPresent(String.self, forKey: .speakers) ?? ""
        activityType = try container.decodeIfPresent(String.self, forKey: .activityType) ?? "General"
        roomCapacity = try container.decodeIfPresent(Int.self, forKey: .roomCapacity) ?? 0
        registeredUsers = try container.decodeIfPresent(Int.self, forKey: .registeredUsers) ?? 0
        scannedInUsers = try container.decodeIfPresent(Int.self, forKey: .scannedInUsers) ?? 0
        queueLength = try container.decodeIfPresent(Int.self, forKey: .queueLength) ?? 0

        let createdAtRaw = try container.decode(String.self, forKey: .createdAt)
        createdAt = try Self.parseAPIDate(createdAtRaw, in: container, key: .createdAt)

        let startTimeRaw = try container.decode(String.self, forKey: .startTimeLocal)
        startTimeLocal = try Self.parseAPIDate(startTimeRaw, in: container, key: .startTimeLocal)

        if let endTimeRaw = try container.decodeIfPresent(String.self, forKey: .endTimeLocal), !endTimeRaw.isEmpty {
            endTimeLocal = try Self.parseAPIDate(endTimeRaw, in: container, key: .endTimeLocal)
        } else {
            endTimeLocal = nil
        }
    }

    private static func parseAPIDate(
        _ rawValue: String,
        in container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Date {
        if let parsed = DateParsers.iso8601WithFractional.date(from: rawValue) ?? DateParsers.iso8601.date(from: rawValue) {
            return parsed
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Could not parse date: \(rawValue)"
        )
    }
}

struct EventActivityInsert: Encodable {
    let event_id: Int64
    let title: String
    let description: String
    let start_time_local: String
    let end_time_local: String?
    let timezone: String
    let location_name: String
    let speakers: String
    let activity_type: String
    let source: String
    let created_by_display: String?
}

struct SupabaseActivityService {
    func fetchActivities(eventID: Int64) async throws -> [EventActivityRecord] {
        let config = try SupabaseConfig.load()
        let endpoint = config.url
            .appending(path: "rest/v1/eventActivities")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "id,event_id,created_at,title,description,start_time_local,end_time_local,timezone,location_name,speakers,activity_type,room_capacity,registered_users,scanned_in_users,queue_length"),
                URLQueryItem(name: "event_id", value: "eq.\(eventID)"),
                URLQueryItem(name: "order", value: "start_time_local.asc")
            ])

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([EventActivityRecord].self, from: data)
    }

    func createActivity(_ payload: EventActivityInsert) async throws -> EventActivityRecord {
        let config = try SupabaseConfig.load()
        let endpoint = config.url.appending(path: "rest/v1/eventActivities")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let inserted = try JSONDecoder().decode([EventActivityRecord].self, from: data)
        guard let record = inserted.first else {
            throw URLError(.cannotParseResponse)
        }

        return record
    }
}

enum DateParsers {
    static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum ActivityDateFormatter {
    static let dateAndTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

@MainActor
final class EventDirectoryViewModel: ObservableObject {
    @Published private(set) var events: [EventRecord] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service = SupabaseEventService()

    func loadEvents() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            events = try await service.fetchEvents()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class EventActivitiesViewModel: ObservableObject {
    @Published private(set) var activities: [EventActivityRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let eventID: Int64
    private let service = SupabaseActivityService()

    init(eventID: Int64) {
        self.eventID = eventID
    }

    func loadActivities() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            activities = try await service.fetchActivities(eventID: eventID)
        } catch {
            errorMessage = "Could not load activities. \(error.localizedDescription)"
        }
    }

    func addActivity(_ input: ActivityFormInput) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let payload = EventActivityInsert(
            event_id: eventID,
            title: input.title,
            description: input.description,
            start_time_local: DateParsers.iso8601WithFractional.string(from: input.startTimeLocal),
            end_time_local: input.endTimeLocal.map { DateParsers.iso8601WithFractional.string(from: $0) },
            timezone: input.timezone,
            location_name: input.locationName,
            speakers: input.speakers,
            activity_type: input.activityType,
            source: "user_added",
            created_by_display: nil
        )

        do {
            let inserted = try await service.createActivity(payload)
            activities.append(inserted)
            activities.sort { $0.startTimeLocal < $1.startTimeLocal }
            return true
        } catch {
            errorMessage = "Could not save activity. \(error.localizedDescription)"
            return false
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                EventDirectoryView()
            }
            .tabItem {
                Label("Events", systemImage: "calendar")
            }
        }
        .tint(.mint)
        .preferredColorScheme(.dark)
    }
}

struct EventDirectoryView: View {
    @StateObject private var viewModel = EventDirectoryViewModel()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            Image("WideLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.horizontal, 12)

            Text("Event Directory")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 4)

            if viewModel.isLoading {
                ProgressView("Loading events...")
                    .tint(.mint)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 48)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.events) { event in
                        NavigationLink(value: event) {
                            EventTile(title: event.name, icon: "calendar.badge.clock")
                        }
                        .buttonStyle(.plain)
                    }

                    AddEventPlaceholderTile()
                }
                .padding()
            }
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.05, blue: 0.08), Color(red: 0.01, green: 0.02, blue: 0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationDestination(for: EventRecord.self) { event in
            EventHomeView(event: event)
        }
        .overlay(alignment: .bottom) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.red.opacity(0.95))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.4))
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .task {
            await viewModel.loadEvents()
        }
    }
}

struct EventTile: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.mint)
            Text(title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.white.opacity(0.95))
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

struct AddEventPlaceholderTile: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.75))
            Text("Add Event")
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(.white.opacity(0.35))
        )
        .accessibilityLabel("Add Event placeholder")
    }
}

struct EventHomeView: View {
    let event: EventRecord
    @StateObject private var viewModel: EventActivitiesViewModel
    @State private var showingAddSheet = false

    init(event: EventRecord) {
        self.event = event
        _viewModel = StateObject(wrappedValue: EventActivitiesViewModel(eventID: event.id))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Text("SXSW 2026 Activities")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                if viewModel.isLoading && viewModel.activities.isEmpty {
                    ProgressView("Loading activities...")
                        .tint(.mint)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                }

                if !viewModel.isLoading && viewModel.activities.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.75))
                        Text("No activities yet")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.92))
                        Text("Tap Add to create the first activity.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.05))
                    )
                }

                ForEach(viewModel.activities) { activity in
                    NavigationLink(value: activity) {
                        ActivityCardView(activity: activity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationDestination(for: EventActivityRecord.self) { activity in
            ActivityDetailView(activity: activity)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Activity", systemImage: "plus.circle.fill")
                }
                .tint(.mint)
            }
        }
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.06, blue: 0.09), Color(red: 0.01, green: 0.02, blue: 0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.red.opacity(0.95))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.4))
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NavigationStack {
                AddActivityView(
                    isSaving: viewModel.isSaving,
                    onSave: { input in
                        await viewModel.addActivity(input)
                    }
                )
            }
            .presentationDetents([.large])
        }
        .task {
            await viewModel.loadActivities()
        }
    }
}

struct ActivityFormInput {
    let title: String
    let description: String
    let startTimeLocal: Date
    let endTimeLocal: Date?
    let timezone: String
    let locationName: String
    let speakers: String
    let activityType: String
}

struct ActivityCardView: View {
    let activity: EventActivityRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(activity.title)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.96))
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(activity.activityType)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.mint.opacity(0.25)))
                        .foregroundStyle(.mint)

                    Text(activity.capacityStatus.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(activity.capacityStatus.color.opacity(0.2)))
                        .foregroundStyle(activity.capacityStatus.color)
                }
            }

            Label(activity.timeSummary, systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))

            Label(activity.locationName, systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))

            if !activity.speakers.isEmpty {
                Label(activity.speakers, systemImage: "person.2.fill")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
            }

            Divider()
                .overlay(Color.white.opacity(0.12))

            HStack(spacing: 12) {
                CardMetric(label: "Capacity", value: "\(activity.scannedInUsers) / \(activity.roomCapacity)")
                CardMetric(label: "Registered", value: "\(activity.registeredUsers)")
                CardMetric(label: "Queue", value: "\(activity.queueLength)")
            }

            if activity.queueLength > 0 {
                Label(activity.estimatedWaitLabel, systemImage: "timer")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

struct CardMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActivityDetailView: View {
    let activity: EventActivityRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(activity.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.96))

                DetailRow(icon: "tag.fill", label: "Type", value: activity.activityType)
                DetailRow(icon: "clock.fill", label: "When", value: activity.timeSummary)
                DetailRow(icon: "globe", label: "Timezone", value: activity.timezone)
                DetailRow(icon: "mappin.and.ellipse", label: "Location", value: activity.locationName)
                DetailRow(icon: "person.2.fill", label: "Speakers", value: activity.speakers.isEmpty ? "TBD" : activity.speakers)
                DetailRow(icon: "circle.inset.filled", label: "Status", value: activity.capacityStatus.title)
                DetailRow(icon: "person.3.fill", label: "Room Capacity", value: "\(activity.roomCapacity)")
                DetailRow(icon: "person.crop.rectangle", label: "Registered Users", value: "\(activity.registeredUsers)")
                DetailRow(icon: "checkmark.seal.fill", label: "Scanned-In Users", value: "\(activity.scannedInUsers)")
                DetailRow(icon: "line.3.horizontal.decrease.circle", label: "Queue Length", value: "\(activity.queueLength)")
                DetailRow(icon: "timer", label: "Estimated Wait", value: activity.estimatedWaitLabel)

                Text("Description")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.top, 8)

                Text(activity.activityDescription.isEmpty ? "No description added yet." : activity.activityDescription)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle("Activity Details")
        .navigationBarTitleDisplayMode(.inline)
        .background(
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.06, blue: 0.09), Color(red: 0.01, green: 0.02, blue: 0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.mint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                Text(value)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
    }
}

struct AddActivityView: View {
    @Environment(\.dismiss) private var dismiss

    let isSaving: Bool
    let onSave: (ActivityFormInput) async -> Bool

    @State private var title = ""
    @State private var details = ""
    @State private var locationName = ""
    @State private var speakers = ""
    @State private var activityType = "Workshop"
    @State private var startTime = Date()
    @State private var hasEndTime = false
    @State private var endTime = Date().addingTimeInterval(60 * 60)
    @State private var validationMessage: String?

    var body: some View {
        Form {
            Section("Overview") {
                TextField("Title *", text: $title)
                TextField("Type * (e.g. Keynote, Music, Film)", text: $activityType)
                TextField("Location *", text: $locationName)
                TextField("Speakers (text)", text: $speakers)
            }

            Section("Time") {
                DatePicker("Start (local) *", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                Toggle("Add end time (optional)", isOn: $hasEndTime)
                if hasEndTime {
                    DatePicker("End (local)", selection: $endTime, displayedComponents: [.date, .hourAndMinute])
                }
            }

            Section("Description") {
                TextEditor(text: $details)
                    .frame(minHeight: 120)
            }

            if let validationMessage {
                Section {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await submit() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving)
            }
        }
    }

    private func submit() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedType = activityType.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            validationMessage = "Title is required."
            return
        }
        guard !trimmedLocation.isEmpty else {
            validationMessage = "Location is required."
            return
        }
        guard !trimmedType.isEmpty else {
            validationMessage = "Type is required."
            return
        }
        if hasEndTime && endTime < startTime {
            validationMessage = "End time must be after start time."
            return
        }

        validationMessage = nil
        let input = ActivityFormInput(
            title: trimmedTitle,
            description: details.trimmingCharacters(in: .whitespacesAndNewlines),
            startTimeLocal: startTime,
            endTimeLocal: hasEndTime ? endTime : nil,
            timezone: TimeZone.current.identifier,
            locationName: trimmedLocation,
            speakers: speakers.trimmingCharacters(in: .whitespacesAndNewlines),
            activityType: trimmedType
        )

        let didSave = await onSave(input)
        if didSave {
            dismiss()
        } else {
            validationMessage = "Could not save activity. Please try again."
        }
    }
}

private extension EventActivityRecord {
    var timeSummary: String {
        let start = ActivityDateFormatter.dateAndTime.string(from: startTimeLocal)
        guard let endTimeLocal else {
            return start
        }
        let end = ActivityDateFormatter.timeOnly.string(from: endTimeLocal)
        return "\(start) - \(end)"
    }

    var capacityStatus: CapacityStatus {
        guard roomCapacity > 0 else { return .unknown }

        if scannedInUsers >= roomCapacity {
            return queueLength > 0 ? .queueing : .full
        }

        let scannedRatio = Double(scannedInUsers) / Double(roomCapacity)
        if scannedRatio >= 0.8 {
            return .limited
        }
        return .available
    }

    var estimatedWaitLabel: String {
        guard queueLength > 0 else { return "No queue" }

        // Prototype heuristic: roughly 2 minutes per person in queue.
        let estimatedMinutes = max(2, queueLength * 2)
        return "~\(estimatedMinutes) mins"
    }
}

private enum CapacityStatus {
    case available
    case limited
    case full
    case queueing
    case unknown

    var title: String {
        switch self {
        case .available:
            return "Available"
        case .limited:
            return "Limited"
        case .full:
            return "Full"
        case .queueing:
            return "Queueing"
        case .unknown:
            return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .available:
            return .green
        case .limited:
            return .orange
        case .full:
            return .red
        case .queueing:
            return .purple
        case .unknown:
            return .gray
        }
    }
}

#Preview {
    ContentView()
}
