//
//  ParserFoundationTests.swift
//  SwiftRunnerTests
//
//  Tests for Plan 1 — parser foundation. New Swift keywords, attributes,
//  switch/case, do/catch, try/throw, guard, defer, enum, extension, keypaths,
//  multi-conformance, computed properties.
//
//  See: docs/superpowers/plans/2026-04-21-swiftrunner-1-parser-foundation.md
//

import XCTest
@testable import Kiln

final class ParserFoundationTests: XCTestCase {
    private let parser = SwiftParser()

    private func tokenize(_ code: String) throws -> [Token] {
        try SwiftLexer(source: code).tokenize()
    }

    private func parse(_ code: String) throws -> ViewNode {
        try parser.parse(tokenize(code))
    }

    // MARK: - Task 1: new keywords & attribute tokens

    func testLexRecognizesNewKeywords() throws {
        let src = "switch case default do catch try throws throw guard defer enum extension protocol async await"
        let tokens = try tokenize(src)
        let expected: [Keyword] = [
            .switch, .case, .default, .do, .catch, .try, .throws, .throw,
            .guard, .defer, .enum, .extension, .protocol, .async, .await
        ]
        for (i, kw) in expected.enumerated() {
            XCTAssertEqual(
                tokens[i].type, .keyword(kw),
                "Token \(i) expected .keyword(.\(kw)) but got \(tokens[i].type)"
            )
        }
    }

    func testLexRecognizesAttributePrefix() throws {
        let tokens = try tokenize("@MainActor func foo() {}")
        guard case .attribute(let name) = tokens[0].type else {
            XCTFail("Expected .attribute token at position 0, got \(tokens[0].type)")
            return
        }
        XCTAssertEqual(name, "MainActor")
        XCTAssertEqual(tokens[1].type, .keyword(.func))
    }

    func testLexAttributeWithParenthesizedArgsSwallowsArgs() throws {
        // @available(iOS 15, *) — parenthesized args should be consumed by the lexer
        // so downstream parsers see a clean attribute marker.
        let tokens = try tokenize("@available(iOS 15, *) func foo() {}")
        guard case .attribute(let name) = tokens[0].type else {
            XCTFail("Expected .attribute token, got \(tokens[0].type)")
            return
        }
        XCTAssertEqual(name, "available")
        XCTAssertEqual(tokens[1].type, .keyword(.func))
    }

    // MARK: - Task 2: switch statement parsing

    func testParsesSwitchStatementWithEnumCases() throws {
        let code = """
        switch phase {
        case .empty:
            ProgressView()
        case .success(let image):
            image.resizable()
        case .failure:
            Text("failed")
        @unknown default:
            EmptyView()
        }
        """
        let node = try parse(code)
        guard case .switchStmt(let scrutinee, let cases, let defaultBody) = node else {
            XCTFail("Expected .switchStmt, got \(node)"); return
        }
        XCTAssertEqual(scrutinee, .variable("phase"))
        XCTAssertEqual(cases.count, 3)
        XCTAssertEqual(cases[0].pattern, .caseMember(name: "empty", bindings: []))
        XCTAssertEqual(cases[1].pattern, .caseMember(name: "success", bindings: ["image"]))
        XCTAssertEqual(cases[2].pattern, .caseMember(name: "failure", bindings: []))
        XCTAssertNotNil(defaultBody)
    }

    @MainActor
    func testSwitchStatementEvaluatesMatchingStringCase() throws {
        let state = SwiftRunnerState(["phase": .string("empty")])
        let code = """
        switch phase { case "empty": 1 case "success": 2 default: 0 }
        """
        let node = try parse(code)
        let value = state.evaluate(node)
        XCTAssertEqual(value, .number(1))
    }

    @MainActor
    func testSwitchStatementFallsThroughToDefault() throws {
        let state = SwiftRunnerState(["phase": .string("other")])
        let node = try parse("""
        switch phase { case "empty": 1 case "success": 2 default: 99 }
        """)
        XCTAssertEqual(state.evaluate(node), .number(99))
    }

    // MARK: - Task 3: do/catch, try, throw

    func testParsesDoCatchBlock() throws {
        let code = """
        do {
            try foo()
        } catch {
            print("err")
        }
        """
        let node = try parse(code)
        guard case .doCatch(_, let clauses) = node else {
            XCTFail("Expected .doCatch, got \(node)"); return
        }
        XCTAssertFalse(clauses.isEmpty)
    }

    func testTryPrefixSkipped() throws {
        // `try foo()` parses as just foo() — the `try` is transparent for now.
        let node = try parse("try foo()")
        if case .functionCall(let name, _) = node {
            XCTAssertEqual(name, "foo")
        } else {
            XCTFail("Expected function call, got \(node)")
        }
    }

    func testParsesThrowStatement() throws {
        let node = try parse("throw SomeError.bad")
        guard case .throwStmt = node else {
            XCTFail("Expected .throwStmt, got \(node)"); return
        }
    }

    // MARK: - Task 4: guard

    func testParsesGuardLetElseReturn() throws {
        let node = try parse("guard let x = y else { return }")
        guard case .guardLet(let name, _, _) = node else {
            XCTFail("Expected .guardLet, got \(node)"); return
        }
        XCTAssertEqual(name, "x")
    }

    func testParsesGuardExprElse() throws {
        let node = try parse("guard !isEmpty else { return }")
        guard case .guardExpr = node else {
            XCTFail("Expected .guardExpr, got \(node)"); return
        }
    }

    // MARK: - Task 5: defer

    func testParsesDeferBlock() throws {
        let node = try parse("defer { cleanup() }")
        guard case .deferBlock = node else {
            XCTFail("Expected .deferBlock, got \(node)"); return
        }
    }

    // MARK: - Task 6: enum declarations

    func testParsesEnumWithSimpleCases() throws {
        let node = try parse("""
        enum Phase {
            case empty
            case success
            case failure
        }
        """)
        guard case .enumDeclaration(let name, let cases, _) = node else {
            XCTFail("Expected .enumDeclaration, got \(node)"); return
        }
        XCTAssertEqual(name, "Phase")
        XCTAssertEqual(cases.map(\.name), ["empty", "success", "failure"])
    }

    func testParsesEnumWithStaticFunc() throws {
        let node = try parse("""
        enum BookService {
            static func fetch() async throws -> Int { return 1 }
        }
        """)
        guard case .enumDeclaration(let name, _, _) = node else {
            XCTFail("Expected .enumDeclaration, got \(node)"); return
        }
        XCTAssertEqual(name, "BookService")
    }

    // MARK: - Task 7: extension declarations

    func testParsesExtensionView() throws {
        let code = """
        extension View {
            func shimmer() -> some View { self.modifier(Shimmer()) }
        }
        """
        let node = try parse(code)
        guard case .extensionDeclaration(let target, _) = node else {
            XCTFail("Expected .extensionDeclaration, got \(node)"); return
        }
        XCTAssertEqual(target, "View")
    }

    // MARK: - Task 8: struct extensions — multi-conformance + computed properties

    func testParsesStructWithMultipleConformances() throws {
        // Any non-trivial struct here that multi-conforms should parse.
        XCTAssertNoThrow(try parse("""
        struct Book: Decodable, Identifiable, Hashable {
            let id: String
            let title: String
        }
        """))
    }

    func testParsesStructWithComputedProperty() throws {
        XCTAssertNoThrow(try parse("""
        struct Foo {
            var bar: String { return "hi" }
        }
        """))
    }

    // MARK: - Task 9: keypaths (\\.self, \\.prop, nested)

    func testKeypathLexedAsDotPrefix() throws {
        // Current lexer converts `\.` → `.` so `\.self` tokens are `.self`.
        // This test documents that behavior; it's enough for .compactMap(\.prop) usage
        // because the parser then reads `.prop` as an implicit-self property access.
        let tokens = try tokenize("\\.self")
        XCTAssertEqual(tokens[0].type, .dot)
        XCTAssertEqual(tokens[1].type, .keyword(.self))
    }

