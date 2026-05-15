import SwiftUI

// MARK: - Wire-format models (Open Library responses)

struct OpenLibraryResponse: Decodable {
    let docs: [OpenLibraryDoc]
}

struct OpenLibraryDoc: Decodable {
    let key: String
    let title: String
    let author_name: [String]?
    let first_publish_year: Int?
    let cover_i: Int?
    let isbn: [String]?
}


struct LibraryView: View {
    @State private var books: [Book] = []

    var body: some View {
        NavigationStack {
            ForEach(books) { book in
                NavigationLink(destination: BookDetailView(book: book)) {
                    Text(book.title)
                }
            }
        }
    }
}

struct Book: Identifiable {
    let id: String
    let title: String
}

struct BookDetailView: View {
    let book: Book
    var body: some View {
        Text(book.title).font(.largeTitle)
    }
}


// Work details — https://openlibrary.org/works/{KEY}.json
// Open Library returns `description` as either a plain string OR an object
// with a `value` field, depending on the work. The SwiftRunner interpreter
// doesn't yet accept the two-name init signature `init(from decoder: Decoder)`
// required by Decodable, and `JSONSerialization.jsonObject` isn't bridged
// as a user-callable static either, so we use JSONDecoder twice with two
// trivial models — the second is a fallback for the wrapped form.
struct OpenLibraryWork: Decodable {
    let title: String?
    let description: String?
    let subjects: [String]?
}

/// Wrapped `description` field shape — used when the API returns
/// `{"description": {"value": "…"}}` instead of a plain string.
/// Hoisted to top-level because the SwiftRunner interpreter doesn't yet
/// support nested type declarations inside another struct.
struct OpenLibraryDescriptionObject: Decodable {
    let value: String?
}

/// Fallback decoder shape — the full work decoded with `description` as
/// the wrapped object form (`{"value": "...", "type": "/type/text"}`).
/// We carry `title` and `subjects` here too so we don't need to merge with
/// a second decode when this shape wins.
struct OpenLibraryWorkObjectDesc: Decodable {
    let title: String?
    let description: OpenLibraryDescriptionObject?
    let subjects: [String]?
}

// MARK: - Display model

struct Book: Identifiable, Hashable {
    let id: String
    let title: String
    let author: String
    let year: String
    let coverURL: URL?
}

// MARK: - Networking — title search only

