import Foundation

public enum TOMLValue: Equatable {
    case number(Double)
    case bool(Bool)
    case string(String)

    var rendered: String {
        switch self {
        case .number(let n):
            var s = String(format: "%.4f", n)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            return s
        case .bool(let b): return b ? "true" : "false"
        case .string(let s):
            let escaped = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
    }
}

/// A line-based reader and editor for the small TOML subset Desk Undo uses:
/// `[table]` headers, `key = number | true | false | "string"`, and `#` comments.
///
/// Edits change only the value they touch, so comments and layout a person added by hand survive.
public struct TOMLDocument: Equatable {
    public private(set) var lines: [String]

    public init(text: String = "") {
        lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
    }

    public var text: String { lines.joined(separator: "\n") }

    public static func tableName(webcam: String) -> String {
        "webcams.\(TOMLValue.string(webcam).rendered)"
    }

    public static func tableName(setup: String) -> String {
        "setups.\(TOMLValue.string(setup).rendered)"
    }

    /// Names of the tables under `prefix.` in file order, e.g. the setup names for `setups`.
    public func tableNames(prefix: String) -> [String] {
        lines.compactMap { Self.header($0) }.compactMap { header in
            guard header.hasPrefix(prefix + ".") else { return nil }
            let rest = header.dropFirst(prefix.count + 1).trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix("\""), let v = Self.parseValue(rest).value, case .string(let name) = v else { return rest }
            return name
        }
    }

    public func hasTable(_ table: String) -> Bool { lines.contains { Self.header($0) == table } }

    public mutating func removeTable(_ table: String) {
        guard let i = lines.firstIndex(where: { Self.header($0) == table }), let range = tableRange(table) else { return }
        lines.removeSubrange(i..<range.upperBound)
    }

    public mutating func renameTable(_ table: String, to new: String) {
        guard let i = lines.firstIndex(where: { Self.header($0) == table }) else { return }
        lines[i] = "[\(new)]"
    }

    /// Copies a table, comments included, under a new name placed right after it.
    public mutating func duplicateTable(_ table: String, as new: String) {
        guard hasTable(table), let range = tableRange(table) else { return }
        var body = Array(lines[range])
        while body.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { body.removeLast() }
        let insertAt = range.lowerBound + body.count
        lines.insert(contentsOf: ["", "[\(new)]"] + body, at: insertAt)
    }

    public func value(_ key: String, in table: String) -> TOMLValue? {
        guard let range = tableRange(table) else { return nil }
        for i in range {
            if let (k, rest) = Self.keyAndRest(lines[i]), k == key {
                return Self.parseValue(rest).value
            }
        }
        return nil
    }

    public mutating func set(_ key: String, _ value: TOMLValue, in table: String) {
        let newPair = "\(key) = \(value.rendered)"
        guard let range = tableRange(table) else {
            while lines.last == "" { lines.removeLast() }
            if !lines.isEmpty { lines.append("") }
            if !table.isEmpty { lines.append("[\(table)]") }
            lines.append(newPair)
            lines.append("")
            return
        }
        for i in range {
            if let (k, rest) = Self.keyAndRest(lines[i]), k == key {
                let comment = Self.parseValue(rest).comment
                lines[i] = comment.map { "\(newPair) \($0)" } ?? newPair
                return
            }
        }
        // A commented-out template line for this key becomes the real line, so the file stays tidy.
        for i in range {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#"), let (k, _) = Self.keyAndRest(String(t.dropFirst())), k == key {
                lines[i] = newPair
                return
            }
        }
        // Otherwise insert after the table's last key, so a comment that introduces the next section stays with it.
        var at = range.lowerBound
        for i in range where Self.keyAndRest(lines[i]) != nil { at = i + 1 }
        lines.insert(newPair, at: at)
    }

    public mutating func remove(_ key: String, in table: String) {
        guard let range = tableRange(table) else { return }
        for i in range {
            if let (k, _) = Self.keyAndRest(lines[i]), k == key {
                lines.remove(at: i)
                return
            }
        }
    }

    // MARK: Parsing

    /// Line indexes belonging to `table`, headers excluded. The top-level table is `""`.
    private func tableRange(_ table: String) -> Range<Int>? {
        var start: Int? = table.isEmpty ? 0 : nil
        for (i, line) in lines.enumerated() {
            if let header = Self.header(line) {
                if let s = start { return s..<i }
                if header == table { start = i + 1 }
            }
        }
        return start.map { $0..<lines.count }
    }

    private static func header(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("["), !t.hasPrefix("[[") else { return nil }
        var inString = false
        var escaped = false
        for (offset, ch) in t.enumerated() where offset > 0 {
            if inString {
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
            } else if ch == "\"" {
                inString = true
            } else if ch == "]" {
                let inner = t.dropFirst().prefix(offset - 1)
                return inner.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func keyAndRest(_ line: String) -> (String, String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.hasPrefix("#"), !t.hasPrefix("["), let eq = t.firstIndex(of: "=") else { return nil }
        let key = t[..<eq].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        return (key, String(t[t.index(after: eq)...]))
    }

    /// Reads one value and any trailing comment from the text after `=`.
    private static func parseValue(_ rest: String) -> (value: TOMLValue?, comment: String?) {
        let t = rest.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("\"") {
            var out = ""
            var escaped = false
            var idx = t.index(after: t.startIndex)
            while idx < t.endIndex {
                let ch = t[idx]
                if escaped { out.append(ch); escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" {
                    let tail = t[t.index(after: idx)...].trimmingCharacters(in: .whitespaces)
                    return (.string(out), tail.hasPrefix("#") ? tail : nil)
                } else { out.append(ch) }
                idx = t.index(after: idx)
            }
            return (nil, nil)
        }
        var body = t
        var comment: String?
        if let hash = t.firstIndex(of: "#") {
            comment = String(t[hash...])
            body = t[..<hash].trimmingCharacters(in: .whitespaces)
        }
        if body == "true" { return (.bool(true), comment) }
        if body == "false" { return (.bool(false), comment) }
        if let n = Double(body), n.isFinite { return (.number(n), comment) }
        return (nil, comment)
    }
}
