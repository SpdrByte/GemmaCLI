# tests/timer.Tests.ps1

Describe "Timer Tool" {
    BeforeAll {
        $toolFile = "timer.ps1"
        $toolPath = Get-ChildItem -Path "$PSScriptRoot/../tools/$toolFile", "$PSScriptRoot/../more_tools/$toolFile" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if (-not $toolPath) { throw "Tool $toolFile not found" }
        $content = Get-Content -Path $toolPath -Raw -Encoding UTF8
        Invoke-Expression $content
    }

    Context "Input Validation" {
        It "should return an error for zero seconds" {
            $result = Invoke-TimerTool -length_seconds 0
            $result | Should Match "ERROR"
        }

        It "should return an error for negative seconds" {
            $result = Invoke-TimerTool -length_seconds -5
            $result | Should Match "ERROR"
        }
    }

    Context "Execution" {
        It "should wait the specified duration and return sound instruction" {
            $seconds = 2
            $started = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Invoke-TimerTool -length_seconds $seconds
            $elapsed = $started.Elapsed.TotalSeconds

            $elapsed | Should BeGreaterThan $seconds
            $result | Should Match "PLAY_SOUND:Alarm01"
            $result | Should Match "Timer for $seconds seconds has finished"
        }
    }
}
