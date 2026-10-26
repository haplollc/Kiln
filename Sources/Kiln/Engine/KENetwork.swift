//
//  KENetwork.swift
//  Kiln engine 2
//
//  URLSession and JSONDecoder for interpreted code.
//  - `try await URLSession.shared.data(from:)` (or `for: URLRequest`) fetches
//    and returns `(Data, URLResponse)`. Interpreted code has no suspension
//    points, so the call waits for the response (at most 20 seconds).
//  - `URLSession.shared.dataTask(with:) { data, response, error in … }.resume()`
//    fetches in the background and calls back on the main thread.
//  - `JSONDecoder().decode(T.self, from:)` builds your own Decodable types
//    from the JSON by their stored properties: CodingKeys, optionals, default
//    values, nested types, arrays, raw-value enums, `.convertFromSnakeCase`
//    and `.iso8601` dates.
//

import Foundation

/// A JSONDecoder's settings.
final class KDecoderBox {
    var snakeCase = false
    var iso8601 = false
}

/// `URLSession.shared.dataTask(with:completionHandler:)`, until `resume()`.
final class KDataTask {
    let request: URLRequest
    let completion: KFunction?
    var task: URLSessionDataTask?
    init(request: URLRequest, completion: KFunction?) {
        self.request = request
        self.completion = completion
    }
}

extension KBuiltins {
    static func data(_ d: Data) -> KV { .native(.object("Data", KRef(d as NSData))) }

    static func dataValue(_ v: KV?) -> Data? {
        if case .native(.object("Data", let ref))? = v { return ref.value as? Data }
        if case .string(let s)? = v { return Data(s.utf8) }
        return nil
    }

    static func request(_ v: KV?) -> URLRequest? {
        switch v {
        case .native(.url(let u))?: return URLRequest(url: u)
        case .native(.object("URLRequest", let ref))?: return (ref.value as? NSURLRequest).map { $0 as URLRequest }
        case .string(let s)?: return URL(string: s).map { URLRequest(url: $0) }
        default: return nil
        }
    }

    static func errorValue(_ message: String) -> KV {
        .native(.object("Error", KRef(NSError(domain: "Kiln", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))))
    }

