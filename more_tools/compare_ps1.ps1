# ===============================================
# GemmaCLI Tool - compare_ps1.ps1 v0.1.0
# Responsibility: Compares two PowerShell files and shows line-by-line differences.
# ===============================================

function Invoke-ComparePs1Tool {
    param(
        [string]$file1,
        [string]$file2
    )

    $f1 = $file1.Trim().Trim("'").Trim('"').Replace('\\', '\')
    $f2 = $file2.Trim().Trim("'").Trim('"').Replace('\\', '\')

    if (-not (Test-Path $f1)) { return "ERROR: File 1 not found: $f1" }
    if (-not (Test-Path $f2)) { return "ERROR: File 2 not found: $f2" }

    $c1 = Get-Content $f1 -Raw
    $c2 = Get-Content $f2 -Raw

    if ($c1 -eq $c2) {
        return "OK: The files are identical."
    }

    # Files differ, use fc.exe for a line-numbered diff
    try {
        $diff = fc.exe /N $f1 $f2 2>&1
        $result = "FILES DIFFER:`n"
        $result += "File 1: $f1`n"
        $result += "File 2: $f2`n"
        $result += "------------------------------------------------------------`n"
        $result += ($diff -join "`n")
        return $result
    } catch {
        return "ERROR: Failed to run diff command. $($_.Exception.Message)"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "compare_ps1"
    RendersToConsole = $false
    Category    = @("Coding/Development")
    Behavior    = "Use this tool to compare two PowerShell (.ps1) files. It is useful for finding differences between versions of a script or comparing tools across workspaces."
    Description = "Compares two specific PowerShell files and identifies differences using line numbers."
    Parameters  = @{
        file1 = "string - Path to the first .ps1 file."
        file2 = "string - Path to the second .ps1 file."
    }
    Example     = "<tool_call>{ ""name"": ""compare_ps1"", ""parameters"": { ""file1"": ""./tools/readfile.ps1"", ""file2"": ""./tools_backup/readfile.ps1"" } }</tool_call>"
    FormatLabel = { param($params) "🔍 Compare PS1 -> $($params.file1) vs $($params.file2)" }
    Execute     = {
        param($params)
        Invoke-ComparePs1Tool -file1 $params.file1 -file2 $params.file2
    }
    ToolUseGuidanceMajor = @"
        - When to use 'compare_ps1': Use this tool when you need to see exactly how two PowerShell scripts differ.
        - The tool returns a line-numbered comparison (diff).
        - If files are identical, it reports 'OK: The files are identical.'
"@
    ToolUseGuidanceMinor = @"
        - Purpose: See the difference between two .ps1 files.
        - Parameters: file1 and file2 (paths).
"@
}
