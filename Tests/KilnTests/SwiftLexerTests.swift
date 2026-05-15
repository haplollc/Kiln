//
//  SwiftLexerTests.swift
//  SwiftRunnerTests
//
//  Created by Claw on 2/21/26.
//

import XCTest
@testable import Kiln

final class SwiftLexerTests: XCTestCase {
    
    // MARK: - Basic Tokens
    
    func testLexerTokenizesIdentifier() throws {
        let lexer = SwiftLexer(source: "hello")
        let tokens = try lexer.tokenize()
        
        XCTAssertEqual(tokens.count, 2) // identifier + EOF
        XCTAssertEqual(tokens[0].type, .identifier("hello"))
    }
    
    func testLexerTokenizesNumber() throws {
        let lexer = SwiftLexer(source: "42")
        let tokens = try lexer.tokenize()
        
        XCTAssertEqual(tokens[0].type, .number(42))
    }
    
    func testLexerTokenizesDecimalNumber() throws {
        let lexer = SwiftLexer(source: "3.14")
        let tokens = try lexer.tokenize()
        
        XCTAssertEqual(tokens[0].type, .number(3.14))
    }
    
    func testLexerTokenizesString() throws {
        let lexer = SwiftLexer(source: "\"Hello World\"")
        let tokens = try lexer.tokenize()
        
        XCTAssertEqual(tokens[0].type, .string("Hello World"))
    }
    
    func testLexerTokenizesEscapedString() throws {
        let lexer = SwiftLexer(source: "\"Hello\\nWorld\"")
        let tokens = try lexer.tokenize()
        
        XCTAssertEqual(tokens[0].type, .string("Hello\nWorld"))
    }
    
    // MARK: - Keywords
    
    func testLexerTokenizesKeywords() throws {
        let lexer = SwiftLexer(source: "let var func if else for in while return")
        let tokens = try lexer.tokenize()
        
        XCTAssertEqual(tokens[0].type, .keyword(.let))
        XCTAssertEqual(tokens[1].type, .keyword(.var))
        XCTAssertEqual(tokens[2].type, .keyword(.func))
        XCTAssertEqual(tokens[3].type, .keyword(.if))
        XCTAssertEqual(tokens[4].type, .keyword(.else))
        XCTAssertEqual(tokens[5].type, .keyword(.for))
        XCTAssertEqual(tokens[6].type, .keyword(.in))
        XCTAssertEqual(tokens[7].type, .keyword(.while))
        XCTAssertEqual(tokens[8].type, .keyword(.return))
    }
    
    func testLexerTokenizesBooleans() throws {
        let lexer = SwiftLexer(source: "true false")
        let tokens = try lexer.tokenize()
        
        XCTAssertEqual(tokens[0].type, .boolean(true))
        XCTAssertEqual(tokens[1].type, .boolean(false))
    }
    
    // MARK: - Operators
    
    func testLexerTokenizesOperators() throws {
        let lexer = SwiftLexer(source: "+ - * / %")
        let tokens = try lexer.tokenize()
        
        XCTAssertEqual(tokens[0].type, .plus)
        XCTAssertEqual(tokens[1].type, .minus)
        XCTAssertEqual(tokens[2].type, .star)
        XCTAssertEqual(tokens[3].type, .slash)
        XCTAssertEqual(tokens[4].type, .percent)
    }
    
    func testLexerTokenizesComparisonOperators() throws {
        let lexer = SwiftLexer(source: "== != < > <= >=")
        let tokens = try lexer.tokenize()
        
        XCTAssertEqual(tokens[0].type, .equalEqual)
        XCTAssertEqual(tokens[1].type, .notEqual)
        XCTAssertEqual(tokens[2].type, .lessThan)
        XCTAssertEqual(tokens[3].type, .greaterThan)
        XCTAssertEqual(tokens[4].type, .lessEqual)
        XCTAssertEqual(tokens[5].type, .greaterEqual)
    }
    
    func testLexerTokenizesLogicalOperators() throws {
        let lexer = SwiftLexer(source: "&& || !")
        let tokens = try lexer.tokenize()
        
        XCTAssertEqual(tokens[0].type, .and)
        XCTAssertEqual(tokens[1].type, .or)
        XCTAssertEqual(tokens[2].type, .not)
    }
    
    // MARK: - Punctuation
    
    func testLexerTokenizesPunctuation() throws {
        let lexer = SwiftLexer(source: "( ) { } [ ] , : . ;")
        let tokens = try lexer.tokenize()
        
        XCTAssertEqual(tokens[0].type, .leftParen)
        XCTAssertEqual(tokens[1].type, .rightParen)
        XCTAssertEqual(tokens[2].type, .leftBrace)
        XCTAssertEqual(tokens[3].type, .rightBrace)
        XCTAssertEqual(tokens[4].type, .leftBracket)
        XCTAssertEqual(tokens[5].type, .rightBracket)
        XCTAssertEqual(tokens[6].type, .comma)
        XCTAssertEqual(tokens[7].type, .colon)
        XCTAssertEqual(tokens[8].type, .dot)
        XCTAssertEqual(tokens[9].type, .semicolon)
    }
    
    // MARK: - Comments
    
    func testLexerSkipsLineComments() throws {
        let lexer = SwiftLexer(source: "hello // this is a comment\nworld")
        let tokens = try lexer.tokenize()
        
        XCTAssertEqual(tokens[0].type, .identifier("hello"))
        XCTAssertEqual(tokens[1].type, .newline)
        XCTAssertEqual(tokens[2].type, .identifier("world"))
    }
    
    func testLexerSkipsBlockComments() throws {
        let lexer = SwiftLexer(source: "hello /* block comment */ world")
        let tokens = try lexer.tokenize()
        
        XCTAssertEqual(tokens[0].type, .identifier("hello"))
        XCTAssertEqual(tokens[1].type, .identifier("world"))
    }
    
    // MARK: - Complex Expressions
    
    func testLexerTokenizesViewCode() throws {
        let code = """
        VStack {
            Text("Hello")
        }
        """
        let lexer = SwiftLexer(source: code)
        let tokens = try lexer.tokenize()
        
        // VStack { newline Text ( "Hello" ) newline } EOF
        XCTAssertEqual(tokens[0].type, .identifier("VStack"))
        XCTAssertEqual(tokens[1].type, .leftBrace)
        XCTAssertEqual(tokens[2].type, .newline)
        XCTAssertEqual(tokens[3].type, .identifier("Text"))
        XCTAssertEqual(tokens[4].type, .leftParen)
        XCTAssertEqual(tokens[5].type, .string("Hello"))
    }
    
    func testLexerTokenizesModifierChain() throws {
        let code = "Text(\"Hi\").font(.title).foregroundColor(.blue)"
        let lexer = SwiftLexer(source: code)
        let tokens = try lexer.tokenize()
        
        XCTAssertEqual(tokens[0].type, .identifier("Text"))
        XCTAssertEqual(tokens[1].type, .leftParen)
        XCTAssertEqual(tokens[2].type, .string("Hi"))
        XCTAssertEqual(tokens[3].type, .rightParen)
        XCTAssertEqual(tokens[4].type, .dot)
        XCTAssertEqual(tokens[5].type, .identifier("font"))
    }
    
    // MARK: - Error Cases
    
    func testLexerThrowsOnUnterminatedString() {
        let lexer = SwiftLexer(source: "\"hello")
        
        XCTAssertThrowsError(try lexer.tokenize()) { error in
            XCTAssertTrue(error is LexerError)
        }
    }
}