    // MARK: - Task 10: attributes on declarations

    func testAttributeBeforeFuncStatementIsConsumed() throws {
        // @MainActor should be consumed, then the func declaration parses normally.
        XCTAssertNoThrow(try parse("""
        @MainActor
        func load() async { }
        """))
    }

    func testAttributeBeforeComputedPropertyIsConsumed() throws {
        XCTAssertNoThrow(try parse("""
        struct Host {
            @ViewBuilder
            private var content: some View {
                Text("hi")
            }
        }
        """))
    }

    // MARK: - Task 11: full LibraryApp.swift fixture parses end-to-end

    func testLibraryAppFixtureParses() throws {
        // Inline fixture — mirrors ~/Desktop/LibraryApp.swift's shape at a smaller scale,
        // covering every new grammar form Plan 1 introduces.
        let code = """
        import SwiftUI

        struct OpenLibraryDoc: Decodable, Identifiable {
            let key: String
            let title: String
            var id: String { return key }
        }

        enum BookService {
            static func search(query: String) async throws -> [OpenLibraryDoc] {
                guard !query.isEmpty else { return [] }
                return []
            }
        }

        struct Shimmer: ViewModifier {
            func body(content: Content) -> some View {
                content
            }
        }

        extension View {
            func shimmer() -> some View { self.modifier(Shimmer()) }
        }

        struct LibraryApp: View {
            @State private var books: [OpenLibraryDoc] = []
            @State private var query: String = "harry potter"

            var body: some View {
                VStack {
                    Text(query)
                    ForEach(books) { book in
                        Text(book.title)
                    }
                }
                .task {
                    do {
                        let results = try await BookService.search(query: query)
                        books = results
                    } catch {
                        print("err")
                    }
                }
            }
        }
        """
        XCTAssertNoThrow(try parse(code))
    }

    // MARK: - Plan 2: user-defined functions

    func testParsesFunctionDeclarationWithParameters() throws {
        let node = try parse("""
        func greet(_ name: String, times count: Int) -> String {
            return name
        }
        """)
        guard case .functionDecl(let name, let params, _, _, _) = node else {
            XCTFail("Expected .functionDecl, got \(node)"); return
        }
        XCTAssertEqual(name, "greet")
        XCTAssertEqual(params.count, 2)
        XCTAssertNil(params[0].externalLabel)         // `_ name` → no external
        XCTAssertEqual(params[0].internalName, "name")
        XCTAssertEqual(params[1].externalLabel, "times")
        XCTAssertEqual(params[1].internalName, "count")
    }

    func testParsesAsyncThrowsFunctionSignature() throws {
        let node = try parse("""
        func search(query: String) async throws -> [Int] {
            return [1, 2, 3]
        }
        """)
        guard case .functionDecl(let name, _, _, let isAsync, let isThrowing) = node else {
            XCTFail("Expected .functionDecl, got \(node)"); return
        }
        XCTAssertEqual(name, "search")
        XCTAssertTrue(isAsync)
        XCTAssertTrue(isThrowing)
    }

    @MainActor
    func testRegisterAndCallTopLevelFunctionReturningLiteral() throws {
        let state = SwiftRunnerState()
        let decl = try parse("func answer() -> Int { return 42 }")
        state.execute(decl)
        XCTAssertNotNil(state.functions["answer"])

        let callNode = try parse("answer()")
        let result = state.evaluate(callNode)
        XCTAssertEqual(result, .number(42))
    }

    @MainActor
    func testUserFunctionBindsArgumentsToParameters() throws {
        let state = SwiftRunnerState()
        let decl = try parse("""
        func add(_ a: Int, _ b: Int) -> Int { return a + b }
        """)
        state.execute(decl)

        let callNode = try parse("add(3, 4)")
        let result = state.evaluate(callNode)
        XCTAssertEqual(result, .number(7))
    }

    @MainActor
    func testUserFunctionLabeledArgumentBindsCorrectly() throws {
        let state = SwiftRunnerState()
        let decl = try parse("""
        func greet(name: String) -> String { return name }
        """)
        state.execute(decl)

        let callNode = try parse("greet(name: \"hi\")")
        let result = state.evaluate(callNode)
        XCTAssertEqual(result, .string("hi"))
    }

    @MainActor
    func testEnumStaticFuncCallableViaDotDispatch() throws {
        let state = SwiftRunnerState()
        let decl = try parse("""
        enum Math {
            static func square(_ x: Int) -> Int { return x * x }
        }
        """)
        state.execute(decl)
        XCTAssertNotNil(state.functions["Math.square"])

        let callNode = try parse("Math.square(5)")
        let result = state.evaluate(callNode)
        XCTAssertEqual(result, .number(25))
    }

    @MainActor
    func testUserFunctionGuardLetEarlyReturn() throws {
        let state = SwiftRunnerState(["candidate": .string("hello")])
        let decl = try parse("""
        func mirror() -> String {
            guard let candidate = candidate else { return "fallback" }
            return candidate
        }
        """)
        state.execute(decl)

        XCTAssertEqual(state.evaluate(try parse("mirror()")), .string("hello"))

        state.variables["candidate"] = .nil
        XCTAssertEqual(state.evaluate(try parse("mirror()")), .string("fallback"))
    }

    // MARK: - Plan 3/4/6/8: Foundation + containers acceptance

    @MainActor
    func testForStateFullLibraryAppSwiftParsesAndRegisters() throws {
        // This is the real file from ~/Desktop/LibraryApp.swift — trimmed of some
        // modifiers the parser doesn't need to execute (still exercises every
        // major construct Plans 1-8 target).
        let code = """
        import SwiftUI

        struct OpenLibraryResponse: Decodable {
            let docs: [OpenLibraryDoc]
        }
        struct OpenLibraryDoc: Decodable {
            let key: String
            let title: String
        }

        enum BookService {
            static func search(query: String) async throws -> [OpenLibraryDoc] {
                guard !query.isEmpty else { return [] }
                var comps = URLComponents(string: "https://openlibrary.org/search.json")!
                let (data, _) = try await URLSession.shared.data(from: comps.url!)
                return try JSONDecoder().decode(OpenLibraryResponse.self, from: data).docs
            }
        }

        struct Shimmer: ViewModifier {
            @State private var phase: Double = -1
            func body(content: Content) -> some View {
                content
            }
        }
        extension View {
            func shimmer() -> some View { self.modifier(Shimmer()) }
        }

        struct BookCard: View {
            let book: OpenLibraryDoc
            var body: some View {
                VStack {
                    AsyncImage(url: URL(string: "https://example.com/img.jpg")) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 10).fill(Color.gray)
                        case .success(let image):
                            image.resizable()
                        case .failure:
                            Text("failed")
                        @unknown default:
                            EmptyView()
                        }
                    }
                    Text(book.title)
                }
            }
        }

        struct LibraryApp: View {
            @State private var books: [OpenLibraryDoc] = []
            @State private var query: String = "harry potter"
            private let columns = [GridItem(.adaptive(minimum: 130))]

            var body: some View {
                NavigationStack {
                    ZStack {
                        LinearGradient(colors: [.blue, .white], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea()
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(books) { book in
                                    BookCard(book: book)
                                }
                            }
                        }
                    }
                    .task {
                        do {
                            let results = try await BookService.search(query: query)
                            books = results
                        } catch { }
                    }
                }
            }
        }
        """
        XCTAssertNoThrow(try parse(code))

        // Parse once more and verify function table registration after SwiftRunner.run-style pipeline.
        let state = SwiftRunnerState()
        let ast = try parse(code)
        // Walk and register declarations manually (mirrors SwiftRunner.registerDeclarations).
        func register(_ node: ViewNode) {
            switch node {
            case .block(let stmts): stmts.forEach(register)
            case .functionDecl: state.execute(node)
            case .enumDeclaration, .extensionDeclaration: state.execute(node)
            default: break
            }
        }
        register(ast)
        XCTAssertNotNil(state.functions["BookService.search"], "enum static func should register")
        XCTAssertNotNil(state.functions["View.shimmer"], "extension func should register")
    }

