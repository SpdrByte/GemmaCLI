# ===============================================
# GemmaCLI Tool - build_site.ps1 v0.2.0
# Responsibility: Automates website deployment preparation.
#                 Syncs a source directory to a build staging area,
#                 creates a compressed archive, and verifies output.
#                 Supports dry-run mode, exclusion lists, and SHA-256 hashing.
# Depends on: none (self-contained)
# ===============================================

# ====================== HELPERS ======================

function Draw-Box {
    param(
        [string[]]$Lines,
        [string]$Title = "",
        [string]$Color = "Cyan"
    )

    $TL = [string][char]0x256D   # ╭
    $TR = [string][char]0x256E   # ╮
    $BL = [string][char]0x2570   # ╰
    $BR = [string][char]0x256F   # ╯
    $H  = [string][char]0x2500   # ─
    $V  = [string][char]0x2502   # │

    $maxLen = 2
    foreach ($l in $Lines) { if ($l.Length -gt $maxLen) { $maxLen = $l.Length } }
    if ($Title.Length -gt $maxLen) { $maxLen = $Title.Length }
    $inner = $maxLen + 2

    $titleText  = if ($Title) { " $Title " } else { "" }
    $titleFill  = $inner - $titleText.Length
    $fillLeft   = [Math]::Floor($titleFill / 2)
    $fillRight  = [Math]::Max(0, $titleFill - $fillLeft)
    $topBorder  = $TL + ($H * $fillLeft) + $titleText + ($H * $fillRight) + $TR

    Write-Host ""
    Write-Host ("  " + $topBorder) -ForegroundColor $Color
    foreach ($l in $Lines) {
        $padded = $l.PadRight($maxLen)
        Write-Host ("  " + $V + " " + $padded + " " + $V) -ForegroundColor $Color
    }
    Write-Host ("  " + $BL + ($H * $inner) + $BR) -ForegroundColor $Color
    Write-Host ""
}

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

# ====================== CORE DEPLOY LOGIC ======================

