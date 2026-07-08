//
//  ExpressionEvaluator.swift
//  SwiftRunner
//
//  Created by Claw on 2/21/26.
//

import Foundation

/// A value that can be stored in the environment
public enum Value: Equatable, CustomStringConvertible {
    case number(Double)
    case string(String)
    case boolean(Bool)
    case array([Value])
    case object([String: Value])
    case `nil`

    public var description: String {
        switch self {
        case .number(let n):
            if n == floor(n) { return String(Int(n)) }
            return String(n)
        case .string(let s): return s
        case .boolean(let b): return b ? "true" : "false"
        case .array(let arr): return "[\(arr.map(\.description).joined(separator: ", "))]"
        case .object(let dict):
            let fields = dict.map { "\($0.key): \($0.value.description)" }.joined(separator: ", ")
            return "{\(fields)}"
        case .nil: return "nil"
        }
    }

    public var isTruthy: Bool {
        switch self {
        case .boolean(let b): return b
        case .nil: return false
        case .number(let n): return n != 0
        case .string(let s): return !s.isEmpty
        case .array(let a): return !a.isEmpty
        case .object(let d): return !d.isEmpty
        }
    }
}

/// Environment for storing variables
public final class Environment {
    private var values: [String: Value] = [:]
    private let parent: Environment?
    
    public init(parent: Environment? = nil) {
        self.parent = parent
    }
    
    public func define(_ name: String, value: Value) {
        values[name] = value
    }
    
    public func get(_ name: String) -> Value? {
        if let value = values[name] {
            return value
        }
        return parent?.get(name)
    }
    
    public func set(_ name: String, value: Value) -> Bool {
        if values[name] != nil {
            values[name] = value
            return true
        }
        return parent?.set(name, value: value) ?? false
    }
}

/// Evaluates expressions and returns values
public final class ExpressionEvaluator {
    
    private var environment: Environment
    private var output: [String] = []
    
    public init(environment: Environment = Environment()) {
        self.environment = environment
    }
    
    /// Evaluate a ViewNode and return the result value
    public func evaluate(_ node: ViewNode) throws -> Value {
        switch node {
        case .literal(let value):
            return try evaluateLiteral(value)
            
        case .variable(let name):
            guard let value = environment.get(name) else {
                return .nil
            }
            return value
            
        case .binary(let left, let op, let right):
            return try evaluateBinary(left, op, right)
            
        case .assignment(let name, _, let value):
            let evaluated = try evaluate(value)
            environment.define(name, value: evaluated)
            return evaluated
            
        case .functionCall(let name, let arguments):
            return try evaluateFunction(name, arguments: arguments)
            
        case .block(let statements):
            var result: Value = .nil
            for stmt in statements {
                result = try evaluate(stmt)
            }
            return result
            
        default:
            return .nil
        }
    }
    
    /// Get console output from print statements
    public func getOutput() -> String {
        return output.joined(separator: "\n")
    }
    
    /// Clear console output
    public func clearOutput() {
        output = []
    }
    
    // MARK: - Private
    
    private func evaluateLiteral(_ literal: LiteralValue) throws -> Value {
        switch literal {
        case .string(let s): return .string(s)
        case .number(let n): return .number(n)
        case .boolean(let b): return .boolean(b)
        case .nil: return .nil
        case .color(let c): return .string(c.rawValue)
        }
    }
    
