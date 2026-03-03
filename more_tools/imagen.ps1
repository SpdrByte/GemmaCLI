# ===============================================
# GemmaCLI Tool - imagen.ps1 v0.1.0
# Responsibility: Generates images using Google's Imagen API.
# ===============================================

function Invoke-ImagenTool {
    param(
        [string]$prompt,
        [string]$model = "gemini-2.0-flash-exp-image-generation",
        [int]$count = 1,
        [int]$seed = 0
    )

    # --- Model Shorthand Translation ---
    $modelAliases = @{ 
        "flash"    = "gemini-2.0-flash-exp-image-generation"
        "standard" = "gemini-2.0-flash-exp-image-generation"
        "nano"     = "gemini-2.5-flash-image"
        "pro"      = "gemini-3-pro-image-preview"
    }
    if ($modelAliases.ContainsKey($model.ToLower())) { 
        $model = $modelAliases[$model.ToLower()] 
    }

    if ([string]::IsNullOrWhiteSpace($model)) {
        $model = "gemini-2.0-flash-exp-image-generation"
    }
    
    # --- Model Validation ---
    $validModels = @(
        "gemini-2.0-flash-exp-image-generation",
        "gemini-2.5-flash-image",
        "gemini-3-pro-image-preview"
    )
    if ($model -notin $validModels) {
        return "ERROR: Invalid model '$model'. Choose from: flash, nano, pro."
    }

    # --- API Key Check ---
    if (-not $script:API_KEY) {
        return "ERROR: Google API key not found. Please set `$script:API_KEY`."
    }

    # --- Prompt Token Limit (Approximate) ---
    if (($prompt -split '\s').Length -gt 480) {
        return "ERROR: Prompt exceeds 480 token limit. Please shorten your prompt."
    }

    # --- Image Count Validation ---
    if ($count -lt 1 -or $count -gt 4) {
        return "ERROR: Number of images (count) must be between 1 and 4."
    }

    # --- Daily Call Limit Tracking (25 calls/day per model) ---
    $limitFilePath = Join-Path $env:APPDATA "GemmaCLI/imagen_limits.json"
    $currentDate = (Get-Date).ToString("yyyy-MM-dd")
    $limits = @{}

    if (Test-Path $limitFilePath) {
        try {
            $jsonContent = Get-Content $limitFilePath -Raw -Encoding UTF8
            $parsedJson = $jsonContent | ConvertFrom-Json
            foreach ($dateKey in $parsedJson.PSObject.Properties.Name) {
                $limits[$dateKey] = @{}
                foreach ($modelKey in $parsedJson.$dateKey.PSObject.Properties.Name) {
                    $limits[$dateKey][$modelKey] = [int]$parsedJson.$dateKey.$modelKey
                }
            }
            # Prune old dates
            $limits.Keys | Where-Object { $_ -ne $currentDate } | ForEach-Object { $limits.Remove($_) }
        } catch {
            Write-Host "WARN: Failed to read imagen_limits.json. Resetting limits." -ForegroundColor Yellow
        }
    }
    
    if (-not $limits.ContainsKey($currentDate)) {
        $limits[$currentDate] = @{}
    }
    if (-not $limits[$currentDate].ContainsKey($model)) {
        $limits[$currentDate][$model] = 0
    }

    $limits[$currentDate][$model] += 1

    if ($limits[$currentDate][$model] -gt 25) {
        $limits[$currentDate][$model] -= 1
        $limits | ConvertTo-Json -Depth 3 | Set-Content $limitFilePath -Encoding UTF8
        return "ERROR: Daily call limit (25) for model '$model' exceeded. Try again tomorrow."
    }
    $limits | ConvertTo-Json -Depth 3 | Set-Content $limitFilePath -Encoding UTF8

    # --- API Call ---
    try {
        $uri = "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=$script:API_KEY"

        $body = @{
            "contents" = @(
                @{
                    "parts" = @(
                        @{ "text" = $prompt }
                    )
                }
            )
            "generationConfig" = @{
                "responseModalities" = @("IMAGE", "TEXT")
            }
        }

        $jsonBody = $body | ConvertTo-Json -Compress -Depth 6

        Write-Host "Calling Gemini image generation with model '$model'..." -ForegroundColor DarkGray
        $rawResponse = Invoke-WebRequest -Uri $uri -Method Post -Body $jsonBody `
            -ContentType "application/json" `
            -ErrorAction Stop
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

            $ext          = if ($mime -eq "image/png") { "png" } else { "jpg" }
            $tempFileName = "imagen_generated_$((Get-Date).Ticks)_$i.$ext"
            $tempFilePath = Join-Path $env:TEMP $tempFileName

            [System.IO.File]::WriteAllBytes($tempFilePath, [System.Convert]::FromBase64String($b64))
            $output += "IMAGE_DATA::$mime::$b64::Generated image for prompt: '$prompt' (File: $tempFilePath)"
            $i++
        }
        return ($output -join "`n")

    } catch {
        $errorBody = $_.ErrorDetails.Message
        return "ERROR: Imagen API call failed. Message: $($_.Exception.Message) | Body: $errorBody"
    }
}

# --- Self-registration block ---
$ToolMeta = @{
    Name        = "imagen"
    Behavior    = "Use this tool to generate high-quality images from textual descriptions. Ideal for creative tasks, visual asset generation, or illustrating concepts."
    Description = "Generates images from a text prompt using Google's Imagen 4.0 API, supporting different models for varying quality and speed."
    Parameters  = @{
        prompt = "string - A detailed textual description of the image to generate."
        model  = "string - Model to use. Default is 'gemini-2.0-flash-exp'."
        count  = "int - Number of images to generate (1-4). Default is 1."
    }
    Example     = "<tool_call>{ ""name"": ""imagen"", ""parameters"": { ""prompt"": ""A serene landscape with a river and mountains, cinematic light."", ""model"": ""standard"", ""count"": 2 } }</tool_call>"
    FormatLabel = { param($p) "🎨 Imagen -> $($p.prompt)" }
    Execute     = { param($params) Invoke-ImagenTool @params }
    ToolUseGuidanceMajor = @"
        - When to use 'imagen': Use this tool to generate visual content based on a textual description. Choose this when the user requires an image for illustration, concept visualization, or creative content creation.
        - Important parameters for 'imagen': 
            - `prompt`: Craft a detailed, descriptive prompt. The quality of the generated image heavily depends on the clarity and detail of the prompt (max 480 tokens).
            - `model`: Select 'ultra' for highest quality and detail (supports 2K output), 'standard' for a balanced approach, or 'fast' for quicker results.
            - `aspect_ratio`: Specify the desired image orientation (e.g., '16:9' for widescreen, '1:1' for square).
            - `image_size`: Choose '1K' or '2K' for resolution; remember '2K' is 'ultra' model exclusive.
            - `count`: Generate multiple variations (1-4) to provide options.
            - `seed`: Use a `seed` value for experimentation if you wish to generate reproducible results or explore variations around a specific image.
        - Daily Limit: Be mindful of the 25 daily call limit per model. Conserve calls by refining prompts carefully and generating multiple images (`count`) in a single call if variations are desired.
        - Output: Images are returned as base64 encoded data, typically for multimodal response.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Create images from text.
        - Basic use: Give a short `prompt` for the image idea.
        - Important: The tool can make 1 to 4 images.

"@
}