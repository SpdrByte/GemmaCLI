# ===============================================
# GemmaCLI Tool - nanobanana.ps1 v0.3.1
# Responsibility: Two-phase image generation with precise model-specific ratio filtering.
# ===============================================

function Invoke-NanoBananaTool {
    param(
        [string]$prompt,
        [string]$model = "auto",
        [int]$count = 1,
        [string]$aspect_ratio = "PENDING",
        [string]$image_size = "1K",
        [int]$seed = 0
    )

    # --- Feature-Based Model Selection ---
    $modelId = "gemini-2.5-flash-image" # Default "Nano" (2.5 Flash)

    # User tier preference mapping
    $tierMapping = @{
        "nano" = "gemini-2.5-flash-image"
        "2"    = "gemini-3.1-flash-image-preview"
        "pro"  = "gemini-3-pro-image-preview"
    }

    if ($model -ne "auto" -and $tierMapping.ContainsKey($model.ToLower())) {
        $modelId = $tierMapping[$model.ToLower()]
    }

    # Resolution/Feature Overrides based on user data
    if ($image_size -eq "512") {
        # Only 3.1 Flash supports 512
        $modelId = "gemini-3.1-flash-image-preview"
    }
    elseif ($image_size -eq "2K" -or $image_size -eq "4K") {
        if ($model -eq "2") {
            $modelId = "gemini-3.1-flash-image-preview"
        } else {
            # Default to Pro for high res unless Tier 2 requested
            $modelId = "gemini-3-pro-image-preview"
        }
    }

    # --- Aspect Ratio Data Sets ---
    # Set A (3.1 Flash): Extreme ratios supported (1:4, 4:1, 1:8, 8:1)
    $ratios_31_flash = @("1:1", "1:4", "1:8", "2:3", "3:2", "3:4", "4:1", "4:3", "4:5", "5:4", "8:1", "9:16", "16:9", "21:9")
    
    # Set B (3 Pro & 2.5 Flash): Standard ratios only
    $ratios_standard = @("1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9")

    $availableRatios = if ($modelId -eq "gemini-3.1-flash-image-preview") { $ratios_31_flash } else { $ratios_standard }

    # --- Phase 1: Ratio Confirmation ---
    if ($aspect_ratio -eq "PENDING") {
        $ratioStr = $availableRatios -join ", "
        $msg = "RESOLUTION_SET::$image_size::AVAILABLE_RATIOS::$ratioStr"
        return "CONSOLE::$msg::END_CONSOLE::Step 1 Complete: Resolution set to $image_size. Now ask the user which Aspect Ratio they want from this SPECIFIC list for the selected model: $ratioStr. Do NOT proceed with generation until they pick one from this list."
    }

    # --- Validation ---
    if ($aspect_ratio -notin $availableRatios) {
        return "ERROR: The aspect ratio '$aspect_ratio' is not supported for the selected model/size. Please choose from: $($availableRatios -join ', ')"
    }

    # --- API Key Check ---
    if (-not $script:API_KEY) {
        return "ERROR: Google API key not found. Please set `$script:API_KEY`."
    }

    # --- Daily Call Limit Tracking ---
    $limitFilePath = Join-Path $env:APPDATA "GemmaCLI/nanobanana_limits.json"
    $currentDate = (Get-Date).ToString("yyyy-MM-dd")
    $limits = @{}
    if (Test-Path $limitFilePath) {
        try {
            $jsonContent = Get-Content $limitFilePath -Raw -Encoding UTF8
            $parsedJson = $jsonContent | ConvertFrom-Json
            foreach ($dateKey in $parsedJson.PSObject.Properties.Name) {
                $limits[$dateKey] = @{}
                foreach ($mKey in $parsedJson.$dateKey.PSObject.Properties.Name) {
                    $limits[$dateKey][$mKey] = [int]$parsedJson.$dateKey.$mKey
                }
            }
            $limits.Keys | Where-Object { $_ -ne $currentDate } | ForEach-Object { $limits.Remove($_) }
        } catch { }
    }
    if (-not $limits.ContainsKey($currentDate)) { $limits[$currentDate] = @{} }
    if (-not $limits[$currentDate].ContainsKey($modelId)) { $limits[$currentDate][$modelId] = 0 }

    $limits[$currentDate][$modelId] += 1
    if ($limits[$currentDate][$modelId] -gt 25) {
        $limits[$currentDate][$modelId] -= 1
        $limits | ConvertTo-Json -Depth 3 | Set-Content $limitFilePath -Encoding UTF8
        return "ERROR: Daily call limit (25) for model tier '$modelId' exceeded. Try again tomorrow."
    }
    $limits | ConvertTo-Json -Depth 3 | Set-Content $limitFilePath -Encoding UTF8

    # --- Phase 2: Actual Generation ---
    try {
        $uri = "https://generativelanguage.googleapis.com/v1beta/models/${modelId}:generateContent?key=$script:API_KEY"

        $body = @{
            "contents" = @( @{ "parts" = @( @{ "text" = $prompt } ) } )
            "generationConfig" = @{ 
                "responseModalities" = @("IMAGE", "TEXT")
                "imageConfig" = @{ 
                    "aspectRatio" = $aspect_ratio
                    "imageSize"   = $image_size 
                }
            }
        }

        $jsonBody = $body | ConvertTo-Json -Compress -Depth 6

        Write-Host "Calling NanoBanana API (${modelId}) for prompt: '$prompt' [$image_size, $aspect_ratio]..." -ForegroundColor DarkGray
        $rawResponse = Invoke-WebRequest -Uri $uri -Method Post -Body $jsonBody -ContentType "application/json" -UseBasicParsing -ErrorAction Stop
        $response = $rawResponse.Content | ConvertFrom-Json

        $parts = $response.candidates[0].content.parts
        $imageParts = $parts | Where-Object { $_.inlineData -ne $null }

        if (-not $imageParts) {
            return "ERROR: No image returned. Response: $($response | ConvertTo-Json -Depth 5)"
        }

        $output = @()
        $i = 0
        foreach ($part in $imageParts) {
            $b64  = $part.inlineData.data
            $mime = $part.inlineData.mimeType
            $ext  = if ($mime -eq "image/png") { "png" } else { "jpg" }
            $tempFileName = "nanobanana_gen_$((Get-Date).Ticks)_$i.$ext"
            $tempFilePath = Join-Path $env:TEMP $tempFileName

            [System.IO.File]::WriteAllBytes($tempFilePath, [System.Convert]::FromBase64String($b64))
            $output += "Image generated ($image_size, $aspect_ratio): '$prompt' (File: $tempFilePath)"
            $i++
        }
        
        $summary = $output -join "`n"
        return "CONSOLE::$summary::END_CONSOLE::$summary"

    } catch {
        $errorBody = if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { "(no details)" }
        $tip = if ($image_size -ne "1K") { " TIP: If you are using a free-tier API key, high resolutions like 2K/4K or specific models may be restricted. Try 1K or 512 instead." } else { "" }
        return "ERROR: NanoBanana API call failed. Model: $modelId. Message: $($_.Exception.Message) | Body: $errorBody$tip"
    }
}

