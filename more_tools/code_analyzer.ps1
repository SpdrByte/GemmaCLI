# ===============================================
# GemmaCLI Tool - code_analyzer.ps1 v0.1.1
# Responsibility: Analyze code via dual agent pipeline
# ===============================================

$ToolMeta = @{
    Name        = "code_analyzer"
    RendersToConsole = $false
    Category    = @("Coding/Development")
    Description = "Analyzes code for errors, security vulnerabilities, style issues, performance problems and suggests fixes. Powered by Gemma for expert-level, language-agnostic analysis."
    Behavior    = "When you are analyzing code, be concise and direct. Focus on actionable feedback that the user can implement. If the user provides a large block of code, focus on the most critical issues first."
    Parameters  = @{
        code = @{
            type        = "string"
            required    = $true
            description = "The code snippet to analyze (supports multiline)"
        }
        language = @{
            type        = "string"
            required    = $true
            description = "Programming language (python, javascript, powershell, java, csharp, cpp, go, rust, etc.)"
        }
        analysis_type = @{
            type        = "array"
            required    = $false
            description = "Analysis categories. Default: ['security','style','errors']. Options: security, style, errors, performance"
        }
        severity_threshold = @{
            type        = "string"
            required    = $false
            description = "Minimum severity to report. Default: 'medium'. Options: low, medium, high"
        }
        report_format = @{
            type        = "string"
            required    = $false
            description = "Output format. Default: 'markdown'. Options: markdown, text, json"
        }
    }
    Example     = "<tool_code>{ ""name"": ""code_analyzer"", ""parameters"": { ""code"": ""function (a,b) { return a + b }"", ""language"": ""javascript"", ""analysis_type"": [""performance""] } }</tool_code>"
    FormatLabel = {
        param($p)
        $types = if ($p.analysis_type) { ($p.analysis_type -join ', ') } else { "security+style+errors" }
        "🔍 Code Analyzer • $($p.language) • $types"
    }
    Execute = {
        param($params)

        # ====================== DEFAULTS & NORMALIZATION ======================
        if (-not $params.analysis_type) { $params.analysis_type = @('security','style','errors') }
        elseif ($params.analysis_type -is [string]) { $params.analysis_type = @($params.analysis_type) }

        if (-not $params.severity_threshold) { $params.severity_threshold = 'medium' }
        if (-not $params.report_format) { $params.report_format = 'markdown' }

        $reportFormat = $params.report_format.ToLower()
        if ($reportFormat -notin @('markdown','text','json')) { $reportFormat = 'markdown' }

        # ====================== BUILD EXPERT PROMPT ======================
        $analysisStr = $params.analysis_type -join ', '
        $formatInstr = if ($reportFormat -eq 'json') {
            "Output ONLY valid JSON. Structure: {`"summary`":`"string`", `"issues`":[{`"issue`":`"string`",`"location`":`"string`",`"severity`":`"high|medium|low`",`"suggestion`":`"string`"}, ...]}"
        } elseif ($reportFormat -eq 'text') {
            "Use clear plain-text sections with bullet points."
        } else {
            "Use clean Markdown with a summary table of issues and code blocks for suggestions."
        }

        $prompt = @"
You are Gemma Code Analyzer — a world-class static analysis expert (OWASP, CWE, language-specific style guides, performance patterns).

Analyze the following $($params.language) code for: $analysisStr

Report ONLY issues at severity '$($params.severity_threshold)' or higher.

$formatInstr

For every issue provide:
• Issue description
• Location (line / range if possible)
• Severity
• Suggested fix (with code example when helpful)

Code to analyze:
``````$($params.language)
$($params.code)
``````
"@

        # ====================== CALL API WITH FALLBACK ======================
        $models = @("gemini-3-flash-preview", "gemini-2.5-flash", "gemma-3-27b-it")
        $result = $null

        foreach ($model in $models) {
            $backend = if ($model -match "gemini") { "gemini" } else { "gemma" }
            $uri = "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=$($script:API_KEY)"
            
            $text = Invoke-SingleTurnApi `
                -uri $uri `
                -prompt $prompt `
                -spinnerLabel "Analyzing with $model..." `
                -backend $backend

            if ($text -and -not ($text -like "ERROR:*")) {
                $result = $text
                break # Success
            } else {
                Write-Host "  $model failed or was cancelled." -ForegroundColor DarkRed
            }
        }

        if ($result) {
            return $result
        } else {
            return "ERROR: Code analysis failed on all available models or was cancelled."
        }
    }
    ToolUseGuidanceMajor = @"
        - When to use 'code_analyzer': Use this tool to perform comprehensive static analysis on code snippets. This is ideal for identifying security vulnerabilities, style inconsistencies, potential errors, or performance bottlenecks in provided code.
        - Important parameters for 'code_analyzer': 
            - `code`: The actual code snippet you want to analyze. Ensure it's complete and valid for the specified language.
            - `language`: Crucial for accurate analysis. Always specify the programming language (e.g., 'python', 'javascript', 'powershell').
            - `analysis_type`: Can be specified as an array (e.g., `["security", "performance"]`) to focus the analysis. Default includes security, style, and errors.
            - `severity_threshold`: Use to filter results to 'low', 'medium', or 'high'. Default is 'medium'.
            - `report_format`: Choose 'markdown' (default), 'text', or 'json' for the output format.
        - Output: The tool provides actionable feedback. For 'markdown' output, expect a summary table of issues and code blocks for suggestions.
        - Advanced Usage: Leverage `analysis_type` and `severity_threshold` to fine-tune the analysis for specific needs.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Check code for problems.
        - Basic use: Provide the `code` and its `language`.
        - Important: Focuses on common errors and style.
"@
}
