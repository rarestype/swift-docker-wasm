@freestanding(expression) macro stringify<T>(_ value: T) -> String =
    #externalMacro(module: "ProbeMacros", type: "StringifyMacro")

public let probe: String = #stringify(13 + 89)