enum BookService {
    /// Title search — https://openlibrary.org/search.json?title=…&limit=12
    /// `title=` matches book titles only (vs. `q=` which also matches authors,
    /// subjects, etc.), so typing "harry potter" returns Harry Potter books.
    static func search(title: String) async throws -> [OpenLibraryDoc] {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var comps = URLComponents(string: "https://openlibrary.org/search.json")!
        comps.queryItems = [
            URLQueryItem(name: "title", value: trimmed),
            URLQueryItem(name: "limit", value: "12"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        return try JSONDecoder().decode(OpenLibraryResponse.self, from: data).docs
    }

    /// Work details — https://openlibrary.org/works/OL…W.json
    static func details(workKey: String) async throws -> OpenLibraryWork {
        let url = URL(string: "https://openlibrary.org\(workKey).json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let wrapped = try? JSONDecoder().decode(OpenLibraryWorkObjectDesc.self, from: data)
        if let w = wrapped {
            if let inner = w.description {
            }
        }
        if let wrapped = wrapped,
           let value = wrapped.description?.value, !value.isEmpty {
            return OpenLibraryWork(
                title: wrapped.title,
                description: value,
                subjects: wrapped.subjects
            )
        }
        let primary = try JSONDecoder().decode(OpenLibraryWork.self, from: data)
        return primary
    }
}

// MARK: - Helpers (top-level free functions; the interpreter doesn't yet
// support `let x: T = { ... }()` IIFEs or `Int.map(String.init)` keypath-init)

private func coverURLFor(doc: OpenLibraryDoc) -> URL? {
    if let id = doc.cover_i {
        return URL(string: "https://covers.openlibrary.org/b/id/\(id)-M.jpg")
    }
    if let isbn = doc.isbn?.first {
        return URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-M.jpg")
    }
    return nil
}

private func yearStringFor(doc: OpenLibraryDoc) -> String {
    if let y = doc.first_publish_year { return "\(y)" }
    return "—"
}

private func mergeBooks(docs: [OpenLibraryDoc]) -> [Book] {
    // Deduplicate by title (case-insensitive). Open Library often returns
    // multiple editions/works with the same title for a single search — we
    // want only the first occurrence of each title in the grid. We track
    // seen titles in an array captured by the closure (the SwiftRunner
    // interpreter doesn't support `for x in collection` loops in user code,
    // so we lean on `compactMap` + closure capture instead).
    var seenTitles: [String] = []
    return docs.compactMap { doc in
        let key = doc.title.lowercased()
        if seenTitles.contains(key) { return nil }
        seenTitles.append(key)
        return Book(
            id: doc.key,
            title: doc.title,
            author: doc.author_name?.first ?? "Unknown author",
            year: yearStringFor(doc: doc),
            coverURL: coverURLFor(doc: doc)
        )
    }
}

// MARK: - Card

struct BookCard: View {
    let book: Book

    // Hardcoded thumbnail size — small cover on the left of the text.
    // 2:3 aspect (matches Open Library's default cover ratio).
    private let coverWidth: CGFloat = 56
    private let coverHeight: CGFloat = 84

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: book.coverURL) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.18))
                        .frame(width: coverWidth, height: coverHeight)
                case .success(let image):
                    // Hard-cap the size INSIDE the success branch so the
                    // loaded image can never burst past the thumbnail
                    // dimensions, even if the AsyncImage's outer frame is
                    // bypassed by the layout. `.scaledToFill().clipped()`
                    // crops covers whose aspect ratio differs from 2:3.
                    image.resizable()
                        .scaledToFill()
                        .frame(width: coverWidth, height: coverHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                case .failure:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.clear)
                        .frame(width: coverWidth, height: coverHeight)
                        .overlay(
                            Image(systemName: "photo.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        )
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: coverWidth, height: coverHeight)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(book.year)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Main view

struct LibraryApp: View {
    @State private var books: [Book] = []
    @State private var query: String = ""
    @State private var isLoading = false
    /// Monotonically incremented per `load()` invocation. The async resume
    /// after `await` only commits state if `mySeq == requestSeq`, so stale
    /// completions from cancelled / overtaken searches drop silently
    /// instead of clobbering the latest results.
    @State private var requestSeq: Int = 0

    // Single column — each book is a horizontal HStack card spanning the row.
    private let columns = [GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    content
                }
                .padding(.vertical)
            }
            // Drop the keyboard interactively as the user scrolls results,
            // matching the standard iOS search-screen behavior.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Library")
        }
        // SwiftUI's `.task(id:)` cancels any in-flight task and starts a new
        // one whenever the ID changes. Typing a character mutates `query` →
        // SwiftUI cancels the previous load (URLSession.data propagates the
        // cancellation) and runs `load()` for the new query. Only one task
        // is alive at a time, so no races on `books` / `isLoading`.
        .task(id: query) {
            await load()
        }
    }

    // MARK: Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Discover")
                .font(.largeTitle.bold())
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by title…", text: $query)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var content: some View {
        if query.isEmpty {
            emptyState(message: "Search for a book by title to get started.")
        } else if isLoading {
            // Loading state: a centered spinner. Books were cleared at the
            // start of `load()`, so nothing stale is shown alongside it.
            VStack(spacing: 12) {
                ProgressView()
                Text("Searching…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else if books.isEmpty {
            emptyState(message: "No results for \"\(query)\".")
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(books) { book in
                    NavigationLink(destination: BookDetailPage(book: book)) {
                        BookCard(book: book)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func emptyState(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: Orchestration

    @MainActor
    private func load() async {
        requestSeq += 1
        let mySeq = requestSeq

        // New request kicks in: clear stale results and show a spinner.
        books = []

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isLoading = false
            return
        }

        isLoading = true

        do {
            let docs = try await BookService.search(title: trimmed)
            // Race / cancellation guard: another search has already started.
            // Drop our results to avoid flicker and stale "Show more" counts.
            guard mySeq == requestSeq else { return }
            books = mergeBooks(docs: docs)
            isLoading = false
        } catch {
            guard mySeq == requestSeq else { return }
            books = []
            isLoading = false
        }
    }
}

// MARK: - Detail page

struct BookDetailPage: View {
    let book: Book

    @State private var work: OpenLibraryWork?
    // Default to true so the spinner appears immediately on first render,
    // before `.task` has had a chance to fire and flip it on.
    @State private var isLoading = true
    @State private var loadFailed = false

    private let coverWidth: CGFloat = 160
    private let coverHeight: CGFloat = 240

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                cover
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.title2.bold())
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("First published \(book.year)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                details
            }
            .padding()
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetails()
        }
    }

    private var cover: some View {
        AsyncImage(url: book.coverURL) { phase in
            switch phase {
            case .empty:
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.18))
                    .frame(width: coverWidth, height: coverHeight)
            case .success(let image):
                image.resizable()
                    .scaledToFill()
                    .frame(width: coverWidth, height: coverHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            case .failure:
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: coverWidth, height: coverHeight)
                    .overlay(
                        Image(systemName: "photo.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    )
            @unknown default:
                EmptyView()
            }
        }
        .frame(width: coverWidth, height: coverHeight)
    }

    @ViewBuilder
    private var details: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading details…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if loadFailed {
            Text("Couldn't load details.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if let work {
            VStack(alignment: .leading, spacing: 16) {
                if let description = work.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.headline)
                        Text(description)
                            .font(.body)
                    }
                }

                if let subjects = work.subjects, !subjects.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Subjects")
                            .font(.headline)
                        Text(subjects.prefix(10).joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @MainActor
    private func loadDetails() async {
        guard work == nil else { return }
        loadFailed = false
        do {
            work = try await BookService.details(workKey: book.id)
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}

#Preview {
    LibraryApp()
}
