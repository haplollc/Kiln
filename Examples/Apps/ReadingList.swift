import SwiftUI

enum Genre: String, CaseIterable, Identifiable {
    case fiction = "Fiction"
    case science = "Science"
    case history = "History"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fiction: return "sparkles"
        case .science: return "atom"
        case .history: return "building.columns"
        }
    }
}

struct Book: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var author: String
    var genre: Genre
    var pages: Int
    var isFinished = false
    var rating = 0
}

final class Library: ObservableObject {
    @Published var books: [Book] = [
        Book(title: "Dune", author: "Frank Herbert", genre: .fiction, pages: 412, isFinished: true, rating: 5),
        Book(title: "Cosmos", author: "Carl Sagan", genre: .science, pages: 396),
        Book(title: "SPQR", author: "Mary Beard", genre: .history, pages: 608),
        Book(title: "Project Hail Mary", author: "Andy Weir", genre: .fiction, pages: 496),
        Book(title: "The Gene", author: "Siddhartha Mukherjee", genre: .science, pages: 592, isFinished: true, rating: 4)
    ]

    var finished: [Book] { books.filter { $0.isFinished } }

    var pagesRead: Int { finished.reduce(0) { $0 + $1.pages } }

    func index(of book: Book) -> Int? {
        books.firstIndex { $0.id == book.id }
    }
}

struct ContentView: View {
    @StateObject private var library = Library()

    var body: some View {
        TabView {
            LibraryTab(library: library)
                .tabItem { Label("Library", systemImage: "books.vertical") }
            StatsTab(library: library)
                .tabItem { Label("Stats", systemImage: "chart.bar") }
        }
    }
}

struct LibraryTab: View {
    @ObservedObject var library: Library
    @State private var search = ""

    private var results: [Book] {
        search.isEmpty ? library.books : library.books.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.author.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Genre.allCases) { genre in
                    let books = results.filter { $0.genre == genre }
                    if !books.isEmpty {
                        Section {
                            ForEach(books) { book in
                                NavigationLink(value: book) {
                                    BookRow(book: book)
                                }
                            }
                        } header: {
                            Label(genre.rawValue, systemImage: genre.icon)
                        }
                    }
                }
            }
            .navigationTitle("Reading List")
            .searchable(text: $search, prompt: "Title or author")
            .navigationDestination(for: Book.self) { book in
                BookDetail(library: library, bookID: book.id)
            }
        }
    }
}

struct BookRow: View {
    let book: Book

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.headline)
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if book.isFinished {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Finished")
            }
        }
    }
}

struct BookDetail: View {
    @ObservedObject var library: Library
    let bookID: UUID

    private var index: Int? {
        library.books.firstIndex { $0.id == bookID }
    }

    var body: some View {
        if let i = index {
            Form {
                Section {
                    LabeledContent("Author", value: library.books[i].author)
                    LabeledContent("Pages", value: "\(library.books[i].pages)")
                    LabeledContent("Genre", value: library.books[i].genre.rawValue)
                }
                Section("Progress") {
                    Toggle("Finished", isOn: $library.books[i].isFinished)
                    Stepper("Rating: \(String(repeating: "★", count: library.books[i].rating))\(String(repeating: "☆", count: 5 - library.books[i].rating))",
                            value: $library.books[i].rating, in: 0...5)
                }
            }
            .navigationTitle(library.books[i].title)
        } else {
            Text("Book not found")
        }
    }
}

struct StatsTab: View {
    @ObservedObject var library: Library

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(library.finished.count) of \(library.books.count) books finished")
                            .font(.headline)
                        ProgressView(value: Double(library.finished.count), total: Double(library.books.count))
                            .tint(.green)
                        Text("\(library.pagesRead) pages read")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section("By genre") {
                    ForEach(Genre.allCases) { genre in
                        let all = library.books.filter { $0.genre == genre }
                        let done = all.filter { $0.isFinished }.count
                        LabeledContent {
                            Text("\(done)/\(all.count)")
                        } label: {
                            Label(genre.rawValue, systemImage: genre.icon)
                        }
                    }
                }
            }
            .navigationTitle("Stats")
        }
    }
}
