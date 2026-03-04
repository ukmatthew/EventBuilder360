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

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.circle.fill")
                .font(.system(size: 68))
                .foregroundStyle(.mint)
            Text("To be built in the SXSW Vibe Programming workshop")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .foregroundStyle(.white.opacity(0.95))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.black)
    }
}

#Preview {
    ContentView()
}
