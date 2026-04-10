# tests/crop_image.Tests.ps1

Describe "Crop Image Tool" {
    BeforeAll {
        $toolPath = Join-Path $PSScriptRoot "../more_tools/crop_image.ps1"
        if (-not (Test-Path $toolPath)) {
            $toolPath = Join-Path $PSScriptRoot "../tools/crop_image.ps1"
        }
        $content = Get-Content -Path $toolPath -Raw -Encoding UTF8
        Invoke-Expression $content

        # Create a dummy bitmap for testing
        Add-Type -AssemblyName System.Drawing
        $script:testFile = Join-Path $env:TEMP "test_crop_image_$((Get-Date).Ticks).png"
        $bmp = [System.Drawing.Bitmap]::new(100, 100)
        $bmp.Save($script:testFile, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    }

    AfterAll {
        if (Test-Path $script:testFile) { Remove-Item $script:testFile -Force }
        # Cleanup any generated crops
        Get-ChildItem -Path $env:TEMP -Filter "test_crop_image_*_cropped_*.png" | Remove-Item -Force
    }

    It "should return an error for a non-existent file" {
        $result = Invoke-CropImageTool -file_path "C:\fake\image.png" -width 50 -height 50
        $result | Should Match "ERROR: File not found"
    }

    It "should return an error for an unsupported format" {
        $fakeWebp = Join-Path $env:TEMP "test.webp"
        New-Item -ItemType File -Path $fakeWebp -Force | Out-Null
        $result = Invoke-CropImageTool -file_path $fakeWebp -width 50 -height 50
        $result | Should Match "Unsupported file format"
        Remove-Item $fakeWebp -Force
    }

    It "should successfully crop a valid image" {
        $result = Invoke-CropImageTool -file_path $script:testFile -width 50 -height 50 -vertical_position "top" -horizontal_position "left"
        $result | Should Match "Image successfully cropped"
        $result | Should Match "Saved to:"
        
        # Verify the file actually exists
        # Regex: Look for 'Saved to: ', then match everything non-greedily until '::' or end of string
        if ($result -match "Saved to:\s*(.*?)(?:::|$)") {
            $path = $matches[1].Trim()
            # Write-Host "`n[DEBUG] Extracted Path: '$path'" -ForegroundColor Cyan
            (Test-Path $path) | Should Be $true
            if (Test-Path $path) { Remove-Item $path -Force }
        } else {
            fail "Could not extract path from result: $result"
        }
    }
}
