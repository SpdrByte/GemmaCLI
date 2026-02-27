# lib/Api.ps1
# Responsibility: Manages interactions with the Google Gemini API, including Job management and error handling.
# Handles the Start-Job logic for API calls.

function Invoke-GemmaApi {
    param($uri, $history, $gConfig)

    $script:apiJob = Start-Job -ScriptBlock {
        param($uri, $contents, $gConfig)
        $payload = @{
            contents         = $contents
            generationConfig = $gConfig
        } | ConvertTo-Json -Depth 20 -Compress
        # Send as UTF8 bytes to avoid PowerShell string encoding issues
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        try {
            Invoke-RestMethod -Uri $uri -Method POST -ContentType "application/json; charset=utf-8" -Body $bytes
        } catch {
            $detail = ""
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($stream)
                $raw    = $reader.ReadToEnd()
                $json   = $raw | ConvertFrom-Json
                $detail = if ($json.error.message) { $json.error.message } else { $raw }
            } catch {}
            $msg = if ($detail) { $detail } else { $_.Exception.Message }
            [PSCustomObject]@{ apiError = $msg }
        }
    } -ArgumentList $uri, $history, $gConfig

    $cancelled = $false
    while ($script:apiJob.State -eq "Running") {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq "Escape") {
                $cancelled = $true
                Stop-Job $script:apiJob
                break
            }
        }
        Start-Sleep -Milliseconds 100
    }

    if ($cancelled) {
        Remove-Job $script:apiJob
        return [PSCustomObject]@{ cancelled = $true }
    }

    $resp = Receive-Job $script:apiJob
    Remove-Job $script:apiJob
    return $resp
}