    // MARK: - Plan 3/4: JSON decoding + Foundation built-ins

    @MainActor
    func testJSONDecoderDecodesBytesIntoNestedValue() throws {
        // Build a Data-shaped value manually, then decode through the JSONDecoder
        // built-in and assert property access walks the nested structure.
        let state = SwiftRunnerState()
        let json = #"{"docs":[{"title":"Harry","year":1997},{"title":"Dune","year":1965}]}"#
        let bytes = Array(json.utf8).map { Value.number(Double($0)) }
        state.variables["data"] = .object([
            "_type": .string("Data"),
            "bytes": .array(bytes),
        ])

        // `try JSONDecoder().decode(Response.self, from: data)` — SwiftRunner
        // doesn't care about the schema name; it returns a nested Value tree.
        let decoded = state.evaluate(try parse("JSONDecoder().decode(Response.self, from: data)"))
        XCTAssertNotEqual(decoded, .nil, "Decoded value should not be nil")

        // `.docs` → array; `.first` / `.title` walk the nested structure.
        state.variables["resp"] = decoded
        let titleValue = state.evaluate(try parse("resp.docs.first.title"))
        XCTAssertEqual(titleValue, .string("Harry"))
    }

    @MainActor
    func testURLSessionSharedResolvesToTaggedObject() throws {
        let state = SwiftRunnerState()
        let result = state.evaluate(try parse("URLSession.shared"))
        guard case .object(let d) = result,
              case .string("URLSession") = d["_type"] ?? .nil else {
            XCTFail("Expected URLSession-tagged object, got \(result)")
            return
        }
    }

    @MainActor
    func testURLComponentsConstructorTagsObject() throws {
        let state = SwiftRunnerState()
        let result = state.evaluate(try parse("URLComponents(string: \"https://example.com\")"))
        guard case .object(let d) = result,
              case .string("URLComponents") = d["_type"] ?? .nil,
              case .string(let s) = d["string"] ?? .nil else {
            XCTFail("Expected URLComponents-tagged object, got \(result)")
            return
        }
        XCTAssertEqual(s, "https://example.com")
    }

    @MainActor
    func testURLComponentsUrlReadComposesBase() throws {
        // URLComponents(string: "https://openlibrary.org/search.json").url
        // should produce a URL-tagged object whose string equals the base URL.
        let state = SwiftRunnerState()
        let result = state.evaluate(try parse("""
        URLComponents(string: "https://openlibrary.org/search.json").url
        """))
        guard case .object(let d) = result,
              case .string("URL") = d["_type"] ?? .nil,
              case .string(let s) = d["string"] ?? .nil else {
            XCTFail("Expected URL object, got \(result)")
            return
        }
        XCTAssertTrue(s.hasPrefix("https://openlibrary.org/search.json"), "URL string: \(s)")
    }

    // MARK: - Plan 5: property assignment + struct methods

    @MainActor
    func testPropertyAssignmentOnObjectVariable() throws {
        let state = SwiftRunnerState([
            "comps": .object([
                "_type": .string("URLComponents"),
                "string": .string("https://openlibrary.org/search.json"),
                "queryItems": .array([]),
            ])
        ])

        // `comps.queryItems = [URLQueryItem(name: "q", value: "harry")]`
        let node = try parse("""
        comps.queryItems = [URLQueryItem(name: "q", value: "harry")]
        """)
        state.execute(node)

        // Verify: .url composition should now include the query.
        let url = state.evaluate(try parse("comps.url"))
        guard case .object(let d) = url,
              case .string(let s) = d["string"] ?? .nil else {
            XCTFail("Expected URL, got \(url)"); return
        }
        XCTAssertTrue(s.contains("q=harry"), "Expected composed query, got \(s)")
    }

    @MainActor
    func testPropertyAssignmentMutatesNestedDictKey() throws {
        let state = SwiftRunnerState([
            "user": .object(["name": .string("old"), "age": .number(30)]),
        ])
        state.execute(try parse("user.name = \"new\""))
        let got = state.evaluate(try parse("user.name"))
        XCTAssertEqual(got, .string("new"))
        let age = state.evaluate(try parse("user.age"))
        XCTAssertEqual(age, .number(30))
    }

    @MainActor
    func testPropertyAssignmentArrayIndexMutation() throws {
        let state = SwiftRunnerState([
            "items": .array([.string("a"), .string("b"), .string("c")]),
        ])
        state.execute(try parse("items[1] = \"B\""))
        let got = state.evaluate(try parse("items[1]"))
        XCTAssertEqual(got, .string("B"))
    }

    @MainActor
    func testStructMethodRegistersAsScopedFunction() throws {
        // A bare ViewModifier-shaped struct: no `var body: some View`, just
        // `func body(content:) -> some View`. We verify that the function is
        // captured + hoisted as `Shimmer.body` by registerDeclarations.
        let code = """
        struct Shimmer: ViewModifier {
            func body(content: Content) -> some View {
                content
            }
        }
        """
        let state = SwiftRunnerState()
        let ast = try parse(code)
        // Walk to register — mirrors SwiftRunner.registerDeclarations.
        func register(_ node: ViewNode) {
            switch node {
            case .block(let stmts): stmts.forEach(register)
            case .functionDecl: state.execute(node)
            case .enumDeclaration, .extensionDeclaration: state.execute(node)
            default: break
            }
        }
        register(ast)
        XCTAssertNotNil(state.functions["Shimmer.body"], "Expected Shimmer.body to be hoisted")
    }

    // MARK: - Plan 5 capstone: .modifier(X()) user dispatch

    func testParsesModifierCallAsUserModifier() throws {
        let node = try parse("Text(\"hi\").modifier(Shimmer())")
        guard case .modified(_, let mods) = node else {
            XCTFail("Expected modified view, got \(node)"); return
        }
        guard case .userModifier(let typeName) = mods.first else {
            XCTFail("Expected .userModifier, got \(String(describing: mods.first))"); return
        }
        XCTAssertEqual(typeName, "Shimmer")
    }

    // MARK: - Plan 7: iOS chrome modifiers

    func testParsesMaterialBackgroundWithShape() throws {
        let node = try parse("""
        Text("hi").background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        """)
        guard case .modified(_, let mods) = node,
              case .materialBackground(let mat, let shape) = mods.first else {
            XCTFail("Expected materialBackground, got \(node)"); return
        }
        XCTAssertEqual(mat, .ultraThin)
        if case .roundedRectangle(let r) = shape {
            XCTAssertEqual(r, 12)
        } else {
            XCTFail("Expected rounded rectangle shape, got \(String(describing: shape))")
        }
    }

    func testParsesButtonStyleBorderedProminent() throws {
        let node = try parse("Button(\"Go\") {}.buttonStyle(.borderedProminent)")
        guard case .modified(_, let mods) = node,
              case .buttonStyle(let style) = mods.first else {
            XCTFail("Expected buttonStyle, got \(node)"); return
        }
        XCTAssertEqual(style, .borderedProminent)
    }

    func testParsesTextFieldStylePlain() throws {
        let node = try parse("""
        TextField("Name", text: $name).textFieldStyle(.plain)
        """)
        guard case .modified(_, let mods) = node,
              case .textFieldStyle(let style) = mods.first else {
            XCTFail("Expected textFieldStyle, got \(node)"); return
        }
        XCTAssertEqual(style, .plain)
    }

    func testParsesControlSizeSmall() throws {
        let node = try parse("ProgressView().controlSize(.small)")
        guard case .modified(_, let mods) = node,
              case .controlSize(let s) = mods.first else {
            XCTFail("Expected controlSize, got \(node)"); return
        }
        XCTAssertEqual(s, .small)
    }