    /// `try await URLSession.shared.data(from: url)`.
    @MainActor static func fetch(_ request: URLRequest, _ interp: KInterpreter, _ line: Int) throws -> KV {
        final class Result: @unchecked Sendable { var data: Data?; var response: URLResponse?; var error: Error? }
        let result = Result()
        let done = DispatchSemaphore(value: 0)
        var req = request
        req.timeoutInterval = min(req.timeoutInterval, 20)
        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            result.data = data; result.response = response; result.error = error
            done.signal()
        }
        task.resume()
        if done.wait(timeout: .now() + 20) == .timedOut {
            task.cancel()
            throw KEThrown(value: errorValue("The request timed out."))
        }
        if let error = result.error { throw KEThrown(value: errorValue(error.localizedDescription)) }
        return .tuple([data(result.data ?? Data()), .native(.object("HTTPURLResponse", KRef(result.response ?? URLResponse())))], [nil, nil])
    }

    @MainActor static func networkMethod(_ kind: String, _ ref: KRef<AnyObject>, _ name: String, _ args: [KV], _ labels: [String?],
                                         _ interp: KInterpreter, _ line: Int) throws -> KV? {
        func arg(_ l: String) -> KV? { labels.firstIndex(of: l).map { args[$0] } }
        switch (kind, name) {
        case ("URLSession", "data"):
            guard let req = request(arg("from") ?? arg("for") ?? args.first) else { throw interp.fail("URLSession.data needs a URL", line) }
            return try fetch(req, interp, line)
        case ("URLSession", "dataTask"):
            guard let req = request(arg("with") ?? args.first) else { throw interp.fail("URLSession.dataTask needs a URL", line) }
            var completion: KFunction?
            if case .function(let f)? = args.last { completion = f }
            return .native(.object("URLSessionDataTask", KRef(KDataTask(request: req, completion: completion))))
        case ("URLSessionDataTask", "resume"):
            guard let box = ref.value as? KDataTask, box.task == nil else { return .void }
            let completion = box.completion
            box.task = URLSession.shared.dataTask(with: box.request) { data, response, error in
                let d = data, r = response, e = error?.localizedDescription
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        interp.perform(completion, [d.map { KBuiltins.data($0) } ?? .nilValue,
                                                    r.map { .native(.object("HTTPURLResponse", KRef($0))) } ?? .nilValue,
                                                    e.map { errorValue($0) } ?? .nilValue])
                    }
                }
            }
            box.task?.resume()
            return .void
        case ("URLSessionDataTask", "cancel"):
            (ref.value as? KDataTask)?.task?.cancel()
            return .void
        case ("URLRequest", "setValue"):
            if let r = ref.value as? NSMutableURLRequest, let field = arg("forHTTPHeaderField")?.asString {
                r.setValue(args.first.map { interp.describe($0) }, forHTTPHeaderField: field)
            }
            return .void
        case ("JSONDecoder", "decode"):
            guard let data = dataValue(arg("from") ?? args.last) else { throw interp.fail("decode(_:from:) needs Data", line) }
            let json: Any
            do {
                json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            } catch {
                throw KEThrown(value: errorValue("The data couldn't be read because it isn't in the correct format."))
            }
            let box = ref.value as? KDecoderBox ?? KDecoderBox()
            return try decode(json, as: decodeTarget(args.first ?? .nilValue, interp), box, interp, line)
        default:
            return nil
        }
    }

    static func networkMember(_ kind: String, _ ref: KRef<AnyObject>, _ name: String) -> KV? {
        switch (kind, name) {
        case ("HTTPURLResponse", "statusCode"): return .int((ref.value as? HTTPURLResponse)?.statusCode ?? 200)
        case ("HTTPURLResponse", "url"): return (ref.value as? URLResponse)?.url.map { .native(.url($0)) } ?? .nilValue
        case ("Data", "count"): return .int((ref.value as? Data)?.count ?? 0)
        case ("Data", "isEmpty"): return .bool((ref.value as? Data)?.isEmpty ?? true)
        case ("Error", "localizedDescription"), ("Error", "description"):
            return .string((ref.value as? NSError)?.localizedDescription ?? "Error")
        case ("URLRequest", "url"): return (ref.value as? NSURLRequest)?.url.map { .native(.url($0)) } ?? .nilValue
        case ("URLComponents", "url"): return (ref.value as? NSURLComponents)?.url.map { .native(.url($0)) } ?? .nilValue
        case ("URLComponents", "string"): return (ref.value as? NSURLComponents)?.string.map { .string($0) } ?? .nilValue
        case ("URLComponents", "queryItems"):
            return (ref.value as? NSURLComponents)?.queryItems.map { .array($0.map { .native(.object("URLQueryItem", KRef($0 as NSURLQueryItem))) }) } ?? .nilValue
        case ("URLQueryItem", "name"): return .string((ref.value as? NSURLQueryItem)?.name ?? "")
        case ("URLQueryItem", "value"): return (ref.value as? NSURLQueryItem)?.value.map { .string($0) } ?? .nilValue
        default: return nil
        }
    }

    static func setNetworkMember(_ kind: String, _ ref: KRef<AnyObject>, _ name: String, _ value: KV) -> Bool {
        switch (kind, name) {
        case ("JSONDecoder", "keyDecodingStrategy"):
            if case .native(.implicit(let s, _)) = value { (ref.value as? KDecoderBox)?.snakeCase = s == "convertFromSnakeCase" }
            return true
        case ("JSONDecoder", "dateDecodingStrategy"):
            if case .native(.implicit(let s, _)) = value { (ref.value as? KDecoderBox)?.iso8601 = s == "iso8601" }
            return true
        case ("URLComponents", "queryItems"):
            if case .array(let items) = value {
                (ref.value as? NSURLComponents)?.queryItems = items.compactMap {
                    if case .native(.object("URLQueryItem", let r)) = $0 { return (r.value as? NSURLQueryItem).map { $0 as URLQueryItem } }
                    return nil
                }
            }
            return true
        case ("URLComponents", "path"):
            (ref.value as? NSURLComponents)?.path = value.asString
            return true
        case ("URLRequest", "httpMethod"):
            (ref.value as? NSMutableURLRequest)?.httpMethod = value.asString ?? "GET"
            return true
        case ("URLRequest", "httpBody"):
            (ref.value as? NSMutableURLRequest)?.httpBody = dataValue(value)
            return true
        default:
            return false
        }
    }

    // MARK: Decoding

    /// What `T.self` names: a type, or `[T].self` (an array literal of one type).
    static func decodeTarget(_ v: KV, _ interp: KInterpreter) -> KETypeRef? {
        switch v {
        case .type(let t): return .named(t.name, [])
        case .array(let items) where items.count == 1: return decodeTarget(items[0], interp).map { .array($0) }
        case .dict(let d) where d.count == 1:
            if let (k, val) = d.first, let kt = decodeTarget(k, interp), let vt = decodeTarget(val, interp) { return .dictionary(kt, vt) }
            return nil
        default: return nil
        }
    }

    @MainActor static func decode(_ json: Any, as type: KETypeRef?, _ box: KDecoderBox, _ interp: KInterpreter, _ line: Int) throws -> KV {
        guard let type else { return plain(json) }
        switch type {
        case .optional(let w):
            return json is NSNull ? .nilValue : try decode(json, as: w, box, interp, line)
        case .array(let e):
            guard let items = json as? [Any] else { throw mismatch("an array", line, interp) }
            return .array(try items.map { try decode($0, as: e, box, interp, line) })
        case .dictionary(_, let v):
            guard let d = json as? [String: Any] else { throw mismatch("a dictionary", line, interp) }
            var out: [KV: KV] = [:]
            for (k, item) in d { out[.string(k)] = try decode(item, as: v, box, interp, line) }
            return .dict(out)
        case .named(let n, let gen):
            switch n {
            case "String":
                if let s = json as? String { return .string(s) }
                throw mismatch("a string", line, interp)
            case "Int", "Int64", "Int32", "UInt":
                if let num = json as? NSNumber { return .int(num.intValue) }
                throw mismatch("a number", line, interp)
            case "Double", "Float", "CGFloat":
                if let num = json as? NSNumber { return .double(num.doubleValue) }
                throw mismatch("a number", line, interp)
            case "Bool":
                if let num = json as? NSNumber { return .bool(num.boolValue) }
                throw mismatch("true or false", line, interp)
            case "URL":
                if let s = json as? String, let u = URL(string: s) { return .native(.url(u)) }
                throw mismatch("a URL", line, interp)
            case "UUID":
                if let s = json as? String, let u = UUID(uuidString: s) { return .native(.uuid(u)) }
                throw mismatch("a UUID", line, interp)
            case "Date":
                if box.iso8601, let s = json as? String, let d = ISO8601DateFormatter().date(from: s) { return .native(.date(d)) }
                if let num = json as? NSNumber { return .native(.date(Date(timeIntervalSinceReferenceDate: num.doubleValue))) }
                throw mismatch("a date", line, interp)
            case "Array" where gen.count == 1:
                return try decode(json, as: .array(gen[0]), box, interp, line)
            case "Optional" where gen.count == 1:
                return try decode(json, as: .optional(gen[0]), box, interp, line)
            default:
                guard let t = interp.type(named: n) else { return plain(json) }
                return try decodeUser(json, t, box, interp, line)
            }
        default:
            return plain(json)
        }
    }

    @MainActor static func decodeUser(_ json: Any, _ t: KType, _ box: KDecoderBox, _ interp: KInterpreter, _ line: Int) throws -> KV {
        if t.isEnum {
            for c in t.cases {
                let raw = try interp.rawValue(KEnumValue(type: t, caseName: c.name, payload: []))
                if raw == plain(json) || (json as? String) == interp.describe(raw) && raw.asString != nil {
                    return .enumV(KEnumValue(type: t, caseName: c.name, payload: []))
                }
            }
            throw KEThrown(value: errorValue("Cannot initialize \(t.name) from invalid value \(json)"))
        }
        guard let object = json as? [String: Any] else { throw mismatch("an object for \(t.name)", line, interp) }
        // CodingKeys: `case authorName = "author_name"`.
        var keys: [String: String] = [:]
        if let ck = t.nested["CodingKeys"] {
            for c in ck.cases {
                let raw = try interp.rawValue(KEnumValue(type: ck, caseName: c.name, payload: []))
                keys[c.name] = raw.asString ?? c.name
            }
        }
        let defaults = try interp.defaultFields(t)
        var fields: [String: KV] = [:]
        for p in t.stored {
            let key: String
            if let k = keys[p.name] { key = k }
            else if !keys.isEmpty { fields[p.name] = defaults[p.name] ?? .nilValue; continue }   // not coded
            else { key = box.snakeCase ? snakeCase(p.name) : p.name }
            if let value = object[key], !(value is NSNull) {
                fields[p.name] = try decode(value, as: p.type, box, interp, line)
            } else if let d = defaults[p.name] {
                fields[p.name] = d
            } else if p.type?.isOptional == true || object[key] is NSNull {
                fields[p.name] = .nilValue
            } else {
                throw KEThrown(value: errorValue("The data couldn't be read because \"\(key)\" is missing (decoding \(t.name))."))
            }
        }
        if t.isClass { return .object(KObject(type: t, fields: fields)) }
        return .structV(KStructValue(type: t, fields: fields))
    }

    static func snakeCase(_ name: String) -> String {
        var out = ""
        for ch in name {
            if ch.isUppercase { out += "_" + ch.lowercased() } else { out.append(ch) }
        }
        return out
    }

    /// JSON as plain values: objects become `[String: Any]` dictionaries.
    static func plain(_ json: Any) -> KV {
        switch json {
        case let s as String: return .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return CFNumberIsFloatType(n) ? .double(n.doubleValue) : .int(n.intValue)
        case let a as [Any]: return .array(a.map(plain))
        case let d as [String: Any]:
            var out: [KV: KV] = [:]
            for (k, v) in d { out[.string(k)] = plain(v) }
            return .dict(out)
        default: return .nilValue
        }
    }

    @MainActor static func mismatch(_ expected: String, _ line: Int, _ interp: KInterpreter) -> KEThrown {
        KEThrown(value: errorValue("The data couldn't be read because it isn't in the correct format (expected \(expected))."))
    }
}
