# tests/tutorial.Tests.ps1
# Pester tests for tutorial.ps1

Describe "Tutorial Tool" {
    BeforeAll {
        $toolPath = "$PSScriptRoot/../more_tools/tutorial.ps1"
        if (-not (Test-Path $toolPath)) { throw "tutorial.ps1 not found" }
        . $toolPath

        # Setup temp appdata
        $script:tempAppData = Join-Path $env:TEMP "gemmacli_tutorial_test_$(Get-Random)"
        New-Item -Path $script:tempAppData -ItemType Directory -Force | Out-Null
        $script:originalAppData = $env:APPDATA
        $env:APPDATA = $script:tempAppData

        # Fake tools directory
        $script:fakeToolsDir = Join-Path $script:tempAppData "fake_tools"
        New-Item -Path $script:fakeToolsDir -ItemType Directory -Force | Out-Null

        # Create fake tools with minimal valid structure to avoid Split-Path errors
        $fakeToolTemplate = @'
function Invoke-FakeTool {{ param() return "fake" }}
$ToolMeta = @{{ Name = "{0}"; Icon = "x"; Description = "fake"; Parameters = @{{}}; Execute = {{ param($p) Invoke-FakeTool @p }} }}
'@
        ($fakeToolTemplate -f "readfile") | Set-Content -Path (Join-Path $script:fakeToolsDir "readfile.ps1") -Encoding UTF8
        ($fakeToolTemplate -f "searchdir") | Set-Content -Path (Join-Path $script:fakeToolsDir "searchdir.ps1") -Encoding UTF8
        ($fakeToolTemplate -f "writefile") | Set-Content -Path (Join-Path $script:fakeToolsDir "writefile.ps1") -Encoding UTF8
    }

    AfterAll {
        $env:APPDATA = $script:originalAppData
        if (Test-Path $script:tempAppData) {
            Remove-Item $script:tempAppData -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    BeforeEach {
        $trackPath = Join-Path $script:tempAppData "GemmaCLI\tutorials_completed.json"
        if (Test-Path $trackPath) { Remove-Item $trackPath -Force }
    }

    Context "ToolMeta Block" {
        It "should have correct Name" {
            $ToolMeta.Name | Should Be "tutorial"
        }

        It "should have an Icon" {
            $ToolMeta.Icon | Should Not BeNullOrEmpty
            $ToolMeta.Icon.Length | Should BeGreaterThan 0
        }

        It "should have a Version" {
            $ToolMeta.Version | Should Not BeNullOrEmpty
            $ToolMeta.Version | Should Match "^\d+\.\d+\.\d+$"
        }

        It "should have Keywords" {
            ($ToolMeta.Keywords -contains "tutorial") | Should Be $true
            $ToolMeta.Keywords.Count | Should BeGreaterThan 0
        }

        It "should have Parameters" {
            ($ToolMeta.Parameters.Keys -contains "action") | Should Be $true
            ($ToolMeta.Parameters.Keys -contains "tool_name") | Should Be $true
        }
    }

    Context "Reset Action" {
        It "should wipe progress" {
            Invoke-TutorialTool -action "start" | Out-Null
            Invoke-TutorialTool -action "next_level" | Out-Null
            $result = Invoke-TutorialTool -action "reset"
            $result | Should Match "Progress wiped"
            $trackPath = Join-Path $script:tempAppData "GemmaCLI\tutorials_completed.json"
            Test-Path $trackPath | Should Be $false
        }
    }

    Context "Bootcamp" {
        It "should start at Level 1" {
            $result = Invoke-TutorialTool -action "start"
            $result | Should Match "Bootcamp Level 1"
        }

        It "should advance to Level 2" {
            Invoke-TutorialTool -action "start" | Out-Null
            $result = Invoke-TutorialTool -action "next_level"
            $result | Should Match "Bootcamp Level 2"
        }

        It "should reach Level 6" {
            Invoke-TutorialTool -action "start" | Out-Null
            1..4 | ForEach-Object { Invoke-TutorialTool -action "next_level" | Out-Null }
            $result = Invoke-TutorialTool -action "next_level"
            $result | Should Match "Bootcamp Level 6"
        }
    }

    Context "Logistics" {
        It "should prompt for tools when missing" {
            Invoke-TutorialTool -action "start" | Out-Null
            1..6 | ForEach-Object { Invoke-TutorialTool -action "next_level" | Out-Null }
            $emptyDir = Join-Path $script:tempAppData "empty"
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null
            $result = Invoke-TutorialTool -action "start" -current_tools_dir $emptyDir
            $result | Should Match "Waiting for tool activation"
        }

        It "should proceed to field lab when tools present" {
            Invoke-TutorialTool -action "start" | Out-Null
            1..6 | ForEach-Object { Invoke-TutorialTool -action "next_level" | Out-Null }
            $result = Invoke-TutorialTool -action "start" -current_tools_dir $script:fakeToolsDir
            $result | Should Match "Field Lab"
        }
    }

    Context "Field Lab" {
        BeforeEach {
            Invoke-TutorialTool -action "start" | Out-Null
            1..5 | ForEach-Object { Invoke-TutorialTool -action "next_level" | Out-Null }
        }

        It "should mark tool learned" {
            Invoke-TutorialTool -action "complete" -tool_name "readfile" -current_tools_dir $script:fakeToolsDir | Out-Null
            $trackPath = Join-Path $script:tempAppData "GemmaCLI\tutorials_completed.json"
            $state = Get-Content $trackPath | ConvertFrom-Json
            ($state.tools_learned -contains "readfile") | Should Be $true
        }
    }

    Context "Graduation" {
        BeforeEach {
            Invoke-TutorialTool -action "start" | Out-Null
            1..5 | ForEach-Object { Invoke-TutorialTool -action "next_level" | Out-Null }
            Invoke-TutorialTool -action "complete" -tool_name "readfile" -current_tools_dir $script:fakeToolsDir | Out-Null
            Invoke-TutorialTool -action "complete" -tool_name "searchdir" -current_tools_dir $script:fakeToolsDir | Out-Null
            Invoke-TutorialTool -action "complete" -tool_name "writefile" -current_tools_dir $script:fakeToolsDir | Out-Null
        }

        It "should show graduation module 1" {
            $result = Invoke-TutorialTool -action "start" -current_tools_dir $script:fakeToolsDir
            $result | Should Match "Graduation Module 1"
        }

        It "should complete after module 3" {
            Invoke-TutorialTool -action "start" -current_tools_dir $script:fakeToolsDir | Out-Null
            Invoke-TutorialTool -action "next_level" | Out-Null
            Invoke-TutorialTool -action "start" -current_tools_dir $script:fakeToolsDir | Out-Null
            Invoke-TutorialTool -action "next_level" | Out-Null
            $result = Invoke-TutorialTool -action "start" -current_tools_dir $script:fakeToolsDir
            $result | Should Match "Graduation Module 3"
        }
    }

    Context "Completion" {
        It "should finish training" {
            Invoke-TutorialTool -action "start" | Out-Null
            1..5 | ForEach-Object { Invoke-TutorialTool -action "next_level" | Out-Null }
            Invoke-TutorialTool -action "complete" -tool_name "readfile" -current_tools_dir $script:fakeToolsDir | Out-Null
            Invoke-TutorialTool -action "complete" -tool_name "searchdir" -current_tools_dir $script:fakeToolsDir | Out-Null
            Invoke-TutorialTool -action "complete" -tool_name "writefile" -current_tools_dir $script:fakeToolsDir | Out-Null
            Invoke-TutorialTool -action "start" -current_tools_dir $script:fakeToolsDir | Out-Null
            Invoke-TutorialTool -action "next_level" | Out-Null
            Invoke-TutorialTool -action "start" -current_tools_dir $script:fakeToolsDir | Out-Null
            Invoke-TutorialTool -action "next_level" | Out-Null
            Invoke-TutorialTool -action "start" -current_tools_dir $script:fakeToolsDir | Out-Null
            Invoke-TutorialTool -action "next_level" | Out-Null
            $result = Invoke-TutorialTool -action "start" -current_tools_dir $script:fakeToolsDir
            $result | Should Match "Training Complete"
        }
    }
}