    func testParsesRefreshableWithTrailingClosure() throws {
        let node = try parse("""
        ScrollView { Text("pull me") }.refreshable { }
        """)
        guard case .modified(_, let mods) = node,
              case .refreshable = mods.first else {
            XCTFail("Expected refreshable, got \(node)"); return
        }
    }

    // MARK: - Plan 5 capstone: computed properties on decoded objects

    @MainActor
    func testComputedPropertyDispatchesOnDecodedJSON() throws {
        // Parse a struct with a computed property, register it, tag a decoded
        // object with the struct's type, and assert property access dispatches
        // through the computed getter.
        let state = SwiftRunnerState()

        let structCode = """
        struct Book: Decodable {
            let title: String
            let author_name: [String]?
            var authorLine: String { return "By: " }
        }
        """
        let ast = try parse(structCode)
        func register(_ node: ViewNode) {
            switch node {
            case .block(let stmts): stmts.forEach(register)
            case .functionDecl, .enumDeclaration, .extensionDeclaration:
                state.execute(node)
            default: break
            }
        }
        register(ast)
        XCTAssertNotNil(state.functions["Book.authorLine"])

        // Simulate a JSONDecoder-decoded book: a plain object with `_type` tag.
        state.variables["b"] = .object([
            "_type": .string("Book"),
            "title": .string("Harry"),
            "author_name": .array([.string("JK Rowling")]),
        ])

        // Plain key — dict hit.
        XCTAssertEqual(state.evaluate(try parse("b.title")), .string("Harry"))

        // Missing key → dispatches through Book.authorLine computed getter.
        XCTAssertEqual(state.evaluate(try parse("b.authorLine")), .string("By: "))
    }

    @MainActor
    func testJSONDecoderTagsTopLevelResult() throws {
        // After `JSONDecoder().decode(Response.self, from: data)`, the returned
        // object should carry a `_type: "Response"` tag.
        let state = SwiftRunnerState()
        let json = #"{"status":"ok"}"#
        state.variables["data"] = .object([
            "_type": .string("Data"),
            "bytes": .array(Array(json.utf8).map { .number(Double($0)) }),
        ])
        let decoded = state.evaluate(try parse("JSONDecoder().decode(Response.self, from: data)"))
        guard case .object(let d) = decoded,
              case .string("Response") = d["_type"] ?? .nil else {
            XCTFail("Expected top-level tag, got \(decoded)"); return
        }
        XCTAssertEqual(d["status"], .string("ok"))
    }

    // MARK: - Plan 7: withAnimation body executes

    @MainActor
    func testWithAnimationExecutesTrailingBody() throws {
        let state = SwiftRunnerState(["count": .number(0)])
        let node = try parse("withAnimation(.easeInOut) { count += 1 }")
        state.execute(node)
        XCTAssertEqual(state.variables["count"], .number(1))
    }

    @MainActor
    func testTaskBlockExecutesBodySynchronously() throws {
        let state = SwiftRunnerState(["flag": .boolean(false)])
        let node = try parse("Task { flag = true }")
        state.execute(node)
        XCTAssertEqual(state.variables["flag"], .boolean(true))
    }

    // MARK: - Plan 5 capstone: nested decoded objects get tagged via schemas

    @MainActor
    func testDecodedNestedArrayElementsDispatchComputedProperty() throws {
        // Parse two structs: OpenLibraryResponse { let docs: [OpenLibraryDoc] }
        // and OpenLibraryDoc with a computed property `authorLine`.
        // Schema propagation should tag each nested doc with _type: OpenLibraryDoc
        // so `resp.docs.first.authorLine` invokes the computed getter.
        let code = """
        struct OpenLibraryResponse: Decodable {
            let docs: [OpenLibraryDoc]
        }
        struct OpenLibraryDoc: Decodable {
            let title: String
            var authorLine: String { return "BY " }
        }
        """

        let state = SwiftRunnerState()
        let ast = try parser.parse(tokenize(code))
        func register(_ node: ViewNode) {
            switch node {
            case .block(let stmts): stmts.forEach(register)
            case .functionDecl, .enumDeclaration, .extensionDeclaration:
                state.execute(node)
            default: break
            }
        }
        register(ast)
        state.typeSchemas = parser.parsedSchemas

        // Sanity: the schema captured the inner type of `docs`.
        XCTAssertEqual(parser.parsedSchemas["OpenLibraryResponse"]?["docs"], "OpenLibraryDoc")
        XCTAssertNotNil(state.functions["OpenLibraryDoc.authorLine"])

        // Provide JSON bytes shaped like the response.
        let json = #"{"docs":[{"title":"Harry"},{"title":"Dune"}]}"#
        state.variables["data"] = .object([
            "_type": .string("Data"),
            "bytes": .array(Array(json.utf8).map { .number(Double($0)) }),
        ])

        let resp = state.evaluate(try parse("JSONDecoder().decode(OpenLibraryResponse.self, from: data)"))
        state.variables["resp"] = resp

        // Nested element computed property should fire thanks to schema tagging.
        XCTAssertEqual(
            state.evaluate(try parse("resp.docs.first.authorLine")),
            .string("BY ")
        )
    }

    // MARK: - Plan 3: array literal trailing comma

    func testArrayLiteralAcceptsTrailingComma() throws {
        let node = try parse("""
        [
            URLQueryItem(name: "q", value: "harry"),
            URLQueryItem(name: "fields", value: "*"),
            URLQueryItem(name: "limit", value: "24"),
        ]
        """)
        guard case .arrayLiteral(let elems) = node else {
            XCTFail("Expected arrayLiteral, got \(node)"); return
        }
        XCTAssertEqual(elems.count, 3)
    }

    // MARK: - Dictionary literals

    func testParsesEmptyDictionaryLiteral() throws {
        // `[:]` — empty dictionary marker. Represented as `_dictLiteral([])`
        // so it evaluates to an empty `.object([:])`.
        XCTAssertNoThrow(try parse("[:]"))
    }

    @MainActor
    func testEmptyDictionaryEvaluatesToEmptyObject() throws {
        let state = SwiftRunnerState()
        let v = state.evaluate(try parse("[:]"))
        XCTAssertEqual(v, .object([:]))
    }

    @MainActor
    func testKeyedDictionaryLiteralEvaluatesToObject() throws {
        let state = SwiftRunnerState()
        let v = state.evaluate(try parse("""
        ["name": "Alice", "age": 30]
        """))
        guard case .object(let d) = v else { XCTFail("Expected object, got \(v)"); return }
        XCTAssertEqual(d["name"], .string("Alice"))
        XCTAssertEqual(d["age"], .number(30))
    }

    func testDictionaryLiteralAcceptsTrailingComma() throws {
        XCTAssertNoThrow(try parse("""
        ["a": 1, "b": 2,]
        """))
    }

    // MARK: - Type-cast operators (as, as?, as!)

    func testParsesAsOptionalCastInGuardLet() throws {
        XCTAssertNoThrow(try parse("""
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        """))
    }

    func testParsesAsForcedCastInExpression() throws {
        XCTAssertNoThrow(try parse("let x = y as! String"))
    }

    func testParsesAsUnconditionalCastInExpression() throws {
        XCTAssertNoThrow(try parse("let x = anything as Any"))
    }

    // MARK: - Optional chain disambiguation from ternary

    func testParsesOptionalChainAfterProperty() throws {
        // `doc.isbn?.first` — `?` adjacent to `isbn`, followed by `.first`.
        // Must not be misread as a ternary operator.
        XCTAssertNoThrow(try parse("let x = doc.isbn?.first"))
    }

    func testOptionalChainInsideLetBinding() throws {
        // The exact shape from LibraryApp.swift's merger code.
        XCTAssertNoThrow(try parse("""
        let isbn = doc.isbn?.first
        let entry = isbn.flatMap { enrichment["ISBN:\\(x)"] }
        """))
    }

