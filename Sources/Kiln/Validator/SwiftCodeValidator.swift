//
//  SwiftCodeValidator.swift
//  SwiftRunner
//
//  Validates Swift code before parsing, catching common errors early
//  with user-friendly error messages.
//

import Foundation

/// A validation issue found in the code
public struct ValidationIssue: Equatable {
    public enum Severity: String, Equatable {
        case error
        case warning
    }

    public let severity: Severity
    public let message: String
    public let line: Int
    public let column: Int

    public init(severity: Severity, message: String, line: Int = 0, column: Int = 0) {
        self.severity = severity
        self.message = message
        self.line = line
        self.column = column
    }
}

/// Validates Swift source code for common issues
public final class SwiftCodeValidator {

    public init() {}

    /// Validate Swift code and return any issues found
    public func validate(_ code: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        issues.append(contentsOf: checkBalancedDelimiters(code))
        issues.append(contentsOf: checkEmptyCode(code))
        issues.append(contentsOf: checkCommonMistakes(code))

        return issues
    }

    /// Quick check: is this code valid enough to attempt parsing?
    public func canParse(_ code: String) -> Bool {
        let issues = validate(code)
        return !issues.contains { $0.severity == .error }
    }

    // MARK: - Delimiter Checking

    private func checkBalancedDelimiters(_ code: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        struct DelimiterInfo {
            let char: Character
            let line: Int
            let column: Int
        }

        var stack: [DelimiterInfo] = []
        var line = 1
        var column = 1
        var inString = false
        var inLineComment = false
        var inBlockComment = false
        var blockCommentDepth = 0
        var prevChar: Character = "\0"

        for char in code {
            defer {
                prevChar = char
                if char == "\n" {
                    line += 1
                    column = 1
                    inLineComment = false
                } else {
                    column += 1
                }
            }

            // Handle comments
            if !inString {
                if char == "/" && prevChar == "/" && !inBlockComment {
                    inLineComment = true
                    continue
                }
                if char == "*" && prevChar == "/" && !inLineComment {
                    if !inBlockComment {
                        inBlockComment = true
                        blockCommentDepth = 1
                    } else {
                        blockCommentDepth += 1
                    }
                    continue
                }
                if char == "/" && prevChar == "*" && inBlockComment {
                    blockCommentDepth -= 1
                    if blockCommentDepth == 0 {
                        inBlockComment = false
                    }
                    continue
                }
            }

            if inLineComment || inBlockComment { continue }

            // Handle strings
            if char == "\"" && prevChar != "\\" {
                inString.toggle()
                continue
            }

            if inString { continue }

            // Track delimiters
            switch char {
            case "(", "{", "[":
                stack.append(DelimiterInfo(char: char, line: line, column: column))
            case ")":
                if let last = stack.last, last.char == "(" {
                    stack.removeLast()
                } else {
                    issues.append(ValidationIssue(
                        severity: .error,
                        message: "Unexpected ')' — no matching '('",
                        line: line, column: column
                    ))
                }
            case "}":
                if let last = stack.last, last.char == "{" {
                    stack.removeLast()
                } else {
                    issues.append(ValidationIssue(
                        severity: .error,
                        message: "Unexpected '}' — no matching '{'",
                        line: line, column: column
                    ))
                }
            case "]":
                if let last = stack.last, last.char == "[" {
                    stack.removeLast()
                } else {
                    issues.append(ValidationIssue(
                        severity: .error,
                        message: "Unexpected ']' — no matching '['",
                        line: line, column: column
                    ))
                }
            default:
                break
            }
        }

        // Check for unclosed delimiters
        for unclosed in stack.reversed() {
            let closing: String
            switch unclosed.char {
            case "(": closing = ")"
            case "{": closing = "}"
            case "[": closing = "]"
            default: closing = "?"
            }
            issues.append(ValidationIssue(
                severity: .error,
                message: "Unclosed '\(unclosed.char)' — expected '\(closing)'",
                line: unclosed.line, column: unclosed.column
            ))
        }

        // Check for unterminated string
        if inString {
            issues.append(ValidationIssue(
                severity: .error,
                message: "Unterminated string literal",
                line: line, column: column
            ))
        }

        // Check for unclosed block comment
        if inBlockComment {
            issues.append(ValidationIssue(
                severity: .error,
                message: "Unterminated block comment /* ... */",
                line: line, column: column
            ))
        }

        return issues
    }

    // MARK: - Empty Code Check

    private func checkEmptyCode(_ code: String) -> [ValidationIssue] {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return [ValidationIssue(severity: .warning, message: "Code is empty")]
        }
        return []
    }

    // MARK: - Common Mistakes

    private func checkCommonMistakes(_ code: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let lines = code.components(separatedBy: "\n")

        for (lineIdx, lineContent) in lines.enumerated() {
            let trimmed = lineContent.trimmingCharacters(in: .whitespaces)
            let lineNumber = lineIdx + 1

            // Check for semicolons at end of lines (Swift convention)
            if trimmed.hasSuffix(";") && !trimmed.contains("//") {
                issues.append(ValidationIssue(
                    severity: .warning,
                    message: "Semicolons are not needed in Swift",
                    line: lineNumber
                ))
            }

            // Check for common typos
            if trimmed.hasPrefix("fucn ") || trimmed.hasPrefix("funct ") {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Did you mean 'func'?",
                    line: lineNumber
                ))
            }

            if trimmed.hasPrefix("sturct ") || trimmed.hasPrefix("strcut ") {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Did you mean 'struct'?",
                    line: lineNumber
                ))
            }

            // Check for = vs == in if conditions
            if trimmed.hasPrefix("if ") && !trimmed.contains("==") && !trimmed.contains("!=") &&
               !trimmed.contains("let ") && !trimmed.contains("var ") {
                // Check for single = (assignment in condition)
                let conditionPart = String(trimmed.dropFirst(3))
                let equalsCount = conditionPart.components(separatedBy: "=").count - 1
                let doubleEqualsCount = conditionPart.components(separatedBy: "==").count - 1
                if equalsCount > doubleEqualsCount && equalsCount > 0 {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        message: "Did you mean '==' instead of '=' in the if condition?",
                        line: lineNumber
                    ))
                }
            }
        }

        return issues
    }
}
