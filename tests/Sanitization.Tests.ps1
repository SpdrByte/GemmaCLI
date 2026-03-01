# tests/Sanitization.Tests.ps1
Describe "JSON Sanitization Logic" {
    BeforeAll {
        function Sanitize-Json {
            param([string]$jsonStr)
            # The bulletproof regex
            $pattern = '(?s)("(?:[^"\\]|\\.)*")'
            return [System.Text.RegularExpressions.Regex]::Replace($jsonStr, $pattern, {
                param($m) $m.Value -replace "\r\n|\r|\n", '\n'
            })
        }
    }

    It "Should escape a simple literal newline inside quotes" {
        $input = '{"text": "Line 1' + "`n" + 'Line 2"}'
        $sanitized = Sanitize-Json -jsonStr $input
        $sanitized | Should Be '{"text": "Line 1\nLine 2"}'
        $obj = $sanitized | ConvertFrom-Json
        $obj.text | Should Be "Line 1`nLine 2"
    }

    It "Should handle multiple literal newlines" {
        $input = '{"text": "A' + "`n`n" + 'B"}'
        $sanitized = Sanitize-Json -jsonStr $input
        $sanitized | Should Be '{"text": "A\n\nB"}'
        $obj = $sanitized | ConvertFrom-Json
        $obj.text | Should Be "A`n`nB"
    }

    It "Should handle escaped quotes with newlines" {
        $input = '{"text": "Quote: \"Hello\"' + "`n" + 'Next line"}'
        $sanitized = Sanitize-Json -jsonStr $input
        $sanitized | Should Be '{"text": "Quote: \"Hello\"\nNext line"}'
        $obj = $sanitized | ConvertFrom-Json
        $obj.text | Should Be "Quote: `"Hello`"`nNext line"
    }

    It "Should handle escaped backslashes at the end of a string (The Trap)" {
        $input = '{"path": "C:\\temp\\' + "`n" + 'Next line"}'
        $sanitized = Sanitize-Json -jsonStr $input
        $sanitized | Should Be '{"path": "C:\\temp\\\nNext line"}'
        $obj = $sanitized | ConvertFrom-Json
        $obj.path | Should Be "C:\temp\`nNext line"
    }

    It "Should NOT touch newlines OUTSIDE of quotes" {
        $input = '{' + "`n" + '    "name": "test"' + "`n" + '}'
        $sanitized = Sanitize-Json -jsonStr $input
        # The newlines after { and before "name" should NOT be replaced by \n
        $sanitized | Should Match '(?s)\{\r?\n\s+"name"'
        $obj = $sanitized | ConvertFrom-Json
        $obj.name | Should Be "test"
    }

    It "Should handle a full writefile tool call with code" {
        $input = '{
  "name": "writefile",
  "parameters": {
    "file_path": "test.txt",
    "content": "line 1' + "`n" + 'line 2' + "`n" + 'line 3"
  }
}'
        $sanitized = Sanitize-Json -jsonStr $input
        $obj = $sanitized | ConvertFrom-Json
        $obj.parameters.content | Should Be "line 1`nline 2`nline 3"
    }
}