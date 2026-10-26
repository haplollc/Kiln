//
//  KEParser.swift
//  Kiln engine 2
//
//  Recursive-descent parser for the Swift Kiln runs. It follows Swift's own
//  whitespace rules: an operator with space on one side only is prefix or
//  postfix; `(`, `[` and `{` on a new line start a new statement; a line
//  that starts with `.member` continues the previous expression.
//

import Foundation

struct KEParser {
    private var toks: [KEToken]
    private var p = 0

    init(tokens: [KEToken]) {
        self.toks = Self.stripConditionalCompilation(tokens)
    }

    static func parse(_ source: String) throws -> KEProgram {
        var lexer = KELexer(source)
        var parser = KEParser(tokens: try lexer.tokenize())
        return try parser.parseProgram()
    }

    // MARK: - Token helpers

    private var cur: KEToken { toks[p] }
    private func ahead(_ o: Int) -> KEToken { p + o < toks.count ? toks[p + o] : toks[toks.count - 1] }
    private mutating func next() { if p < toks.count - 1 { p += 1 } }
    private var atEOF: Bool { if case .eof = cur.kind { return true }; return false }

    private func at(_ c: Character) -> Bool { cur.isPunct(c) }
    private func atIdent(_ s: String) -> Bool { cur.isIdent(s) }
    private func atOp(_ s: String) -> Bool { cur.isOp(s) }

    @discardableResult
    private mutating func eat(_ c: Character) -> Bool { if at(c) { next(); return true }; return false }
    @discardableResult
    private mutating func eatIdent(_ s: String) -> Bool { if atIdent(s) { next(); return true }; return false }

    private mutating func expect(_ c: Character, _ context: String = "") throws {
        guard eat(c) else { throw error("expected '\(c)'\(context.isEmpty ? "" : " " + context), found '\(cur)'") }
    }

    private func error(_ message: String) -> KESyntaxError {
        KESyntaxError(message: message, line: cur.line, col: cur.col)
    }

    private mutating func identifier(_ what: String = "a name") throws -> String {
        guard let s = cur.identValue else { throw error("expected \(what), found '\(cur)'") }
        next()
        return s
    }

    private static let keywords: Set<String> = ["let", "var", "if", "else", "guard", "switch", "case", "default", "for", "in",
        "while", "repeat", "return", "break", "continue", "fallthrough", "throw", "do", "catch", "defer", "func",
        "struct", "class", "enum", "protocol", "extension", "import", "init", "deinit", "where", "typealias", "actor"]

    // MARK: - #if