# --- Self-registration block ---
$ToolMeta = @{
    Name        = "nanobanana"
    Behavior    = "Use this tool to generate images. It uses a two-step process: First confirm the size to find valid ratios, then generate."
    Description = "Generates images. Step 1 sets size; Step 2 sets ratio and generates. Note: 2K/4K may require a paid API tier."
    Parameters  = @{
        prompt       = "string - Detailed description of the image."
        model        = "string - Optional tier: 'nano', '2', or 'pro'. Default is 'auto'."
        image_size   = "string - Resolution: '512', '1K', '2K', or '4K'. Default is '1K'."
        aspect_ratio = "string - Ratio: Use 'PENDING' for the first call to get valid options. Default is 'PENDING'."
        count        = "int - Number of images (1-4). Default is 1."
    }
    Example     = "<tool_call>{ ""name"": ""nanobanana"", ""parameters"": { ""prompt"": ""A cat."", ""image_size"": ""1K"" } }</tool_call>"
    FormatLabel = { param($p) "🍌 NanoBanana -> $($p.prompt) [$($p.image_size)]" }
    Execute     = { param($params) Invoke-NanoBananaTool @params }
    ToolUseGuidanceMajor = @"
        - When to use 'nanobanana': Use this whenever the user wants to create an image.
        - INTERACTION FLOW (Two-Step Process):
            1. STEP 1 (Size Selection): Ask the user for the Resolution (512, 1K, 2K, or 4K).
            2. Call nanobanana with `prompt` and `image_size`. Leave `aspect_ratio` as 'PENDING'.
            3. STEP 2 (Ratio Selection): The tool will return a list of AVAILABLE_RATIOS for that specific model.
            4. Ask the user to choose from that SPECIFIC list. (Do NOT use 'etc.', list them all).
            5. Final Call: Call nanobanana again with the `prompt`, `image_size`, AND the chosen `aspect_ratio`.
        - Model Mapping (Internal):
            - 512 -> Nano Banana 2 (3.1 Flash). Supports extreme ratios like 1:8, 8:1, 1:4, 4:1.
            - 2K/4K -> Nano Banana Pro (3 Pro). Supports standard ratios only.
            - 1K -> Nano Banana (2.5 Flash). Supports standard ratios only.
        - API LIMITATION WARNING: High resolutions (2K, 4K) or the 'Pro' model may not be available on all free-tier API keys. If the tool returns a permission or tier error, advise the user to try 1K or 512.
"@
    ToolUseGuidanceMinor = @"
        - Step 1: Ask for Size. Call tool with Size and aspect_ratio='PENDING'.
        - Step 2: Ask user for Ratio from the returned list. Call tool again to generate.
        - Warning: 2K/4K might fail on free API keys; suggest 1K if it does.
"@
}