    func testTernaryAfterSpacedQuestionMarkStillParses() throws {
        // Regression guard: `fill(flag ? .blue : .red)` must still be a ternary
        // even though `.blue` starts with `.`. The disambiguation relies on
        // whitespace before `?`.
        let node = try parse("Circle().fill(flag ? .blue : .red)")
        guard case .modified = node else {
            XCTFail("Expected modified Circle, got \(node)"); return
        }
    }

    // MARK: - Smoke test against the real Desktop file

    /// Pulls in the current contents of `~/Desktop/LibraryApp.swift` and asserts
    /// it parses without throwing. Conditional on the file existing so CI on
    /// other machines doesn't break.
    func testDesktopLibraryAppParses() throws {
        let home = NSHomeDirectory()
        let path = "\(home)/Desktop/LibraryApp.swift"
        guard FileManager.default.fileExists(atPath: path),
              let src = try? String(contentsOfFile: path) else {
            throw XCTSkip("LibraryApp.swift not present on this machine")
        }
        do {
            _ = try parse(src)
        } catch {
            XCTFail("LibraryApp.swift failed to parse: \(error.localizedDescription)")
        }
    }

    // MARK: - Diagnostic: BookDetailPage stored body contains stateInit nodes

    /// Sanity check that the parser captures `@State` defaults into the
    /// stored body of an inlined struct. Without this, navigating to the
    /// detail page leaves `isLoading`/`work`/`loadFailed` undefined, so
    /// every branch of the `if isLoading {} else if loadFailed {} else if let work {}`
    /// chain is falsy and the details section renders nothing.
    func testInlinedStructStoresStateInitsInBody() throws {
        let code = """
        struct DetailPage: View {
            let book: String
            @State private var loading = true
            @State private var work: String?
            var body: some View {
                Text("Hi")
            }
        }
        """
        let p = SwiftParser()
        _ = try p.parse(try SwiftLexer(source: code).tokenize())
        guard let stored = p.parsedStructs["DetailPage"] else {
            return XCTFail("DetailPage not registered")
        }
        guard case .block(let stmts) = stored.body else {
            return XCTFail("storedBody should be a block when state inits exist, got \(stored.body)")
        }
        let inits = stmts.compactMap { stmt -> String? in
            if case .stateInit(let n, _) = stmt { return n }
            return nil
        }
        XCTAssertTrue(inits.contains("loading"),
                      "missing stateInit for `loading`. inits=\(inits)")
        XCTAssertTrue(inits.contains("work"),
                      "missing stateInit for `work`. inits=\(inits)")
        XCTAssertFalse(inits.contains("book"),
                       "init-param `book` should NOT be a stateInit. inits=\(inits)")
    }

    // MARK: - Diagnostic: which structs in LibraryApp.swift end up registered?

    func testDiagnoseLibraryAppStructsRegistered() throws {
        let home = NSHomeDirectory()
        let path = "\(home)/Desktop/LibraryApp.swift"
        guard FileManager.default.fileExists(atPath: path),
              let src = try? String(contentsOfFile: path) else {
            throw XCTSkip("LibraryApp.swift not present on this machine")
        }
        let p = SwiftParser()
        let tokens = try SwiftLexer(source: src).tokenize()
        _ = try p.parse(tokens)
        let names = p.parsedStructs.keys.sorted()
        print("[DIAG] parsedStructs: \(names)")
        // We at least expect the View structs we care about to be registered.
        XCTAssertTrue(names.contains("BookCard"), "BookCard not registered: \(names)")
        XCTAssertTrue(names.contains("LibraryApp"), "LibraryApp not registered: \(names)")
        XCTAssertTrue(names.contains("BookDetailPage"), "BookDetailPage not registered: \(names)")
    }

    // MARK: - Defer regression for the user's task/load flow

    @MainActor
    func testDeferRunsOnFunctionExitAndResetsState() throws {
        let state = SwiftRunnerState()
        let decl = try parse("""
        struct App {
            @State var isLoading = false
            @State var books: [Int] = []

            func load() {
                isLoading = true
                defer { isLoading = false }
                books = [1, 2, 3]
            }
        }
        """)
        func register(_ n: ViewNode) {
            switch n {
            case .block(let s): s.forEach(register)
            case .functionDecl, .enumDeclaration, .extensionDeclaration:
                state.execute(n)
            default: break
            }
        }
        register(decl)
        state.variables["isLoading"] = .boolean(false)
        state.variables["books"] = .array([])

        _ = state.evaluate(try parse("load()"))

        XCTAssertEqual(state.variables["isLoading"], .boolean(false),
                       "defer { isLoading = false } should fire after load() returns")
        if case .array(let arr) = state.variables["books"] {
            XCTAssertEqual(arr.count, 3)
        } else {
            XCTFail("books should be a 3-element array")
        }
    }

    @MainActor
    func testDeferRunsEvenOnEarlyReturn() throws {
        let state = SwiftRunnerState()
        let decl = try parse("""
        struct App {
            @State var counter = 0

            func tick() {
                defer { counter = 999 }
                if true { return }
                counter = -1
            }
        }
        """)
        func register(_ n: ViewNode) {
            switch n {
            case .block(let s): s.forEach(register)
            case .functionDecl, .enumDeclaration, .extensionDeclaration:
                state.execute(n)
            default: break
            }
        }
        register(decl)
        state.variables["counter"] = .number(0)

        _ = state.evaluate(try parse("tick()"))

        XCTAssertEqual(state.variables["counter"], .number(999),
                       "defer must fire on early-return paths")
    }

    @MainActor
    func testIfLetShorthandUnwrapsSameNameOptional() throws {
        let state = SwiftRunnerState()
        // Wrap in a function so executeWithReturn handles `.conditional`.
        let decl = try parse("""
        func check() {
            if let errorMessage {
                errorMessage = "ran"
            }
        }
        """)
        state.execute(decl)

        // When errorMessage is nil, the then-branch must NOT run.
        state.variables["errorMessage"] = .nil
        _ = state.evaluate(try parse("check()"))
        XCTAssertEqual(state.variables["errorMessage"], .nil,
                       "shorthand `if let` must NOT enter then-branch when nil")

        // When errorMessage is non-nil, the then-branch MUST run.
        state.variables["errorMessage"] = .string("oops")
        _ = state.evaluate(try parse("check()"))
        XCTAssertEqual(state.variables["errorMessage"], .string("ran"),
                       "shorthand `if let` must enter then-branch when non-nil")
    }

    @MainActor
    func testOptionalStateVarRegistersAsNilEvenWithoutInitializer() throws {
        // The user's LibraryApp has `@State private var errorMessage: String?`
        // with no `=` — the parser previously dropped the property silently.
        // Now it should register as `.nil` so reads inside the body work.
        let state = SwiftRunnerState()
        let ast = try parse("""
        struct App: View {
            @State private var errorMessage: String?
            var body: some View {
                Text("hi")
            }
        }

        App()
        """)
        // collect & strip extracts assignments from blocks. We invoke that path
        // by running through SwiftRunner.run's pipeline indirectly: state vars
        // appear as `.assignment` nodes at the top of the App() inlined body.
        func collectAssignments(_ node: ViewNode, into vars: inout [String: Value]) {
            switch node {
            case .assignment(let n, _, let v):
                vars[n] = state.evaluate(v)
            case .block(let stmts):
                for s in stmts { collectAssignments(s, into: &vars) }
            default: break
            }
        }
        var collected: [String: Value] = [:]
        collectAssignments(ast, into: &collected)
        XCTAssertNotNil(collected["errorMessage"], "errorMessage must be registered as .nil")
        if let v = collected["errorMessage"] {
            XCTAssertEqual(v, .nil)
        }
    }

    // MARK: - Multi-struct file: pick the LAST view, not the first

