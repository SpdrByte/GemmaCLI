# tools/calculator.ps1
# Responsibility: Comprehensive calculator for basic and complex math.
# v1.1.0 - Added degree-mode trig functions (sind, cosd, tand, asind, acosd, atand).

function Invoke-CalculatorTool {
    param([string]$expression)

    if ([string]::IsNullOrWhiteSpace($expression)) {
        return "ERROR: expression cannot be empty."
    }

    $originalExpression = $expression
    $expr = $expression.Trim().ToLower()

    # --- Helper Functions (defined within the job context) ---
    $factFunc = {
        param([int]$n)
        if ($n -lt 0) { throw "Factorial not defined for negative numbers." }
        if ($n -gt 170) { throw "Factorial result too large (overflow)." }
        if ($n -eq 0) { return 1.0 }
        $res = 1.0
        for ($i = 1; $i -le $n; $i++) { $res *= $i }
        return $res
    }

    # --- Normalization ---
    # Replace constants
    $expr = $expr -replace '\bpi\b', "([math]::pi)"
    $expr = $expr -replace '\be\b', "([math]::e)"
    
    # Degree-mode trig functions
    $degMap = @{
        "sind"  = "[math]::sin(({0}) * [math]::pi / 180)"
        "cosd"  = "[math]::cos(({0}) * [math]::pi / 180)"
        "tand"  = "[math]::tan(({0}) * [math]::pi / 180)"
        "asind" = "([math]::asin({0}) * 180 / [math]::pi)"
        "acosd" = "([math]::acos({0}) * 180 / [math]::pi)"
        "atand" = "([math]::atan({0}) * 180 / [math]::pi)"
    }
    $parens = '\((?>[^()]+|(?<open>\()|(?<-open>\)))+(?(open)(?!))\)'
    foreach ($func in $degMap.Keys) {
        while ($expr -match "\b$func\b(?<arg>$parens)") {
            $argWithParens = $matches['arg']
            $argContent = $argWithParens.Substring(1, $argWithParens.Length - 2)
            $replacement = $degMap[$func] -f $argContent
            # We use a literal replacement to avoid regex special characters in the $replacement string
            $target = "$func$argWithParens"
            $idx = $expr.IndexOf($target)
            if ($idx -ge 0) {
                $expr = $expr.Remove($idx, $target.Length).Insert($idx, "($replacement)")
            } else { break }
        }
    }

    # Replace common function names with [Math]:: equivalents
    $mathFunctions = @("abs", "acos", "asin", "atan", "cos", "cosh", "exp", "floor", "round", "sign", "sin", "sinh", "sqrt", "tan", "tanh", "truncate")
    foreach ($func in $mathFunctions) {
        $expr = $expr -replace "(?<!\[math\]::)\b$func\b\(", "[math]::$func("
    }
    
    # Special cases
    $expr = $expr -replace "(?<!\[math\]::)\bceil\b\(", "[math]::ceiling("
    $expr = $expr -replace "(?<!\[math\]::)\bceiling\b\(", "[math]::ceiling("
    
    # Explicit mapping for logarithms to avoid ambiguity
    $expr = $expr -replace "(?<!\[math\]::)\bln\b\(", "[math]::log("
    $expr = $expr -replace "(?<!\[math\]::)\blog10\b\(", "[math]::log10("
    $expr = $expr -replace "(?<!\[math\]::)\blog\b\(", "[math]::log(" # Supports [math]::log(x) and [math]::log(x, base)
    
    # Custom functions
    while ($expr -match '\bfact(?:orial)?\b\((\d+)\)') {
        $n = [int]$matches[1]
        try {
            $val = &$factFunc $n
            $expr = $expr -replace "\bfact(?:orial)?\b\($n\)", "($val)"
        } catch {
            return "ERROR: $($_.Exception.Message)"
        }
    }

    # Handle '^' for power
    $operand = "(?:[\d\.\w\:\/\[\]]+$parens|$parens|[\d\.\w\:\/\[\]]+)"
    
    # Iterate as long as there's a ^ to replace. 
    # The replacement uses a token that doesn't contain ^, ensuring termination.
    $maxIterations = 20
    $powIteration = 0
    while ($expr -match "\^" -and $powIteration -lt $maxIterations) {
        $powIteration++
        if ($expr -match "(?<left>$operand)\s*\^\s*(?<right>$operand)") {
            $expr = $expr -replace "(?<left>$operand)\s*\^\s*(?<right>$operand)", '_POW_(${left},${right})'
        } else {
            break # No more ^ matches the operand pattern
        }
    }

    # Handle pow(a,b) if model used it directly
    $expr = $expr -replace '(?<!\[math\]::)\bpow\b\(', '_POW_('

    # Final replacement for power calls
    $expr = $expr -replace '_POW_\(', '[math]::pow('

    # --- Safety Check ---
    if ($expr -notmatch '^[\d\.\+\-\*\/\%\(\)\,\s\[\]\:\w]+$') {
         return "ERROR: expression contains invalid characters."
    }
    
    $temp = $expr -replace '\[math\]', ''
    $temp = $temp -replace '\:\:\w+', ''
    $temp = $temp -replace '\d+', ''
    $temp = $temp -replace '[\.\+\-\*\/\%\(\)\,\s\[\]\:]', ''
    if ($temp.Trim().Length -gt 0) {
        return "ERROR: expression contains unsupported elements: $temp"
    }

    try {
        $sb = [ScriptBlock]::Create($expr)
        $result = &$sb
        
        # Ensure result is a single value
        if ($result -is [array] -and $result.Count -eq 1) { $result = $result[0] }

        if ($null -eq $result) {
            return "ERROR: Evaluation resulted in null. Check your expression for completeness."
        }

        $formattedResult = if ($result -is [double] -or $result -is [float] -or $result -is [decimal]) {
            if ([double]::IsInfinity($result)) { "Infinity" }
            elseif ([double]::IsNaN($result)) { "NaN" }
            else { "{0:G15}" -f $result }
        } else {
            $result.ToString()
        }

        $lines = @(
            "Expression: $originalExpression",
            "Result:     $formattedResult"
        )
        Draw-Box -Lines $lines -Title "Calculator" -Color Green

        return "CONSOLE::Result: $formattedResult::END_CONSOLE::OK: $originalExpression = $formattedResult"
    } catch {
        return "ERROR: Evaluation failed for '$originalExpression'. $($_.Exception.Message)"
    }
}