    private func evaluateBinary(_ left: ViewNode, _ op: BinaryOperator, _ right: ViewNode) throws -> Value {
        let leftVal = try evaluate(left)
        let rightVal = try evaluate(right)
        
        switch op {
        // Arithmetic
        case .plus:
            if case .number(let l) = leftVal, case .number(let r) = rightVal {
                return .number(l + r)
            }
            // Array concatenation: [a] + [b] → [a, b] (used for e.g. growing a
            // snake: `[head] + body`, or appending: `out + [item]`).
            if case .array(let l) = leftVal, case .array(let r) = rightVal {
                return .array(l + r)
            }
            // String concatenation
            return .string(leftVal.description + rightVal.description)
            
        case .minus:
            if case .number(let l) = leftVal, case .number(let r) = rightVal {
                return .number(l - r)
            }
            return .nil
            
        case .multiply:
            if case .number(let l) = leftVal, case .number(let r) = rightVal {
                return .number(l * r)
            }
            return .nil
            
        case .divide:
            if case .number(let l) = leftVal, case .number(let r) = rightVal {
                guard r != 0 else { return .nil }
                return .number(l / r)
            }
            return .nil
            
        case .modulo:
            if case .number(let l) = leftVal, case .number(let r) = rightVal {
                guard r != 0 else { return .nil }
                return .number(l.truncatingRemainder(dividingBy: r))
            }
            return .nil
            
        // Comparison
        case .equal:
            return .boolean(leftVal == rightVal)
            
        case .notEqual:
            return .boolean(leftVal != rightVal)
            
        case .less:
            if case .number(let l) = leftVal, case .number(let r) = rightVal {
                return .boolean(l < r)
            }
            return .nil
            
        case .greater:
            if case .number(let l) = leftVal, case .number(let r) = rightVal {
                return .boolean(l > r)
            }
            return .nil
            
        case .lessEqual:
            if case .number(let l) = leftVal, case .number(let r) = rightVal {
                return .boolean(l <= r)
            }
            return .nil
            
        case .greaterEqual:
            if case .number(let l) = leftVal, case .number(let r) = rightVal {
                return .boolean(l >= r)
            }
            return .nil
            
        // Logical
        case .and:
            return .boolean(leftVal.isTruthy && rightVal.isTruthy)
            
        case .or:
            return .boolean(leftVal.isTruthy || rightVal.isTruthy)
        }
    }
    
    private func evaluateFunction(_ name: String, arguments: [Argument]) throws -> Value {
        switch name {
        case "print":
            let values = try arguments.map { try evaluate($0.value) }
            let line = values.map(\.description).joined(separator: " ")
            output.append(line)
            return .nil
            
        case "abs":
            if let first = arguments.first,
               case .number(let n) = try evaluate(first.value) {
                return .number(abs(n))
            }
            return .nil
            
        case "sqrt":
            if let first = arguments.first,
               case .number(let n) = try evaluate(first.value) {
                return .number(sqrt(n))
            }
            return .nil
            
        case "pow":
            if arguments.count >= 2,
               case .number(let base) = try evaluate(arguments[0].value),
               case .number(let exp) = try evaluate(arguments[1].value) {
                return .number(pow(base, exp))
            }
            return .nil
            
        case "min":
            let nums = try arguments.compactMap { arg -> Double? in
                if case .number(let n) = try evaluate(arg.value) {
                    return n
                }
                return nil
            }
            if let result = nums.min() {
                return .number(result)
            }
            return .nil
            
        case "max":
            let nums = try arguments.compactMap { arg -> Double? in
                if case .number(let n) = try evaluate(arg.value) {
                    return n
                }
                return nil
            }
            if let result = nums.max() {
                return .number(result)
            }
            return .nil
            
        case "round":
            if let first = arguments.first,
               case .number(let n) = try evaluate(first.value) {
                return .number(round(n))
            }
            return .nil
            
        case "floor":
            if let first = arguments.first,
               case .number(let n) = try evaluate(first.value) {
                return .number(floor(n))
            }
            return .nil
            
        case "ceil":
            if let first = arguments.first,
               case .number(let n) = try evaluate(first.value) {
                return .number(ceil(n))
            }
            return .nil
            
        case "String":
            if let first = arguments.first {
                let value = try evaluate(first.value)
                return .string(value.description)
            }
            return .string("")
            
        case "Int":
            if let first = arguments.first,
               case .number(let n) = try evaluate(first.value) {
                return .number(floor(n))
            }
            return .nil
            
        case "Double":
            if let first = arguments.first {
                let value = try evaluate(first.value)
                switch value {
                case .number(let n): return .number(n)
                case .string(let s): 
                    if let n = Double(s) { return .number(n) }
                default: break
                }
            }
            return .nil
            
        default:
            return .nil
        }
    }
}
