# tests/video_surveillance.Tests.ps1
$toolFile = "video_surveillance.ps1"
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolPath = Get-ChildItem -Path "$projectRoot/tools/$toolFile", "$projectRoot/more_tools/$toolFile" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

Describe "Video Surveillance Tool" {
    BeforeAll {
        if (-not $toolPath) { throw "Tool $toolFile not found" }
        
        # Mocking Global Dependencies
        function Get-StoredKey { param($keyName) return "mock_api_key" }
        $script:API_KEY = "mock_api_key"
        
        # Load the tool
        $content = Get-Content -Path $toolPath -Raw -Encoding UTF8
        Invoke-Expression $content
    }

    Context "Metadata" {
        It "should define the tool metadata correctly" {
            $ToolMeta.Name | Should Be "video_surveillance"
            $ToolMeta.Category | Should Contain "Security"
            $ToolMeta.Parameters.action | Should Match "start"
        }
    }

    Context "Functionality" {
        BeforeEach {
            # Mocking PowerShell Job and Process Cmdlets
            Mock Get-Job { return $null } -ModuleName Pester
            Mock Start-Job { return @{ Name = "GemmaGuardian"; State = "Running" } } -ModuleName Pester
            Mock Stop-Job { } -ModuleName Pester
            Mock Remove-Job { } -ModuleName Pester
            Mock Stop-Process { } -ModuleName Pester
            Mock Get-Command { return @{ Name = "MockCmd" } } -ModuleName Pester
            
            # Mocking ffmpeg device listing (function in local scope)
            function ffmpeg { 
                return '[in#0 @ 0000] "Integrated Camera" (video)' 
            }
        }

        It "should report IDLE status when no job is running" {
            Mock Get-Job { return $null }
            $result = Invoke-VideoSurveillanceTool -action "status"
            $result | Should Match "IDLE"
        }

        It "should report GUARDING status when the job is running" {
            Mock Get-Job { return @{ Name = "GemmaGuardian"; State = "Running" } }
            $result = Invoke-VideoSurveillanceTool -action "status"
            $result | Should Match "GUARDING"
        }

        It "should attempt to stop the job and processes on 'stop'" {
            Mock Get-Job { return @{ Name = "GemmaGuardian"; State = "Running" } }
            $result = Invoke-VideoSurveillanceTool -action "stop"
            # In Pester 5, Assert-MockCalled is standard
            Assert-MockCalled Stop-Job -Exactly 1
            Assert-MockCalled Stop-Process -AtLeast 1
            $result | Should Match "Disarmed"
        }

        It "should detect the camera name correctly during 'start'" {
            $result = Invoke-VideoSurveillanceTool -action "start"
            $result | Should Match "active on 'Integrated Camera'"
        }
        
        It "should fail if ffmpeg is missing" {
            Mock Get-Command { param($name) if ($name -eq "ffmpeg") { return $null } else { return @{ Name = "node" } } }
            $result = Invoke-VideoSurveillanceTool -action "start"
            $result | Should Match "ERROR: FFmpeg is required"
        }
    }
}