$ToolMeta = @{
    Name        = "calculator"
    RendersToConsole = $true
    Category    = @("Coding/Development", "Help/Consultation")
    Behavior    = "Use this tool to evaluate mathematical expressions, perform basic arithmetic, or compute complex equations. Support for trigonometry, logarithms, powers, and constants (pi, e) is included. Use this whenever a user asks for a calculation or when you need precise math results to solve a problem. It does not solve equations symbolically; you must provide the final numerical expression."
    Description = "Evaluates mathematical expressions (arithmetic, trig, logs, etc.)."
    Parameters  = @{
        expression = "string - the math expression to evaluate (e.g., 'sin(pi/4) * sqrt(16) + 2^3')"
    }
    Example     = "<tool_call>{ ""name"": ""calculator"", ""parameters"": { ""expression"": ""sqrt(144) + log10(100)"" } }</tool_call>"
    FormatLabel = { param($p) "🧮 calculator -> $($p.expression)" }
    Execute     = {
        param($params)
        Invoke-CalculatorTool @params
    }
    ToolUseGuidanceMajor = @"
- Supports basic operators: +, -, *, /, %
- Supports power: ^ or pow(x, y)
- Supports constants: pi, e
- Supports functions:
    - sin(x), cos(x), tan(x) (radians)
    - sind(x), cosd(x), tand(x) (DEGREES - use these for degree-based trig)
    - asin(x), acos(x), atan(x) (returns radians)
    - asind(x), acosd(x), atand(x) (returns DEGREES)
    - sqrt(x), abs(x)
    - log10(x), ln(x) or log(x) (natural log)
    - log(x, base)
    - floor(x), ceil(x), round(x)
    - fact(n) or factorial(n)
- Example complex usage: '(-b + sqrt(b^2 - 4*a*c)) / (2*a)' (replace a, b, c with values)
"@
}