function Invoke-BuildSite {
    param(
        [string]$action,
        [string]$sourcePath,
        [string]$buildPath   = "./build",
        [string]$archiveName = "build_site.zip",
        [string]$exclude     = "",
        [string]$dryRun      = "false"
    )

    $ARR = [string][char]0x2192   # →
    $BUL = [string][char]0x2022   # •

    $isDryRun  = ($dryRun -eq "true" -or $dryRun -eq "1")
    $excludeList = @(".git", ".env", ".env.local", "node_modules", "*.log")
    if (-not [string]::IsNullOrWhiteSpace($exclude)) {
        $excludeList += $exclude.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    }

    # ---- RESOLVE PATHS RELATIVE TO SOURCE PARENT IF NOT ROOTED ----
    if ([string]::IsNullOrWhiteSpace($sourcePath)) {
        return "ERROR: 'sourcePath' is required for all actions to determine output locations relative to the site directory."
    }

    $sourceResolved = Resolve-Path $sourcePath -ErrorAction SilentlyContinue
    if (-not $sourceResolved) {
        return "ERROR: sourcePath '$sourcePath' not found or is not accessible."
    }
    $sourceParent = Split-Path $sourceResolved.Path -Parent
    
    # Resolve buildPath relative to source parent if it's relative
    if (-not [System.IO.Path]::IsPathRooted($buildPath)) {
        $buildPath = Join-Path $sourceParent $buildPath
    }

    # Resolve archive output path relative to source parent if it's relative
    if (-not [System.IO.Path]::IsPathRooted($archiveName)) {
        $archiveDest = Join-Path $sourceParent $archiveName
    } else {
        $archiveDest = $archiveName
    }

    # ---- VALIDATE ----
    if ($action -eq "validate") {
        $fileCount  = (Get-ChildItem -Recurse -File -Path $sourceResolved).Count
        $totalBytes = (Get-ChildItem -Recurse -File -Path $sourceResolved | Measure-Object -Property Length -Sum).Sum
        $lines = @(
            "Source path is valid",
            "",
            "  Path      $sourceResolved",
            "  Files     $fileCount",
            "  Total     $(Format-FileSize $totalBytes)"
        )
        Draw-Box -Lines $lines -Title "Validate: Source" -Color Green
        $result = @{ ok=$true; sourcePath="$sourceResolved"; fileCount=$fileCount; totalBytes=$totalBytes } | ConvertTo-Json -Depth 4
        return "CONSOLE::Validation complete.::END_CONSOLE::$result"
    }

    # ---- SYNC ----
    if ($action -eq "sync") {
        # Collect files respecting exclusions
        $allFiles = Get-ChildItem -Recurse -File -Path $sourceResolved | Where-Object {
            $rel  = $_.FullName.Substring($sourceResolved.Path.Length).TrimStart('\','/')
            $skip = $false
            foreach ($pat in $excludeList) {
                if ($rel -like $pat -or $_.Name -like $pat -or $rel -like "$pat*" -or $rel -like "*\$pat\*" -or $rel -like "*/$pat/*") {
                    $skip = $true; break
                }
            }
            -not $skip
        }

        if ($isDryRun) {
            $previewLines = @("DRY RUN — files that WOULD be copied", "", "  Source  $sourceResolved", "  Build   $buildPath", "  Exclude $($excludeList -join ', ')", "")
            foreach ($f in $allFiles | Select-Object -First 20) {
                $rel = $f.FullName.Substring($sourceResolved.Path.Length).TrimStart('\','/')
                $previewLines += "  $BUL $rel"
            }
            if ($allFiles.Count -gt 20) { $previewLines += "  ... and $($allFiles.Count - 20) more file(s)" }
            $previewLines += ""
            $previewLines += "  Total files: $($allFiles.Count)"
            Draw-Box -Lines $previewLines -Title "Sync: Dry Run" -Color Yellow
            $result = @{ dryRun=$true; fileCount=$allFiles.Count; sourcePath="$sourceResolved"; buildPath=$buildPath } | ConvertTo-Json -Depth 4
            return "CONSOLE::Dry run complete.::END_CONSOLE::$result"
        }

        # Prepare build directory
        if (Test-Path $buildPath) {
            $fullBuildPath = (Resolve-Path $buildPath).Path
            if ($fullBuildPath -eq (Get-Location).Path -or $fullBuildPath -eq $sourceResolved.Path) {
                return "ERROR: buildPath cannot be the current working directory or the source directory."
            }
            Remove-Item -Recurse -Force $buildPath
        }
        New-Item -ItemType Directory -Path $buildPath -Force | Out-Null

        # Test write permissions
        try {
            $testFile = Join-Path $buildPath ".write_test"
            [System.IO.File]::WriteAllText($testFile, "test")
            Remove-Item $testFile -Force
        } catch {
            return "ERROR: No write permission for build path '$buildPath': $($_.Exception.Message)"
        }

        $copied = 0
        foreach ($f in $allFiles) {
            $rel     = $f.FullName.Substring($sourceResolved.Path.Length).TrimStart('\','/')
            $dest    = Join-Path $buildPath $rel
            $destDir = Split-Path $dest -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            $f_path = $f.FullName
            Copy-Item $f_path -Destination $dest -Force
            $copied++
        }

        $lines = @(
            "Sync complete",
            "",
            "  Source     $sourceResolved",
            "  Build      $buildPath",
            "  Copied     $copied file(s)",
            "  Excluded   $($excludeList -join ', ')"
        )
        Draw-Box -Lines $lines -Title "Sync: Complete" -Color Green
        $result = @{ ok=$true; sourcePath="$sourceResolved"; buildPath=$buildPath; filesCopied=$copied; excluded=$excludeList } | ConvertTo-Json -Depth 4
        return "CONSOLE::Sync complete.::END_CONSOLE::$result"
    }

    # ---- ARCHIVE ----
    if ($action -eq "archive") {
        if (-not (Test-Path $buildPath -PathType Container)) {
            return "ERROR: buildPath '$buildPath' does not exist. Run action='sync' first."
        }

        if (Test-Path $archiveDest) { Remove-Item $archiveDest -Force }

        # Compress contents (not the folder itself as root)
        try {
            $resolvedBuild = (Resolve-Path $buildPath).Path
            Compress-Archive -Path (Join-Path $resolvedBuild "*") -DestinationPath $archiveDest -Force
        } catch {
            return "ERROR: Failed to create archive '$archiveDest': $($_.Exception.Message)"
        }

        if (-not (Test-Path $archiveDest)) {
            return "ERROR: Archive was not created at '$archiveDest'. Unknown failure."
        }

        $archiveInfo = Get-Item $archiveDest
        $sizeStr     = Format-FileSize $archiveInfo.Length

        # SHA-256
        $sha256 = (Get-FileHash -Path $archiveDest -Algorithm SHA256).Hash

        $lines = @(
            "Archive created successfully",
            "",
            "  Path    $archiveDest",
            "  Size    $sizeStr",
            "  SHA256  $sha256"
        )
        Draw-Box -Lines $lines -Title "Archive: Complete" -Color Green
        $result = @{ ok=$true; archivePath=$archiveDest; sizeBytes=$archiveInfo.Length; sizeFormatted=$sizeStr; sha256=$sha256 } | ConvertTo-Json -Depth 4
        return "CONSOLE::Archive created.::END_CONSOLE::$result"
    }

    # ---- DEPLOY (sync + archive in one shot) ----
    if ($action -eq "deploy") {
        if ([string]::IsNullOrWhiteSpace($sourcePath)) {
            return "ERROR: 'sourcePath' is required for action 'deploy'."
        }

        Write-Host ""
        Write-Host "  [build_site.ps1] Starting full deploy pipeline..." -ForegroundColor DarkGray

        # Step 1 — Sync
        $syncResult = Invoke-BuildSite -action "sync" -sourcePath $sourcePath -buildPath $buildPath -archiveName $archiveName -exclude $exclude -dryRun $dryRun
        if ($syncResult -like "ERROR:*") { return $syncResult }

        # Bail here if dry run — no point archiving
        if ($isDryRun) { return $syncResult }

        # Step 2 — Archive
        $archResult = Invoke-BuildSite -action "archive" -sourcePath $sourcePath -buildPath $buildPath -archiveName $archiveName -exclude $exclude -dryRun $dryRun
        if ($archResult -like "ERROR:*") { return $archResult }

        # Parse archive JSON from the CONSOLE:: wrapper
        $archJson = $archResult -replace "CONSOLE::.*?::END_CONSOLE::", ""
        $archData = $archJson | ConvertFrom-Json

        $lines = @(
            "Full deploy pipeline complete",
            "",
            "  Source    $sourcePath",
            "  Build     $buildPath",
            "  Archive   $($archData.archivePath)",
            "  Size      $($archData.sizeFormatted)",
            "  SHA256    $($archData.sha256)"
        )
        Draw-Box -Lines $lines -Title "Deploy: Done" -Color Green
        $result = @{ ok=$true; sourcePath=$sourcePath; buildPath=$buildPath; archivePath=$archData.archivePath; sizeFormatted=$archData.sizeFormatted; sha256=$archData.sha256 } | ConvertTo-Json -Depth 4
        return "CONSOLE::Deploy pipeline complete.::END_CONSOLE::$result"
    }

    return "ERROR: Unknown action '$action'. Valid actions: validate, sync, archive, deploy"
}

# ====================== TOOL REGISTRATION ======================

$ToolMeta = @{
    Name             = "build_site"
    Icon             = "🏗️"
    RendersToConsole = $true
    Category    = @("Coding/Development")
    Behavior         = "Prepares website files for deployment: validates source paths, syncs to a build directory, and produces a compressed archive. Call when the user wants to build, package, or deploy website files. Do NOT call proactively or speculatively."
    Description      = "Automate website deployment prep: validate a source directory, sync files to a build folder (with exclusions and dry-run support), create a deployment ZIP archive, and verify output with SHA-256."
    Parameters       = @{
        action      = "string - one of: validate | sync | archive | deploy"
        sourcePath  = "string (required for validate, sync, deploy) - path to the source website directory"
        buildPath   = "string (optional) - staging directory for deployment-ready files. Default: './build'"
        archiveName = "string (optional) - output archive filename. Default: 'build_site.zip'"
        exclude     = "string (optional) - comma-separated additional exclusion patterns e.g. '*.tmp,secrets'"
        dryRun      = "string (optional) - set to 'true' to preview files without making changes. Default: 'false'"
    }
    Example          = @"
<tool_call>{ "name": "build_site", "parameters": { "action": "validate", "sourcePath": "./my-site" } }</tool_call>
<tool_call>{ "name": "build_site", "parameters": { "action": "sync", "sourcePath": "./my-site", "buildPath": "./build", "dryRun": "true" } }</tool_call>
<tool_call>{ "name": "build_site", "parameters": { "action": "sync", "sourcePath": "./my-site", "buildPath": "./build", "exclude": "*.tmp,drafts" } }</tool_call>
<tool_call>{ "name": "build_site", "parameters": { "action": "archive", "buildPath": "./build", "archiveName": "release_v2.zip" } }</tool_call>
<tool_call>{ "name": "build_site", "parameters": { "action": "deploy", "sourcePath": "./my-site", "buildPath": "./build", "archiveName": "build_site.zip" } }</tool_call>
"@
    FormatLabel      = { param($p)
        $src = ""
        if ($p.sourcePath) { $src = " $ARR $($p.sourcePath)" }
        $dry = ""
        if ($p.dryRun -eq "true") { $dry = " [dry-run]" }
        "$($p.action)$src$dry"
    }
    Execute          = {
        param($params)
        Invoke-BuildSite @params
    }
    ToolUseGuidanceMajor = @"
- When to use 'build_site': ALWAYS use when the user asks to package, build, sync, or deploy a static website directory.
- Recommended workflow:
    1. Call build_site action='validate' to confirm the source path exists and review file counts
    2. Call build_site action='sync' with dryRun='true' to preview what will be copied
    3. Call build_site action='sync' (no dry-run) to populate the build directory
    4. Call build_site action='archive' to create the deployment ZIP
    5. Report the archive path, size, and SHA-256 hash to the user
- OR use action='deploy' to run steps 3+4 in a single call.
- Default exclusions (always applied): .git, .env, .env.local, node_modules, *.log
- Additional exclusions can be passed via 'exclude' as a comma-separated string
- dryRun='true' is safe for validation — no files are written or deleted
- action='archive' zips the BUILD CONTENTS directly, not the build folder as a root entry
- SHA-256 is always computed and returned with archive results for integrity verification
"@
    ToolUseGuidanceMinor = @"
- Purpose: Website deployment packaging — sync, zip, verify.
- Use action='deploy' for a one-shot sync + archive pipeline.
- Always surface the archive path and SHA-256 hash to the user after archiving.
"@
}
