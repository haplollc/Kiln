// A live search of the Open Library API, run by Kiln on device:
// URLSession, JSONDecoder with .convertFromSnakeCase and with CodingKeys,
// decoded into this file's own Decodable types. Needs a network connection.
import SwiftUI

struct SearchResponse: Decodable {
    let numFound: Int
    let docs: [Doc]
}

struct Doc: Decodable, Identifiable {
    let key: String
    let title: String
    let authorName: [String]?
    let firstPublishYear: Int?
    var id: String { key }
}

struct Work: Decodable {
    let title: String
    let pages: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case pages = "number_of_pages_median"
    }
}

struct ContentView: View {
    @State private var docs: [Doc] = []
    @State private var total = 0
    @State private var first: Work?
    @State private var message = "Loading…"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(message)
                    if let first {
                        Text("CodingKeys: \(first.title), \(first.pages ?? 0) pages")
                    }
                }
                Section("Results") {
                    ForEach(docs) { doc in
                        VStack(alignment: .leading) {
                            Text(doc.title).font(.headline)
                            Text("\(doc.authorName?.first ?? "Unknown") · \(doc.firstPublishYear.map(String.init) ?? "?")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Open Library")
            .task { await load() }
        }
    }

    func load() async {
        do {
            let url = URL(string: "https://openlibrary.org/search.json?title=dune&limit=5&fields=key,title,author_name,first_publish_year,number_of_pages_median")!
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(SearchResponse.self, from: data)
            docs = result.docs
            total = result.numFound
            message = "HTTP \(status), \(total) found, showing \(docs.count)"
            struct Wrapper: Decodable { let docs: [Work] }
            first = try JSONDecoder().decode(Wrapper.self, from: data).docs.first
        } catch {
            message = "Failed: \(error.localizedDescription)"
        }
    }
}