    @MainActor
    func testMultiStructFilePicksLastViewNotFirst() throws {
        // Reproduces the LibraryApp.swift symptom: when a file has multiple
        // View-conforming structs and ends with `#Preview { LibraryApp() }`,
        // the runner must render LibraryApp's body — NOT the first View struct
        // (PlaceholderCard) that happens to appear earlier in the file.
        //
        // The lexer strips `#Preview`, leaving a bare `{ LibraryApp() }`.
        // The parser inlines LibraryApp(), so the custom-call signal is gone.
        // deduplicatePreview must still pick LibraryApp's body.
        let runner = SwiftRunner.shared
        _ = runner.run("") // reset state
        let result = runner.run("""
        struct PlaceholderCard: View {
            var body: some View {
                Text("PLACEHOLDER")
            }
        }

        struct MainApp: View {
            @State private var loaded = false
            var body: some View {
                Text("MAIN")
                    .onAppear {
                        loaded = true
                    }
            }
        }

        #Preview {
            MainApp()
        }
        """)
        XCTAssertEqual(result.errors, [])
        // The final view should be MainApp's body. We assert by reading the
        // actual rendered consoleOutput after firing the onAppear action that
        // only MainApp.body has.
        // Easier: check `runner.hasView` is true and that we can find a registered
        // assignment for `loaded` (MainApp's @State). Then we'd know MainApp parsed.
        // But the real check: invoke the resulting deduplicated AST's first found
        // .onAppear action and verify `loaded` flips to true.
        //
        // For now, the cleanest assertion: the deduplicated top-level view AST
        // must NOT be the PlaceholderCard body.
        let cleanAST = runner.cleanASTForTesting
        XCTAssertNotNil(cleanAST)
        let cleanStr = "\(cleanAST as Any)"
        XCTAssertFalse(cleanStr.contains("PLACEHOLDER"),
                       "Deduplicated AST must NOT be PlaceholderCard's body — got: \(cleanStr.prefix(500))")
        XCTAssertTrue(cleanStr.contains("MAIN"),
                      "Deduplicated AST must contain MainApp's body — got: \(cleanStr.prefix(500))")
    }

    @MainActor
    func testDedupPreservesUserFunctionsForRuntimeDispatch() throws {
        // The user's symptom: `.task` fired `print(...)` (the only log they saw),
        // then `await load()` silently no-op'd because `LibraryApp.load` was
        // never registered — dedup had stripped all `.functionDecl`,
        // `.enumDeclaration`, `.extensionDeclaration` nodes from the AST that
        // `registerDeclarations` walks.
        //
        // After the fix, the post-dedup AST must still contain those nodes so
        // the runtime function table gets populated.
        let runner = SwiftRunner.shared
        _ = runner.run("") // reset
        _ = runner.run("""
        enum Helper { static func tag() -> Int { return 7 } }
        func freeFn() -> Int { return 11 }

        struct PlaceholderCard: View {
            var body: some View { Text("PH") }
        }

        struct App: View {
            @State private var n: Int = 0
            var body: some View { Text("APP") }
            func compute() -> Int { return 99 }
        }

        #Preview { App() }
        """)
        guard let deduped = runner.dedupedASTForTesting else {
            return XCTFail("dedupedASTForTesting was nil")
        }
        let astStr = "\(deduped)"
        XCTAssertTrue(astStr.contains("enumDeclaration"),
                      "enum Helper must survive dedup")
        XCTAssertTrue(astStr.contains("freeFn"),
                      "free function freeFn() must survive dedup")
        XCTAssertTrue(astStr.contains("compute"),
                      "App.compute (extension on struct) must survive dedup")
        XCTAssertTrue(astStr.contains("\"APP\""),
                      "App's body view (not Placeholder's) must survive dedup — got: \(astStr.prefix(800))")
        XCTAssertFalse(astStr.contains("\"PH\""),
                       "PlaceholderCard's body must NOT be the rendered view")
    }

    @MainActor
    func testRunAsyncCompletesWithoutBlockingMain() async throws {
        // The async runtime path: `.task` body that does `await URLSession.shared.data`
        // suspends a Task without blocking the main thread. Here we just verify
        // that runAsync executes the body to completion and updates state — the
        // suspension behavior is what the SwiftUI Task wrapper provides for free.
        let state = SwiftRunnerState()
        let parser = SwiftParser()
        let lexer = SwiftLexer(source: """
        struct App {
            @State var ready = false
            @State var loaded: Int = 0
            func tickAsync() async {
                ready = true
                loaded = 42
            }
        }
        """)
        let tokens = try lexer.tokenize()
        let ast = try parser.parse(tokens)
        func register(_ n: ViewNode) {
            switch n {
            case .block(let s): s.forEach(register)
            case .functionDecl, .enumDeclaration, .extensionDeclaration:
                state.execute(n)
            default: break
            }
        }
        register(ast)

        // Run the .task action async and confirm state changed.
        let parser2 = SwiftParser()
        let action = try parser2.parse(try SwiftLexer(source: "tickAsync()").tokenize())
        await state.runAsync(action)

        XCTAssertEqual(state.variables["ready"], .boolean(true))
        XCTAssertEqual(state.variables["loaded"], .number(42))
    }

    @MainActor
    func testDollarZeroLexesAsBindingIdentifierNotNumber() throws {
        // The user's `ForEach(books) { BookCard(book: $0) }` was rendering
        // every BookCard with `book = 0` because the lexer required a letter
        // after `$`. `$0` got split into `$` (dropped) and `0` (number literal).
        let tokens = try tokenize("$0")
        XCTAssertEqual(tokens.count, 2, "expected one bindingIdentifier + EOF")
        guard case .bindingIdentifier(let name) = tokens[0].type else {
            return XCTFail("Expected bindingIdentifier, got: \(tokens[0])")
        }
        XCTAssertEqual(name, "0", "expected `$0` to lex as bindingIdentifier(\"0\")")

        // Sanity: `$query` (letter form) still works.
        let tokens2 = try tokenize("$query")
        guard case .bindingIdentifier(let q) = tokens2[0].type else {
            return XCTFail("Expected bindingIdentifier for $query")
        }
        XCTAssertEqual(q, "query")
    }

    @MainActor
    func testForEachBindsDollarZeroToCurrentItem() throws {
        // End-to-end: a ForEach over a tagged collection should make `$0`
        // (the current item) accessible inside the body.
        let runner = SwiftRunner.shared
        _ = runner.run("")
        _ = runner.run("""
        struct Row: View {
            let label: String
            var body: some View { Text(label) }
        }
        struct Wrapper: View {
            @State private var items: [String] = ["alpha", "beta", "gamma"]
            var body: some View {
                VStack {
                    ForEach(items, id: \\.self) { Row(label: $0) }
                }
            }
        }
        #Preview { Wrapper() }
        """)
        guard let cleanAST = runner.cleanASTForTesting else {
            return XCTFail("no cleanAST")
        }
        let astStr = "\(cleanAST)"
        // After dedup, the body should contain a forEachCollection over `items`
        // and Row's body which uses `label` (= $0). We mostly care that no
        // bare numeric literals replaced the `$0` references.
        XCTAssertTrue(astStr.contains("forEachCollection") || astStr.contains("forEach"),
                      "ForEach should survive dedup — got \(astStr.prefix(500))")
        XCTAssertFalse(astStr.contains("literal(SwiftRunner.LiteralValue.number(0.0))"),
                       "no `$0` should have been converted to a literal 0 — got \(astStr.prefix(500))")
    }

    @MainActor
    func testOnSubmitDoesNotEraseTextField() throws {
        // The user's `TextField("…", text: $query).textFieldStyle(.plain)
        // .submitLabel(.search).onSubmit { Task { await load() } }` chain
        // was wrapping the entire TextField in a `.methodCall`, which the
        // renderer treated as a non-view, hiding the search bar entirely.
        let runner = SwiftRunner.shared
        _ = runner.run("")
        _ = runner.run("""
        struct App: View {
            @State private var query: String = ""
            var body: some View {
                TextField("Search…", text: $query)
                    .onSubmit { print("submitted") }
            }
        }
        #Preview { App() }
        """)
        guard let cleanAST = runner.cleanASTForTesting else {
            return XCTFail("no cleanAST")
        }
        let astStr = "\(cleanAST)"
        XCTAssertTrue(astStr.contains("textField"),
                      "TextField must survive .onSubmit — got: \(astStr.prefix(500))")
        XCTAssertFalse(astStr.contains("methodCall"),
                       "TextField must NOT be wrapped in a methodCall — got: \(astStr.prefix(500))")
    }

