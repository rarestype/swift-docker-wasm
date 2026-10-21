import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

/// Expands to the source text of its argument, as a string literal.
public struct StringifyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) -> ExprSyntax {
        let argument: String = node.arguments.first?.expression.trimmedDescription ?? ""
        return "\(literal: argument)"
    }
}

@main struct ProbeMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [StringifyMacro.self]
}
