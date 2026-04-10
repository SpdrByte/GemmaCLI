# tests/video_editor.Tests.ps1
# Responsibility: Verify video_editor helper functions and ToolMeta registration.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = Split-Path -Parent $scriptDir
$toolPath = Join-Path $projectRoot "more_tools/video_editor.ps1"

Describe "Video Editor Tool" {
    BeforeAll {
        # Dot-source the tool to load its functions
        if (Test-Path $toolPath) {
            # Since the tool dot-sources UI.ps1, we might need to mock Draw-Box if it fails
            function Draw-Box { param($Lines, $Color, $Title) }
            . $toolPath
        } else {
            throw "video_editor.ps1 not found at $toolPath"
        }
    }

    Context "Helper Functions" {
        It "Get-VideoOutputPath should generate a valid path with timestamp" {
            $input = "C:\Videos\movie.mp4"
            $suffix = "trimmed"
            $result = Get-VideoOutputPath -inputPath $input -suffix $suffix
            
            $result | Should Match "movie_trimmed_\d{8}_\d{6}\.mp4"
            $result | Should Match "C:\\Videos\\"
        }

        It "Get-VideoOutputPath should allow overriding extension" {
            $input = "movie.mp4"
            $suffix = "thumb"
            $ext = "jpg"
            $result = Get-VideoOutputPath -inputPath $input -suffix $suffix -ext $ext
            
            $result | Should Match "movie_thumb_\d{8}_\d{6}\.jpg"
        }

        It "Escape-Arg should correctly handle paths with spaces" {
            $arg = "C:\My Videos\clip 1.mp4"
            $escaped = Escape-Arg $arg
            $escaped | Should Be '"C:\My Videos\clip 1.mp4"'
        }

        It "Escape-Arg should handle nested quotes" {
            $arg = 'text="Hello World"'
            $escaped = Escape-Arg $arg
            $escaped | Should Be '"text=\"Hello World\""'
        }
    }

    Context "Tool Registration" {
        It "should have a valid ToolMeta block" {
            $ToolMeta | Should Not Be $null
            $ToolMeta.Name | Should Be "video_editor"
            $ToolMeta.Parameters | Should Not Be $null
            $ToolMeta.Execute | Should BeOfType [scriptblock]
        }

        It "FormatLabel should include the operation name" {
            $params = @{ operation = "trim"; file_path = "test.mp4" }
            $label = & $ToolMeta.FormatLabel $params
            $label | Should Match "video_editor \[trim\]"
            $label | Should Match "test.mp4"
        }
    }

    Context "Main Dispatch" {
        It "should return an error if FFmpeg is missing" {
            # Mock Find-FFmpeg to return null
            function Find-FFmpeg { return $null }
            
            $result = Invoke-VideoEditTool -operation "trim" -file_path "test.mp4"
            $result | Should Match "ERROR: FFmpeg not found"
        }

        It "should return an error for unknown operations" {
            # Mock Find-FFmpeg to return something
            function Find-FFmpeg { return "ffmpeg.exe" }
            
            $result = Invoke-VideoEditTool -operation "invalid_op" -file_path "test.mp4"
            $result | Should Match "ERROR: Unknown operation"
        }
    }

    Context "New Operations Dispatch" {
        BeforeAll {
            function Find-FFmpeg { return "ffmpeg.exe" }
        }

        It "should dispatch to Ken Burns" {
            # Mock the Op-KenBurns function to verify dispatch
            function Op-KenBurns { return "DISPATCHED_KEN_BURNS" }
            $result = Invoke-VideoEditTool -operation "ken_burns" -file_path "test.jpg"
            $result | Should Be "DISPATCHED_KEN_BURNS"
        }

        It "should dispatch to Padding" {
            function Op-Padding { return "DISPATCHED_PADDING" }
            $result = Invoke-VideoEditTool -operation "padding" -file_path "test.mp4"
            $result | Should Be "DISPATCHED_PADDING"
        }

        It "should dispatch to Filter" {
            function Op-Filter { return "DISPATCHED_FILTER" }
            $result = Invoke-VideoEditTool -operation "filter" -file_path "test.mp4"
            $result | Should Be "DISPATCHED_FILTER"
        }
    }
}