    @MainActor
    func testMultiStructWithTaskOnAppearGetsPreserved() throws {
        // The actual symptom from LibraryApp.swift: a `.task { ... }` on the
        // main view's NavigationStack must survive deduplication so SwiftUI
        // can fire the action when the view mounts.
        let runner = SwiftRunner.shared
        _ = runner.run("") // reset
        _ = runner.run("""
        struct PlaceholderCard: View {
            var body: some View { Text("PH") }
        }
        struct LibraryApp: View {
            @State private var books: [String] = []
            var body: some View {
                NavigationStack {
                    Text("LIB")
                }
                .task {
                    books = ["a", "b"]
                }
            }
        }
        #Preview { LibraryApp() }
        """)
        guard let cleanAST = runner.cleanASTForTesting else {
            return XCTFail("cleanASTForTesting was nil")
        }
        let astStr = "\(cleanAST)"
        XCTAssertTrue(astStr.contains("LIB"),
                      "cleanAST must come from LibraryApp's body — got: \(astStr.prefix(800))")
        XCTAssertTrue(astStr.contains("taskAction"),
                      ".task should produce a taskAction modifier and survive dedup — got: \(astStr.prefix(800))")
        XCTAssertTrue(astStr.contains("books"),
                      ".task action should reference `books` — got: \(astStr.prefix(800))")
    }

    // MARK: - Bare-name dispatch fallback to unique scoped match

    @MainActor
    func testBareCallResolvesToUniqueScopedFunction() throws {
        // `load()` inside a struct is registered as `LibraryApp.load` by
        // the struct-member hoisting path. A bare `load()` call should find
        // it via the `.load` suffix fallback.
        let state = SwiftRunnerState()
        let decl = try parse("""
        struct LibraryApp {
            func load() -> Int { return 99 }
        }
        """)
        func register(_ n: ViewNode) {
            switch n {
            case .block(let s): s.forEach(register)
            case .functionDecl, .enumDeclaration, .extensionDeclaration:
                state.execute(n)
            default: break
            }
        }
        register(decl)
        XCTAssertNotNil(state.functions["LibraryApp.load"])

        // Bare `load()` finds LibraryApp.load as a unique `.load` match.
        let result = state.evaluate(try parse("load()"))
        XCTAssertEqual(result, .number(99))
    }

    // MARK: - Computed view property dispatch at render time

    @MainActor
    func testParsesComputedViewPropertyBody() throws {
        // A struct with a computed `some View` body AND a separate computed
        // `some View` property `header` that `body` references bare.
        // We parse, register, and confirm the header body is captured as a
        // zero-arg functionDecl so the view builder can render it.
        let code = """
        struct Host: View {
            var body: some View {
                VStack { header }
            }
            private var header: some View {
                Text("hi")
            }
        }
        """
        XCTAssertNoThrow(try parse(code))

        let state = SwiftRunnerState()
        let ast = try parse(code)
        func register(_ n: ViewNode) {
            switch n {
            case .block(let s): s.forEach(register)
            case .functionDecl, .enumDeclaration, .extensionDeclaration:
                state.execute(n)
            default: break
            }
        }
        register(ast)
        XCTAssertNotNil(state.functions["Host.header"])
    }

    // MARK: - End-to-end diagnostic for LibraryApp.swift

