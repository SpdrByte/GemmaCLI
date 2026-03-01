# tests/readfile.Tests.ps1

Describe "Invoke-ReadFileTool Functionality" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../tools/readfile.ps1")
        $script:testFile = New-TemporaryFile
        Set-Content -Path $script:testFile.FullName -Value "hello world"
    }

    AfterAll {
        Remove-Item $script:testFile -Force -ErrorAction SilentlyContinue
    }

    Context "when given a valid file" {
        It "returns the file's content" {
            $result = Invoke-ReadFileTool -file_path $script:testFile.FullName
            ($result).Trim() | Should Be "hello world"
        }

        It "handles paths with extra quotes from JSON artifacts" {
            $quotedPath = "`"$($script:testFile.FullName)`""
            $result = Invoke-ReadFileTool -file_path $quotedPath
            ($result).Trim() | Should Be "hello world"
        }
    }

    Context "when given an invalid path" {
        It "returns an ERROR string for a nonexistent file" {
            $result = Invoke-ReadFileTool -file_path "C:\fake\path\that\does\not\exist.txt"
            $result | Should Match "^ERROR:"
        }

        It "returns an ERROR string for a directory path" {
            $result = Invoke-ReadFileTool -file_path $env:TEMP
            $result | Should Match "^ERROR:"
        }
    }
}
