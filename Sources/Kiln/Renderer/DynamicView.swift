//
//  DynamicView.swift
//  SwiftRunner
//

import SwiftUI

/// Wrapper view that observes SwiftRunnerState for reactive re-rendering.
/// When state.variables changes, SwiftUI re-evaluates body, rebuilding the view tree
/// from the AST with current state values.
@MainActor
struct DynamicView: View {
    let ast: ViewNode
    @StateObject var state: SwiftRunnerState

    init(ast: ViewNode, state: SwiftRunnerState) {
        self.ast = ast
        _state = StateObject(wrappedValue: state)
    }

    var body: some View {
        DynamicViewBuilder.build(ast, state: state)
    }
}