    /// Run the actual Desktop file through SwiftRunner.shared.run() and emit a
    /// full report: does it parse, what functions get registered, what's the
    /// initial state, what does the top-level AST look like after cleanup,
    /// and can we locate the body view node for LibraryApp.
    @MainActor
    func testDiagnoseLibraryAppEndToEnd() throws {
        let home = NSHomeDirectory()
        let path = "\(home)/Desktop/LibraryApp.swift"
        guard FileManager.default.fileExists(atPath: path),
              let src = try? String(contentsOfFile: path) else {
            throw XCTSkip("LibraryApp.swift not present")
        }

        let runner = SwiftRunner.shared
        let result = runner.run(src)

        print("=== DIAG: errors ===")
        print(runner.errors)
        print("=== DIAG: console ===")
        print(result.consoleOutput)
        print("=== DIAG: hasView ===")
        print(runner.hasView)

        // Peek at the parser's state
        print("=== DIAG: parsedStructs ===")
        print(parser.parsedStructs.keys.sorted())
        print("=== DIAG: parsedSchemas ===")
        for (k, v) in parser.parsedSchemas.sorted(by: { $0.key < $1.key }) {
            print("  \(k): \(v)")
        }

        // Re-parse to inspect AST directly (runner owns its own parser).
        let standaloneParser = SwiftParser()
        let lexer = SwiftLexer(source: src)
        let tokens = try lexer.tokenize()
        let ast = try standaloneParser.parse(tokens)

        print("=== DIAG: top-level AST statement count ===")
        if case .block(let stmts) = ast {
            print(stmts.count)
            for (i, s) in stmts.enumerated() {
                switch s {
                case .functionDecl(let n, _, _, _, _): print("  [\(i)] functionDecl: \(n)")
                case .enumDeclaration(let n, _, _):    print("  [\(i)] enumDeclaration: \(n)")
                case .extensionDeclaration(let t, _):  print("  [\(i)] extensionDeclaration: \(t)")
                case .block:                           print("  [\(i)] block (likely a struct)")
                case .empty:                           print("  [\(i)] empty")
                default:                               print("  [\(i)] \(type(of: s))")
                }
            }
        } else {
            print("top-level is not a block: \(ast)")
        }

        print("=== DIAG: parsedStructSchemas ===")
        print(standaloneParser.parsedSchemas.keys.sorted())

        // Now simulate the full SwiftRunner.run pipeline up to state construction.
        // We can't inspect the state directly because runner.run returns a view and
        // keeps state inside DynamicView. Reconstruct state.
        let state = SwiftRunnerState()
        func register(_ n: ViewNode) {
            switch n {
            case .block(let s): s.forEach(register)
            case .functionDecl, .enumDeclaration, .extensionDeclaration:
                state.execute(n)
            default: break
            }
        }
        register(ast)
        state.typeSchemas = standaloneParser.parsedSchemas

        print("=== DIAG: registered functions ===")
        for k in state.functions.keys.sorted() { print("  \(k)") }

        // Preload the @State vars the body reads (from the cleanAST state capture).
        state.variables["query"] = .string("science fiction")
        state.variables["books"] = .array([])
        state.variables["isLoading"] = .boolean(false)

        // First, simulate the full live app: invoke load() (triggered by .task)
        // and inspect state afterward.
        state.variables["query"] = .string("science fiction")
        state.variables["books"] = .array([])
        state.variables["isLoading"] = .boolean(false)
        state.variables["errorMessage"] = .nil
        print("=== DIAG: live-app simulation: invoke load() ===")
        _ = state.evaluate(try parse("load()"))
        // Inspect the docs array that was set as a side-effect of search()
        if case .array(let docs) = state.variables["docs"] ?? .nil {
            print("  state.variables[docs].count = \(docs.count)")
            if let first = docs.first {
                print("  first doc keys (first 400): \(first.description.prefix(400))")
            }
        } else {
            print("  state.variables[docs] type = \(state.variables["docs"] ?? .nil)")
        }
        if case .array(let live) = state.variables["books"] ?? .nil {
            print("  state.variables[books].count = \(live.count)")
            if let first = live.first { print("  first live book: \(first.description.prefix(400))") }
        } else {
            print("  state.variables[books] = \(state.variables["books"] ?? .nil)")
        }
        print("  state.typeSchemas: \(state.typeSchemas)")
        print("  state.variables[isLoading] = \(state.variables["isLoading"] ?? .nil)")
        print("  state.variables[errorMessage] = \(state.variables["errorMessage"] ?? .nil)")

        // Trace each step of BookService.search manually.
        print("=== DIAG: step trace ===")
        let comps0 = state.evaluate(try parse(#"URLComponents(string: "https://openlibrary.org/search.json")"#))
        state.variables["_c"] = comps0
        print("  URLComponents: \(comps0)")

        state.execute(try parse(#"_c.queryItems = [URLQueryItem(name: "q", value: "harry potter"), URLQueryItem(name: "limit", value: "3")]"#))
        print("  after queryItems = [...]: \(state.variables["_c"] ?? .nil)")

        let urlVal = state.evaluate(try parse("_c.url"))
        print("  _c.url = \(urlVal)")

        let fetchResult = state.evaluate(try parse("URLSession.shared.data(from: _c.url)"))
        if case .array(let arr) = fetchResult, arr.count == 2 {
            print("  data bytes count: \((bytesSize(arr[0])))")
            print("  response: \(arr[1])")

            // Decode directly
            state.variables["_data"] = arr[0]
            let decoded = state.evaluate(try parse(
                "JSONDecoder().decode(OpenLibraryResponse.self, from: _data)"
            ))
            print("  decoded top-level: \(searchResultTypeName(decoded))")
            state.variables["_decoded"] = decoded
            let docsViaDot = state.evaluate(try parse("_decoded.docs"))
            print("  _decoded.docs type: \(searchResultTypeName(docsViaDot))")
            if case .array(let da) = docsViaDot {
                print("  _decoded.docs count: \(da.count)")
                if let first = da.first {
                    print("  first doc snippet: \(first.description.prefix(300))")
                }
            }
        } else {
            print("  fetch returned (non-tuple): \(fetchResult)")
        }

        // Dispatch BookService.search end-to-end.
        print("=== DIAG: BookService.search(query: \"science fiction\") ===")
        let searchResult = state.evaluate(try parse(#"BookService.search(query: "science fiction")"#))
        print("  search return type: \(searchResultTypeName(searchResult))")
        if case .array(let a) = searchResult {
            print("  docs.count: \(a.count)")
            if let first = a.first {
                print("  first doc: \(first.description.prefix(400))")
            }
        } else {
            print("  search returned (non-array): \(searchResult.description.prefix(400))")
        }

        // Then, mergeBooks over the result + empty enrichment.
        if case .array = searchResult {
            state.variables["_docsForTest"] = searchResult
            state.variables["_enrichmentForTest"] = .object([:])
            let merged = state.evaluate(try parse(
                "mergeBooks(docs: _docsForTest, enrichment: _enrichmentForTest)"
            ))
            print("=== DIAG: mergeBooks result ===")
            if case .array(let a) = merged {
                print("  books count: \(a.count)")
                if let first = a.first { print("  first book: \(first.description.prefix(400))") }
            } else {
                print("  non-array: \(merged.description.prefix(400))")
            }
        }
    }

    private func bytesSize(_ v: Value) -> Int {
        guard case .object(let d) = v, case .array(let a) = d["bytes"] ?? .nil else { return -1 }
        return a.count
    }

    private func searchResultTypeName(_ v: Value) -> String {
        switch v {
        case .nil: return "nil"
        case .array(let a): return "array[\(a.count)]"
        case .object(let d): return "object(keys: \(d.keys.sorted()))"
        case .string(let s): return "string(\(s.prefix(60)))"
        case .number(let n): return "number(\(n))"
        case .boolean(let b): return "bool(\(b))"
        }
    }

    // MARK: - Deferred initialization (valid Swift: `let x: T` then assigned)

    /// `let x: T` (no `=`) is valid Swift when `x` is assigned on every path
    /// before use (definite initialization). The parser lowers it to an
    /// initial nil binding so later branch assignments are runnable.
    func testDeferredLetInitWithTypeAnnotationLowersToNil() throws {
        let node = try parse("let description: String?")
        guard case .assignment(let name, let isVar, let value) = node else {
            return XCTFail("expected assignment, got \(node)")
        }
        XCTAssertEqual(name, "description")
        XCTAssertFalse(isVar)
        XCTAssertEqual(value, .literal(.nil))
    }

    func testDeferredVarInitWithTypeAnnotationLowersToNil() throws {
        let node = try parse("var count: Int")
        guard case .assignment(let name, let isVar, let value) = node else {
            return XCTFail("expected assignment, got \(node)")
        }
        XCTAssertEqual(name, "count")
        XCTAssertTrue(isVar)
        XCTAssertEqual(value, .literal(.nil))
    }

    /// Bare `let x` (no type, no initializer) is still invalid Swift and
    /// should error with the original "needs an initial value" hint.
    func testDeferredLetWithoutTypeStillErrors() {
        XCTAssertThrowsError(try parse("let x"))
    }

    /// Wrapped in a block so a deferred decl + subsequent assignments parse
    /// as adjacent statements (no errors thrown). The actual runtime
    /// commit-after-branch semantics live outside the parser's purview.
    func testDeferredLetFollowedByAssignmentsParsesCleanly() throws {
        let code = """
        let result: String?
        result = "first"
        """
        let node = try parse(code)
        guard case .block(let stmts) = node else {
            return XCTFail("expected block, got \(node)")
        }
        XCTAssertEqual(stmts.count, 2)
        guard case .assignment(let name, _, let value) = stmts[0] else {
            return XCTFail("first stmt should be assignment, got \(stmts[0])")
        }
        XCTAssertEqual(name, "result")
        XCTAssertEqual(value, .literal(.nil))
    }

    // MARK: - Multi-clause guard (comma-separated conditions)

    /// `guard A, B else { ... }` is valid Swift — equivalent to `guard A && B`.
    /// The parser ANDs all comma-separated condition expressions together.
    func testGuardWithMultipleCommaConditionsParses() throws {
        let node = try parse("guard a == 1, b != 2 else { return }")
        guard case .guardExpr(let cond, _) = node else {
            return XCTFail("expected guardExpr, got \(node)")
        }
        guard case .binary(_, let op, _) = cond else {
            return XCTFail("expected AND-binary condition, got \(cond)")
        }
        XCTAssertEqual(op, .and)
    }

    /// Three-clause guard chains left-associatively: ((A && B) && C).
    func testGuardWithThreeCommaConditionsChainsAndOperators() throws {
        let node = try parse("guard a, b, c else { return }")
        guard case .guardExpr(let cond, _) = node else {
            return XCTFail("expected guardExpr, got \(node)")
        }
        guard case .binary(let left, .and, let right) = cond else {
            return XCTFail("expected AND-binary condition, got \(cond)")
        }
        XCTAssertEqual(right, .variable("c"))
        guard case .binary(_, .and, _) = left else {
            return XCTFail("expected nested AND on the left, got \(left)")
        }
    }

    /// Single-condition guards still produce a bare `guardExpr` (no regression).
    func testGuardWithSingleConditionUnchanged() throws {
        let node = try parse("guard a == 1 else { return }")
        guard case .guardExpr(let cond, _) = node else {
            return XCTFail("expected guardExpr, got \(node)")
        }
        if case .binary(_, .and, _) = cond {
            XCTFail("single-condition guard should not wrap in AND")
        }
    }

    // MARK: - (original task-4 test kept for regression)

    func testLexPreservesExistingKeywordsStillWork() throws {
        // Regression guard: the existing keyword set keeps lexing as before.
        let tokens = try tokenize("let var func struct if else for in while return true false nil self")
        let expected: [TokenType] = [
            .keyword(.let), .keyword(.var), .keyword(.func), .keyword(.struct),
            .keyword(.if), .keyword(.else), .keyword(.for), .keyword(.in),
            .keyword(.while), .keyword(.return),
            .boolean(true), .boolean(false),
            .keyword(.nil), .keyword(.self),
        ]
        for (i, t) in expected.enumerated() {
            XCTAssertEqual(tokens[i].type, t, "Token \(i) mismatch — existing keyword regressed")
        }
    }
}