    /// Keeps the first branch of every `#if … #endif` (DEBUG, os(iOS), …).
    private static func stripConditionalCompilation(_ tokens: [KEToken]) -> [KEToken] {
        guard tokens.contains(where: { $0.isPunct("#") }) else { return tokens }
        var out: [KEToken] = []
        var stack: [Bool] = []          // per #if level: still in the kept branch?
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if t.isPunct("#"), i + 1 < tokens.count, let d = tokens[i + 1].identValue,
               ["if", "elseif", "else", "endif"].contains(d) {
                let line = tokens[i + 1].line
                i += 2
                if d == "if" || d == "elseif" {
                    while i < tokens.count, tokens[i].line == line, !(tokens[i].kind == .eof) { i += 1 }
                }
                switch d {
                case "if": stack.append(true)
                case "endif": if !stack.isEmpty { stack.removeLast() }
                default: if !stack.isEmpty { stack[stack.count - 1] = false }
                }
                continue
            }
            if !stack.contains(false) || t.kind == .eof { out.append(t) }
            i += 1
        }
        return out
    }

    // MARK: - Program

    mutating func parseProgram() throws -> KEProgram {
        var prog = KEProgram()
        while !atEOF {
            if eat(";") { continue }
            if at("#"), ahead(1).isIdent("Preview") {
                next(); next()
                if at("(") { try skipBalanced("(", ")") }
                prog.previews.append(try parseBlock())
                continue
            }
            let attrs = try parseAttributes()
            let mods = parseModifiers()
            if let decl = try parseDeclaration(attrs: attrs, mods: mods) {
                switch decl {
                case .type(let t): prog.types.append(t)
                case .function(let f): prog.functions.append(f)
                case .importDecl(let n): prog.imports.append(n)
                case .typeAlias: break
                }
                continue
            }
            prog.globals.append(contentsOf: try parseStatement(attrs: attrs, mods: mods))
        }
        return prog
    }

    // MARK: - Attributes & modifiers

    private mutating func parseAttributes() throws -> [KEAttribute] {
        var attrs: [KEAttribute] = []
        while at("@"), let name = ahead(1).identValue {
            next(); next()
            var full = name
            while at("."), let more = ahead(1).identValue, !ahead(1).spaceBefore { next(); next(); full += "." + more }
            var args: [KEArg] = []
            if at("("), !cur.spaceBefore {
                let save = p
                if let parsed = try? parseCallArguments() { args = parsed } else { p = save; try skipBalanced("(", ")") }
            }
            attrs.append(KEAttribute(name: full, args: args))
        }
        return attrs
    }

    private static let modifierWords: Set<String> = ["private", "fileprivate", "public", "internal", "open", "final",
        "static", "override", "required", "convenience", "mutating", "nonmutating", "lazy", "weak", "unowned",
        "dynamic", "optional", "indirect", "nonisolated", "isolated", "consuming", "borrowing", "package"]

    private static let declarationWords: Set<String> = ["func", "var", "let", "class", "struct", "enum", "protocol",
        "extension", "init", "subscript", "typealias", "actor", "deinit", "case", "convenience", "required"]

    private mutating func parseModifiers() -> Set<String> {
        var mods = Set<String>()
        while let w = cur.identValue {
            let following = ahead(1)
            let modifiesDeclaration = (following.identValue.map { Self.modifierWords.contains($0) || Self.declarationWords.contains($0) } ?? false)
                || (following.isPunct("(") && !following.spaceBefore && ahead(2).isIdent("set"))
            if Self.modifierWords.contains(w), modifiesDeclaration {
                // `optional` and `indirect` are only modifiers before a declaration keyword.
                if w == "optional" || w == "indirect", !(ahead(1).identValue.map { ["func", "var", "case", "enum", "let"].contains($0) } ?? false) { break }
                mods.insert(w); next()
                if at("("), !cur.spaceBefore { try? skipBalanced("(", ")") }   // private(set)
            } else if w == "class", let n = ahead(1).identValue, ["func", "var", "let"].contains(n) {
                mods.insert("static"); next()
            } else { break }
        }
        return mods
    }

    private mutating func skipBalanced(_ open: Character, _ close: Character) throws {
        guard eat(open) else { return }
        var depth = 1
        while depth > 0 {
            if atEOF { throw error("unbalanced '\(open)'") }
            if at(open) { depth += 1 } else if at(close) { depth -= 1 }
            next()
        }
    }

    // MARK: - Declarations

    private mutating func parseDeclaration(attrs: [KEAttribute], mods: Set<String>) throws -> KEDecl? {
        guard let w = cur.identValue else { return nil }
        switch w {
        case "import":
            next()
            if let k = cur.identValue, ["struct", "class", "enum", "func", "var", "let", "protocol", "typealias"].contains(k) { next() }
            var name = try identifier()
            while at("."), let more = ahead(1).identValue { next(); next(); name += "." + more }
            return .importDecl(name)
        case "struct", "class", "enum", "protocol", "extension", "actor":
            // `class func` handled by modifiers; a lone `class` here declares a type.
            return .type(try parseTypeDecl(attrs: attrs))
        case "func":
            return .function(try parseFunc(attrs: attrs, mods: mods))
        case "typealias":
            next()
            let name = try identifier()
            if at("<") { try skipAngles() }
            try expect("=")
            if let t = try? parseType() { return .typeAlias(name, t) }
            return .typeAlias(name, .named(name, []))
        default:
            return nil
        }
    }

    private mutating func parseTypeDecl(attrs: [KEAttribute]) throws -> KETypeDecl {
        let line = cur.line
        let kw = try identifier()
        let kind = KETypeKind(rawValue: kw) ?? .structType
        var name = try identifier("a type name")
        while at("."), let more = ahead(1).identValue { next(); next(); name += "." + more }   // extension A.B
        if atOp("<") { try skipAngles() }
        var inherits: [String] = []
        if eat(":") {
            repeat {
                if let t = try? parseType(), let n = t.name { inherits.append(n) }
            } while eat(",")
        }
        if atIdent("where") { while !at("{") && !atEOF { next() } }
        let decl = KETypeDecl(kind: kind, name: name, inherits: inherits, attributes: attrs, line: line)
        if kind == .protocolType {
            try skipBalanced("{", "}")
            return decl
        }
        try parseTypeBody(decl)
        return decl
    }

    private mutating func parseTypeBody(_ decl: KETypeDecl) throws {
        try expect("{", "to open the body of \(decl.name)")
        while !at("}") {
            if atEOF { throw error("missing '}' at the end of \(decl.name)") }
            if eat(";") { continue }
            let attrs = try parseAttributes()
            let mods = parseModifiers()
            guard let w = cur.identValue else { throw error("unexpected '\(cur)' in the body of \(decl.name)") }
            switch w {
            case "case":
                next()
                repeat {
                    let cname = try identifier("a case name")
                    var assoc: [(String?, KETypeRef)] = []
                    if at("(") {
                        next()
                        while !at(")") {
                            var label: String? = nil
                            if let l = cur.identValue, ahead(1).isPunct(":") { label = l; next(); next() }
                            assoc.append((label, try parseType()))
                            if at("=") { next(); _ = try parseExpression() }   // default payload
                            if !eat(",") { break }
                        }
                        try expect(")")
                    }
                    var raw: KEExpr? = nil
                    if atOp("=") { next(); raw = try parseExpression() }
                    decl.cases.append(KEEnumCase(name: cname, associated: assoc, rawValue: raw))
                } while eat(",")
            case "var", "let":
                decl.properties.append(contentsOf: try parseVarDecl(attrs: attrs, mods: mods, inType: true))
            case "func":
                decl.methods.append(try parseFunc(attrs: attrs, mods: mods))
            case "init":
                decl.inits.append(try parseInit(attrs: attrs))
            case "deinit":
                next(); try skipBalanced("{", "}")
            case "subscript":
                next()
                let params = try parseParams()
                var ret: KETypeRef? = nil
                if atOp("->") { next(); ret = try parseType() }
                var body: [KEStmt] = []
                if at("{") {
                    let save = p
                    next()
                    if atIdent("get") {
                        p = save
                        next()
                        while !at("}") && !atEOF {
                            if eatIdent("get") { body = try parseBlock() }
                            else if eatIdent("set") { if at("(") { try skipBalanced("(", ")") }; _ = try parseBlock() }
                            else { next() }
                        }
                        try expect("}")
                    } else { p = save; body = try parseBlock() }
                }
                decl.subscripts.append(KEFuncDecl(name: "subscript", params: params, returnType: ret, body: body,
                                                  isStatic: mods.contains("static"), isMutating: false, attributes: attrs, line: cur.line))
            case "struct", "class", "enum", "protocol", "extension", "actor":
                decl.nested.append(try parseTypeDecl(attrs: attrs))
            case "typealias":
                next(); _ = try identifier(); if eat("=") || atOp("=") { if atOp("=") { next() }; _ = try? parseType() }
            case "associatedtype":
                next(); _ = try identifier(); if eat(":") { _ = try? parseType() }
            default:
                throw error("unexpected '\(w)' in the body of \(decl.name)")
            }
        }
        next()
    }

    private mutating func skipAngles() throws {
        var depth = 0
        repeat {
            if let o = cur.opValue {
                for ch in o { if ch == "<" { depth += 1 } else if ch == ">" { depth -= 1 } }
            }
            next()
        } while depth > 0 && !atEOF
    }

    private mutating func parseFunc(attrs: [KEAttribute], mods: Set<String>) throws -> KEFuncDecl {
        let line = cur.line
        next()  // func
        var name: String
        if let n = cur.identValue { name = n; next() }
        else if let o = cur.opValue { name = o; next() }   // operator func
        else { throw error("expected a function name") }
        if atOp("<") { try skipAngles() }
        let params = try parseParams()
        while let w = cur.identValue, ["async", "throws", "rethrows", "reasync"].contains(w) { next() }
        var ret: KETypeRef? = nil
        if atOp("->") { next(); ret = try parseType() }
        if atIdent("where") { while !at("{") && !atEOF { next() } }
        let body = at("{") ? try parseBlock() : []
        return KEFuncDecl(name: name, params: params, returnType: ret, body: body, isStatic: mods.contains("static"),
                          isMutating: mods.contains("mutating"), attributes: attrs, line: line)
    }

    private mutating func parseInit(attrs: [KEAttribute]) throws -> KEFuncDecl {
        let line = cur.line
        next()  // init
        var attributes = attrs
        if atOp("?") || atOp("!") { next(); attributes.append(KEAttribute(name: "Failable", args: [])) }
        if atOp("<") { try skipAngles() }
        let params = try parseParams()
        while let w = cur.identValue, ["async", "throws", "rethrows"].contains(w) { next() }
        if atIdent("where") { while !at("{") && !atEOF { next() } }
        let body = at("{") ? try parseBlock() : []
        return KEFuncDecl(name: "init", params: params, returnType: nil, body: body, isStatic: false,
                          isMutating: true, attributes: attributes, line: line)
    }

    private mutating func parseParams() throws -> [KEParam] {
        try expect("(", "to start the parameters")
        var params: [KEParam] = []
        while !at(")") {
            _ = try parseAttributes()
            let first = try identifier("a parameter name")
            var label: String? = first
            var name = first
            if let second = cur.identValue, !at(":") { name = second; next(); label = first }
            if first == "_" { label = nil }
            var type: KETypeRef? = nil
            var isInout = false
            var variadic = false
            if eat(":") {
                _ = try parseAttributes()
                if eatIdent("inout") { isInout = true }
                type = try parseType()
                if atOp("...") { next(); variadic = true }
            }
            var def: KEExpr? = nil
            if atOp("=") { next(); def = try parseExpression() }
            params.append(KEParam(label: label, name: name, type: type, defaultValue: def, isInout: isInout, isVariadic: variadic))
            if !eat(",") { break }
        }
        try expect(")", "to close the parameters")
        return params
    }

    /// `var a: T = x`, `let a = 1, b = 2`, `var body: some View { … }`, `var x = 0 { didSet { … } }`.
    private mutating func parseVarDecl(attrs: [KEAttribute], mods: Set<String>, inType: Bool) throws -> [KEVarDecl] {
        let isLet = atIdent("let")
        next()
        var decls: [KEVarDecl] = []
        repeat {
            let line = cur.line
            let pattern: KEPattern
            if at("(") { pattern = try parsePattern(binding: true) }
            else { pattern = .binding(try identifier("a variable name"), isVar: !isLet) }
            var type: KETypeRef? = nil
            if eat(":") { type = try parseType() }
            var initial: KEExpr? = nil
            if atOp("=") { next(); initial = try parseExpression() }
            var getter: [KEStmt]? = nil
            var setter: (String, [KEStmt])? = nil
            var willSet: (String, [KEStmt])? = nil
            var didSet: (String, [KEStmt])? = nil
            if at("{"), !(initial != nil && cur.newlineBefore) {
                // Accessor block or getter body.
                let save = p
                next()
                let first = cur.identValue
                if let f = first, ["get", "set", "willSet", "didSet", "_read", "_modify"].contains(f),
                   ahead(1).isPunct("{") || ahead(1).isPunct("(") || ahead(1).isPunct("}") || f == "get" {
                    while !at("}") {
                        if atEOF { throw error("missing '}' after accessors") }
                        _ = try parseAttributes()
                        let acc = try identifier("an accessor")
                        var param = acc == "set" || acc == "willSet" ? "newValue" : "oldValue"
                        if at("(") { next(); param = try identifier(); try expect(")") }
                        while let w = cur.identValue, ["async", "throws"].contains(w) { next() }
                        let body = at("{") ? try parseBlock() : []
                        switch acc {
                        case "get": getter = body
                        case "set": setter = (param, body)
                        case "willSet": willSet = (param, body)
                        case "didSet": didSet = (param, body)
                        default: break
                        }
                    }
                    next()
                } else {
                    p = save
                    getter = try parseBlock()
                }
            }
            decls.append(KEVarDecl(pattern: pattern, isLet: isLet, isStatic: mods.contains("static"), type: type,
                                   initial: initial, attributes: attrs, getter: getter, setter: setter,
                                   willSet: willSet, didSet: didSet, isLazy: mods.contains("lazy"), line: line))
        } while eat(",")
        return decls
    }

    // MARK: - Types

    mutating func parseType() throws -> KETypeRef {
        _ = try parseAttributes()
        if eatIdent("inout") {}
        var t: KETypeRef
        if eatIdent("some") || eatIdent("any") {
            t = .opaque(try parseType())
            return t
        }
        if at("[") {
            next()
            let first = try parseType()
            if eat(":") {
                let v = try parseType()
                try expect("]")
                t = .dictionary(first, v)
            } else {
                try expect("]")
                t = .array(first)
            }
        } else if at("(") {
            next()
            var elems: [KETypeRef] = []
            while !at(")") {
                if cur.identValue != nil, ahead(1).isPunct(":") { next(); next() }
                else if cur.identValue != nil, ahead(1).identValue != nil, ahead(2).isPunct(":") { next(); next(); next() }
                elems.append(try parseType())
                if atOp("...") { next() }
                if !eat(",") { break }
            }
            try expect(")")
            while let w = cur.identValue, ["async", "throws"].contains(w) { next() }
            if atOp("->") {
                next()
                t = .function(elems, try parseType())
            } else {
                t = elems.count == 1 ? elems[0] : .tuple(elems)
            }
        } else {
            var name = try identifier("a type")
            var args: [KETypeRef] = []
            if atOp("<") || (cur.opValue?.hasPrefix("<") ?? false) {
                args = try parseGenericArgs()
            }
            while at("."), let more = ahead(1).identValue {
                next(); next()
                if more == "Type" || more == "Protocol" { continue }
                name += "." + more
                if atOp("<") { args = try parseGenericArgs() }
            }
            t = .named(name, args)
        }
        while true {
            if atOp("?") && !cur.spaceBefore { next(); t = .optional(t) }
            else if atOp("!") && !cur.spaceBefore { next(); t = .optional(t) }
            else if at("."), ahead(1).isIdent("Type") { next(); next() }
            else { break }
        }
        if atOp("->") {   // `Int -> Bool` without parens (old style)
            next()
            t = .function([t], try parseType())
        }
        return t
    }

    private mutating func parseGenericArgs() throws -> [KETypeRef] {
        // Accept `<`, then types, then `>`; split `>>` / `>?` style tokens.
        guard let o = cur.opValue, o.hasPrefix("<") else { return [] }
        if o == "<" { next() } else { toks[p].kind = .op(String(o.dropFirst())) }
        var args: [KETypeRef] = []
        while true {
            args.append(try parseType())
            if eat(",") { continue }
            break
        }
        guard let c = cur.opValue, c.hasPrefix(">") else { throw error("expected '>' after generic arguments") }
        if c == ">" { next() } else { toks[p].kind = .op(String(c.dropFirst())) }
        return args
    }

    // MARK: - Statements

    private mutating func parseBlock() throws -> [KEStmt] {
        try expect("{")
        var stmts: [KEStmt] = []
        while !at("}") {
            if atEOF { throw error("missing '}'") }
            if eat(";") { continue }
            stmts.append(contentsOf: try parseStatement())
        }
        next()
        return stmts
    }

    private mutating func parseStatement(attrs: [KEAttribute] = [], mods: Set<String> = []) throws -> [KEStmt] {
        var attrs = attrs
        var mods = mods
        if attrs.isEmpty, at("@") { attrs = try parseAttributes() }
        if mods.isEmpty { mods = parseModifiers() }
        let line = cur.line
        guard let w = cur.identValue else { return [try parseExpressionStatement()] }

        // Labeled loop: `outer: for …`
        if !Self.keywords.contains(w), ahead(1).isPunct(":"), let k = ahead(2).identValue, ["for", "while", "repeat"].contains(k) {
            next(); next()
            return try parseLoop(label: w)
        }

        switch w {
        case "let", "var":
            return try parseVarDecl(attrs: attrs, mods: mods, inType: false).map { .variable($0) }
        case "if":
            return [try parseIf()]
        case "guard":
            next()
            let conds = try parseConditions()
            guard eatIdent("else") else { throw error("expected 'else' after guard condition") }
            return [.guardStmt(conds, try parseBlock())]
        case "switch":
            next()
            let subject = try parseExpression(noTrailing: true)
            return [.switchStmt(subject, try parseSwitchBody())]
        case "for", "while", "repeat":
            return try parseLoop(label: nil)
        case "return":
            next()
            if at("}") || at(";") || atEOF || cur.newlineBefore || atIdent("case") || atIdent("default") {
                return [.returnStmt(nil, line: line)]
            }
            return [.returnStmt(try parseExpression(), line: line)]
        case "break":
            next()
            if let l = cur.identValue, !cur.newlineBefore, !Self.keywords.contains(l) { next(); return [.breakStmt(l)] }
            return [.breakStmt(nil)]
        case "continue":
            next()
            if let l = cur.identValue, !cur.newlineBefore, !Self.keywords.contains(l) { next(); return [.continueStmt(l)] }
            return [.continueStmt(nil)]
        case "fallthrough":
            next(); return [.fallthroughStmt]
        case "throw":
            next(); return [.throwStmt(try parseExpression())]
        case "do":
            next()
            let body = try parseBlock()
            var catches: [KECatch] = []
            while eatIdent("catch") {
                var pattern: KEPattern? = nil
                if !at("{") {
                    if eatIdent("let") || eatIdent("var") {
                        let n = try identifier()
                        pattern = .binding(n, isVar: false)
                        while !at("{") && !atEOF { next() }
                    } else {
                        while !at("{") && !atEOF { next() }
                    }
                }
                catches.append(KECatch(pattern: pattern, body: try parseBlock()))
            }
            return [.doCatch(body, catches)]
        case "defer":
            next(); return [.deferStmt(try parseBlock())]
        case "func":
            return [.declaration(.function(try parseFunc(attrs: attrs, mods: mods)))]
        case "struct", "class", "enum", "protocol", "extension", "actor":
            if w == "class", ahead(1).identValue.map({ ["func", "var"].contains($0) }) == true { break }
            return [.declaration(.type(try parseTypeDecl(attrs: attrs)))]
        case "typealias":
            next(); _ = try identifier(); if atOp("=") { next(); _ = try? parseType() }
            return []
        case "import":
            if case .some(.importDecl) = try parseDeclaration(attrs: [], mods: []) { return [] }
        default:
            break
        }
        return [try parseExpressionStatement()]
    }

    private static let assignOps: Set<String> = ["=", "+=", "-=", "*=", "/=", "%=", "&&=", "||=", "??=", "<<=", ">>=", "&=", "|=", "^="]

    private mutating func parseExpressionStatement() throws -> KEStmt {
        let line = cur.line
        let e = try parseExpression()
        if let o = cur.opValue, Self.assignOps.contains(o) {
            next()
            let v = try parseExpression()
            return .assign(o, e, v, line: line)
        }
        return .expr(e)
    }

    private mutating func parseIf() throws -> KEStmt {
        next()  // if
        let conds = try parseConditions()
        let then = try parseBlock()
        var elseClause: KEElse? = nil
        if eatIdent("else") {
            if atIdent("if") { elseClause = .elseIf(try parseIf()) }
            else { elseClause = .block(try parseBlock()) }
        }
        return .ifStmt(conds, then, elseClause)
    }

    private mutating func parseConditions() throws -> [KECondition] {
        var conds: [KECondition] = []
        repeat {
            if at("#"), ahead(1).isIdent("available") || ahead(1).isIdent("unavailable") {
                next(); next(); try skipBalanced("(", ")")
                conds.append(.available)
            } else if atIdent("let") || atIdent("var") {
                let isVar = atIdent("var")
                next()
                let pattern: KEPattern = at("(") ? try parsePattern(binding: true) : .binding(try identifier(), isVar: isVar)
                if eat(":") { _ = try parseType() }
                if atOp("=") {
                    next()
                    conds.append(.optionalBinding(pattern, try parseExpression(noTrailing: true)))
                } else if case .binding(let n, _) = pattern {
                    conds.append(.optionalBinding(pattern, .ident(n, line: cur.line)))   // if let x
                }
            } else if atIdent("case") {
                next()
                let pattern = try parsePattern(binding: false)
                guard atOp("=") else { throw error("expected '=' in 'case' condition") }
                next()
                conds.append(.casePattern(pattern, try parseExpression(noTrailing: true)))
            } else {
                conds.append(.expr(try parseExpression(noTrailing: true)))
            }
        } while eat(",")
        return conds
    }

    private mutating func parseLoop(label: String?) throws -> [KEStmt] {
        if eatIdent("for") {
            if eatIdent("case") {}
            if atIdent("await") { next() }
            let pattern = try parsePattern(binding: true)
            guard eatIdent("in") else { throw error("expected 'in' in for loop") }
            let seq = try parseExpression(noTrailing: true)
            var whereClause: KEExpr? = nil
            if eatIdent("where") { whereClause = try parseExpression(noTrailing: true) }
            return [.forIn(pattern, seq, whereClause, try parseBlock(), label: label)]
        }
        if eatIdent("while") {
            let conds = try parseConditions()
            return [.whileStmt(conds, try parseBlock(), label: label)]
        }
        next()  // repeat
        let body = try parseBlock()
        guard eatIdent("while") else { throw error("expected 'while' after repeat block") }
        return [.repeatWhile(body, try parseExpression(), label: label)]
    }

    private mutating func parseSwitchBody() throws -> [KESwitchCase] {
        try expect("{", "to open the switch")
        var cases: [KESwitchCase] = []
        while !at("}") {
            if atEOF { throw error("missing '}' after switch") }
            _ = try parseAttributes()   // @unknown
            if eatIdent("default") {
                try expect(":")
                cases.append(KESwitchCase(patterns: [], body: try parseCaseBody(), isDefault: true))
                continue
            }
            guard eatIdent("case") else { throw error("expected 'case' or 'default' in switch, found '\(cur)'") }
            var patterns: [(KEPattern, KEExpr?)] = []
            repeat {
                let pat = try parsePattern(binding: false)
                var whereExpr: KEExpr? = nil
                if eatIdent("where") { whereExpr = try parseExpression() }
                patterns.append((pat, whereExpr))
            } while eat(",")
            try expect(":", "after the case pattern")
            cases.append(KESwitchCase(patterns: patterns, body: try parseCaseBody(), isDefault: false))
        }
        next()
        return cases
    }

    private mutating func parseCaseBody() throws -> [KEStmt] {
        var stmts: [KEStmt] = []
        while !at("}") && !atIdent("case") && !atIdent("default") && !(at("@") && ahead(1).isIdent("unknown")) {
            if atEOF { throw error("missing '}' after switch") }
            if eat(";") { continue }
            stmts.append(contentsOf: try parseStatement())
        }
        return stmts
    }

    // MARK: - Patterns

    private mutating func parsePattern(binding: Bool) throws -> KEPattern {
        var pat = try parsePatternPrimary(binding: binding)
        if atIdent("as"), !binding || true, ahead(1).identValue != nil, case .binding = pat {
            next(); pat = .cast(pat, try parseType())
        }
        return pat
    }

    private mutating func parsePatternPrimary(binding: Bool) throws -> KEPattern {
        if atIdent("_") { next(); return .wildcard }
        if atIdent("let") || atIdent("var") {
            let isVar = atIdent("var")
            next()
            var inner = try parsePatternPrimary(binding: true)
            if case .binding(let n, _) = inner { inner = .binding(n, isVar: isVar) }
            return inner
        }
        if atIdent("is") { next(); return .typeCheck(try parseType()) }
        if at("(") {
            next()
            var elems: [KEPattern] = []
            while !at(")") {
                if cur.identValue != nil, ahead(1).isPunct(":") { next(); next() }   // labeled tuple element
                elems.append(try parsePattern(binding: binding))
                if !eat(",") { break }
            }
            try expect(")")
            return elems.count == 1 ? elems[0] : .tuple(elems)
        }
        if at("."), let name = ahead(1).identValue {
            next(); next()
            var sub: [KEPattern] = []
            if at("("), !cur.newlineBefore {
                next()
                while !at(")") {
                    if cur.identValue != nil, ahead(1).isPunct(":"), !ahead(1).spaceBefore || true,
                       !(cur.identValue == "let" || cur.identValue == "var") { next(); next() }
                    sub.append(try parsePattern(binding: binding))
                    if !eat(",") { break }
                }
                try expect(")")
            }
            return .enumCase(type: nil, name: name, sub)
        }
        if binding, let n = cur.identValue, !Self.keywords.contains(n) {
            next()
            if atOp("?") && !cur.spaceBefore { next(); return .optional(.binding(n, isVar: false)) }
            return .binding(n, isVar: false)
        }
        // Qualified enum case `Kind.a(let x)` or a plain value.
        if let n = cur.identValue, n.first?.isUppercase == true, ahead(1).isPunct("."), let c = ahead(2).identValue,
           ahead(3).isPunct("(") {
            next(); next(); next()
            next()
            var sub: [KEPattern] = []
            while !at(")") {
                sub.append(try parsePattern(binding: binding))
                if !eat(",") { break }
            }
            try expect(")")
            return .enumCase(type: n, name: c, sub)
        }
        let e = try parseExpression(noTrailing: true, stopAtColon: true)
        if atOp("?") && !cur.spaceBefore, case .ident(let n, _) = e { next(); return .optional(.binding(n, isVar: false)) }
        return .expression(e)
    }

    // MARK: - Expressions

    mutating func parseExpression(noTrailing: Bool = false, stopAtColon: Bool = false) throws -> KEExpr {
        let cond = try parseBinary(0, noTrailing: noTrailing)
        if atOp("?"), cur.spaceBefore {
            next()
            let t = try parseExpression(noTrailing: noTrailing)
            try expect(":", "in the ternary expression")
            let f = try parseExpression(noTrailing: noTrailing, stopAtColon: stopAtColon)
            return .ternary(cond, t, f)
        }
        return cond
    }

    private static let precedence: [String: Int] = [
        "||": 1, "&&": 2,
        "==": 3, "!=": 3, "<": 3, ">": 3, "<=": 3, ">=": 3, "===": 3, "!==": 3, "~=": 3,
        "??": 4,
        "is": 5, "as": 5,
        "..<": 6, "...": 6,
        "+": 7, "-": 7, "|": 7, "^": 7, "&+": 7, "&-": 7,
        "*": 8, "/": 8, "%": 8, "&": 8, "&*": 8,
        "<<": 9, ">>": 9,
    ]

    /// An operator token works as a binary operator: spaces on both sides or neither,
    /// or at the start of a continued line followed by a space.
    private func binaryOp() -> String? {
        if let w = cur.identValue, w == "is" || w == "as", !cur.newlineBefore { return w }
        guard let o = cur.opValue, Self.precedence[o] != nil else { return nil }
        if cur.newlineBefore { return cur.spaceAfter ? o : nil }
        if cur.spaceBefore != cur.spaceAfter {
            // `a ..< b` style is binary; `x-1` too. `-x` after a space is prefix.
            return nil
        }
        return o
    }

    private mutating func parseBinary(_ minPrec: Int, noTrailing: Bool) throws -> KEExpr {
        var left = try parseUnary(noTrailing: noTrailing)
        while let op = binaryOp(), let prec = Self.precedence[op], prec > minPrec {
            let line = cur.line
            next()
            if op == "is" {
                left = .cast(left, "is", try parseType())
                continue
            }
            if op == "as" {
                var kind = "as"
                if atOp("?") && !cur.spaceBefore { next(); kind = "as?" }
                else if atOp("!") && !cur.spaceBefore { next(); kind = "as!" }
                left = .cast(left, kind, try parseType())
                continue
            }
            let rightAssoc = op == "??"
            let right = try parseBinary(rightAssoc ? prec - 1 : prec, noTrailing: noTrailing)
            left = .binary(op, left, right, line: line)
        }
        return left
    }

    private mutating func parseUnary(noTrailing: Bool) throws -> KEExpr {
        if let w = cur.identValue {
            if w == "try" {
                next()
                var kind = "try"
                if atOp("?") && !cur.spaceBefore { next(); kind = "try?" }
                else if atOp("!") && !cur.spaceBefore { next(); kind = "try!" }
                return .tryExpr(kind, try parseUnary(noTrailing: noTrailing))
            }
            if w == "await" { next(); return .awaitExpr(try parseUnary(noTrailing: noTrailing)) }
        }
        if let o = cur.opValue, ["-", "+", "!", "~", "&", "..<", "..."].contains(o) {
            next()
            if o == "..<" || o == "..." { return .prefix(o, try parseUnary(noTrailing: noTrailing)) }
            let operand = try parseUnary(noTrailing: noTrailing)
            if o == "-", case .int(let i) = operand { return .int(-i) }
            if o == "-", case .double(let d) = operand { return .double(-d) }
            return .prefix(o, operand)
        }
        return try parsePostfix(try parsePrimary(noTrailing: noTrailing), noTrailing: noTrailing)
    }

    private mutating func parsePostfix(_ base: KEExpr, noTrailing: Bool) throws -> KEExpr {
        var e = base
        while true {
            let line = cur.line
            if at(".") {
                // A `.` on a new line continues the chain (SwiftUI modifiers).
                let n = ahead(1)
                if let name = n.identValue {
                    next(); next()
                    e = .member(e, name, line: line)
                    continue
                }
                if case .int(let i) = n.kind {   // tuple.0
                    next(); next()
                    e = .member(e, String(i), line: line)
                    continue
                }
                if case .double(let d) = n.kind {   // tuple.0.1 lexed as a double
                    next(); next()
                    let parts = String(d).split(separator: ".")
                    for part in parts { e = .member(e, String(part), line: line) }
                    continue
                }
                break
            }
            if at("("), !cur.newlineBefore {
                let args = try parseCallArguments()
                e = .call(e, args + (noTrailing ? [] : try parseTrailingClosures()), line: line)
                continue
            }
            if at("["), !cur.newlineBefore, !cur.spaceBefore || isSubscriptable(e) {
                next()
                var args: [KEArg] = []
                while !at("]") {
                    var label: String? = nil
                    if let l = cur.identValue, ahead(1).isPunct(":"), !Self.keywords.contains(l) { label = l; next(); next() }
                    args.append(KEArg(label: label, value: try parseExpression()))
                    if !eat(",") { break }
                }
                try expect("]")
                e = .subscriptAccess(e, args, line: line)
                continue
            }
            if at("{"), !noTrailing, !cur.newlineBefore, canTakeTrailingClosure(e) {
                let trailing = try parseTrailingClosures()
                e = .call(e, trailing, line: line)
                continue
            }
            if atOp("!"), !cur.spaceBefore { next(); e = .postfix("!", e); continue }
            if atOp("?"), !cur.spaceBefore { next(); e = .optionalChain(e); continue }
            if atOp("..."), !cur.spaceBefore, ahead(1).isPunct("]") || ahead(1).isPunct(")") || ahead(1).isPunct(",") {
                next(); e = .postfix("...", e); continue
            }
            break
        }
        return e
    }

    private func isSubscriptable(_ e: KEExpr) -> Bool {
        switch e {
        case .ident, .member, .call, .subscriptAccess, .selfRef, .postfix, .optionalChain: return true
        default: return false
        }
    }

    /// Trailing closures attach to calls, identifiers and members — not to
    /// literals or operators (`x == y {` in an `if` is handled by noTrailing).
    private func canTakeTrailingClosure(_ e: KEExpr) -> Bool {
        switch e {
        case .ident(let n, _): return !Self.keywords.contains(n)
        case .member, .call, .implicitMember, .typeExpr: return true
        default: return false
        }
    }

    mutating func parseCallArguments() throws -> [KEArg] {
        try expect("(")
        var args: [KEArg] = []
        while !at(")") {
            if atEOF { throw error("missing ')'") }
            var label: String? = nil
            if let l = cur.identValue, ahead(1).isPunct(":") {
                label = l; next(); next()
                // Models sometimes double a label: `y: height: value`.
                while cur.identValue != nil, ahead(1).isPunct(":"), !ahead(2).isPunct(":") { next(); next() }
            }
            // Operator references: `reduce(0, +)`, `sorted(by: <)`.
            if let o = cur.opValue, Self.precedence[o] != nil, ahead(1).isPunct(")") || ahead(1).isPunct(",") {
                next()
                args.append(KEArg(label: label, value: .ident(o, line: cur.line)))
            } else {
                args.append(KEArg(label: label, value: try parseExpression()))
            }
            if !eat(",") { break }
        }
        try expect(")", "to close the argument list")
        return args
    }

    private mutating func parseTrailingClosures() throws -> [KEArg] {
        var args: [KEArg] = []
        // `Button(action: { … }) label: { … }` — a labeled closure straight after the parens.
        if let l = cur.identValue, !cur.newlineBefore, ahead(1).isPunct(":"), ahead(2).isPunct("{"), !Self.keywords.contains(l) {
            next(); next()
            args.append(KEArg(label: l, value: .closure(try parseClosure())))
        }
        guard at("{"), !cur.newlineBefore || !args.isEmpty, args.isEmpty else { return args.isEmpty ? args : try moreLabeledClosures(args) }
        args.append(KEArg(label: nil, value: .closure(try parseClosure())))
        // Labeled trailing closures: `} label: {`, `} header: {`
        while let l = cur.identValue, !cur.newlineBefore, ahead(1).isPunct(":"), ahead(2).isPunct("{"),
              !Self.keywords.contains(l) {
            next(); next()
            args.append(KEArg(label: l, value: .closure(try parseClosure())))
        }
        return args
    }

    private mutating func moreLabeledClosures(_ start: [KEArg]) throws -> [KEArg] {
        var args = start
        while let l = cur.identValue, !cur.newlineBefore, ahead(1).isPunct(":"), ahead(2).isPunct("{"), !Self.keywords.contains(l) {
            next(); next()
            args.append(KEArg(label: l, value: .closure(try parseClosure())))
        }
        return args
    }

    private mutating func parseClosure() throws -> KEClosure {
        let line = cur.line
        try expect("{")
        var params: [KEClosure.Param] = []
        var explicit = false
        let save = p
        if let sig = try? parseClosureSignature(), atIdent("in") {
            next()
            params = sig
            explicit = true
        } else {
            p = save
        }
        var body: [KEStmt] = []
        while !at("}") {
            if atEOF { throw KESyntaxError(message: "missing '}' to close the closure that starts here", line: line, col: 0) }
            if eat(";") { continue }
            body.append(contentsOf: try parseStatement())
        }
        next()
        return KEClosure(params: params, body: body, hasExplicitParams: explicit, line: line)
    }

    private mutating func parseClosureSignature() throws -> [KEClosure.Param] {
        if at("[") { try skipBalanced("[", "]") }      // capture list
        var params: [KEClosure.Param] = []
        if at("(") {
            next()
            while !at(")") {
                var name = try identifier()
                if let second = cur.identValue, !at(":"), second != "in" { name = second; next() }
                var type: KETypeRef? = nil
                if eat(":") { type = try parseType() }
                params.append(.init(name: name, type: type))
                if !eat(",") { break }
            }
            try expect(")")
        } else if atIdent("in") {
            return []
        } else {
            while let n = cur.identValue, n != "in" {
                if Self.keywords.contains(n) && n != "_" { throw error("not a closure signature") }
                next()
                params.append(.init(name: n, type: nil))
                if !eat(",") { break }
            }
        }
        while let w = cur.identValue, ["async", "throws"].contains(w) { next() }
        if atOp("->") { next(); _ = try parseType() }
        guard atIdent("in") else { throw error("not a closure signature") }
        return params
    }

    private mutating func parsePrimary(noTrailing: Bool) throws -> KEExpr {
        let t = cur
        let line = t.line
        switch t.kind {
        case .int(let i): next(); return .int(i)
        case .double(let d): next(); return .double(d)
        case .string(let parts, _):
            next()
            var segs: [KEStringSegment] = []
            for part in parts {
                switch part {
                case .text(let s): segs.append(.text(s))
                case .interp(let src, let l):
                    var lx = KELexer(src, lineOffset: l - 1)
                    var sub = KEParser(tokens: try lx.tokenize())
                    var args: [KEArg] = []
                    while !sub.atEOF {
                        var label: String? = nil
                        if let lab = sub.cur.identValue, sub.ahead(1).isPunct(":") { label = lab; sub.next(); sub.next() }
                        args.append(KEArg(label: label, value: try sub.parseExpression()))
                        if !sub.eat(",") { break }
                    }
                    segs.append(.interp(args))
                }
            }
            return .string(segs)
        case .ident(let name):
            switch name {
            case "true": next(); return .bool(true)
            case "false": next(); return .bool(false)
            case "nil": next(); return .nilLit
            case "self": next(); return .selfRef(line: line)
            case "if":
                // if-expression: `let x = if a { 1 } else { 2 }`
                next()
                let conds = try parseConditions()
                let then = try parseBlock()
                var other: [KEStmt] = []
                if eatIdent("else") {
                    if atIdent("if") { other = [.expr(try parsePrimary(noTrailing: noTrailing))] }
                    else { other = try parseBlock() }
                }
                return .ifExpr(conds, then, other)
            case "switch":
                next()
                let subject = try parseExpression(noTrailing: true)
                return .switchExpr(subject, try parseSwitchBody())
            default:
                next()
                // Generic type used as a value: Set<Int>(), Array<String>.init()
                if name.first?.isUppercase == true, atOp("<"), !cur.spaceBefore {
                    let save = p
                    if let args = try? parseGenericArgs(), at("(") || at(".") {
                        return .typeExpr(.named(name, args))
                    }
                    p = save
                }
                return .ident(name, line: line)
            }
        case .punct(let c):
            switch c {
            case ".":
                next()
                let name = try identifier("a member name after '.'")
                return .implicitMember(name, line: line)
            case "(":
                next()
                var elems: [(String?, KEExpr)] = []
                while !at(")") {
                    var label: String? = nil
                    if let l = cur.identValue, ahead(1).isPunct(":"), !Self.keywords.contains(l) { label = l; next(); next() }
                    elems.append((label, try parseExpression()))
                    if !eat(",") { break }
                }
                try expect(")")
                if elems.count == 1, elems[0].0 == nil { return elems[0].1 }
                return .tuple(elems)
            case "[":
                next()
                if eat("]") { return .array([]) }
                if at(":") && ahead(1).isPunct("]") { next(); next(); return .dictionary([]) }
                let first = try parseExpression()
                if eat(":") {
                    var pairs: [(KEExpr, KEExpr)] = [(first, try parseExpression())]
                    while eat(",") {
                        if at("]") { break }
                        let k = try parseExpression()
                        try expect(":")
                        pairs.append((k, try parseExpression()))
                    }
                    try expect("]")
                    return .dictionary(pairs)
                }
                var elems = [first]
                while eat(",") {
                    if at("]") { break }
                    elems.append(try parseExpression())
                }
                try expect("]")
                return .array(elems)
            case "{":
                return .closure(try parseClosure())
            case "\\":
                next()
                var root: String? = nil
                if let r = cur.identValue { root = r; next() }
                var comps: [String] = []
                while at(".") {
                    next()
                    if let n = cur.identValue { comps.append(n); next() }
                    else if case .int(let i) = cur.kind { comps.append(String(i)); next() }
                    if atOp("?") || atOp("!") { next() }
                }
                return .keyPath(root: root, comps)
            case "#":
                next()
                let name = try identifier()
                if at("(") { try skipBalanced("(", ")") }
                if name == "line" { return .int(line) }
                return .string([.text("#" + name)])
            default:
                break
            }
        case .op(let o):
            throw error("unexpected '\(o)'")
        default:
            break
        }
        throw error("unexpected '\(t)'")
    }
}
