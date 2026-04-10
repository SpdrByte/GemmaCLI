# ===============================================
# GemmaCLI Tool - git.ps1 v0.2.0
# Responsibility: Check various git data
# ===============================================

function Invoke-GitTool {
    param(
        [string]$action = "status"
    )

    # Check if git is installed
    $gitAvailable = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
    if (-not $gitAvailable) {
        return "ERROR: Git is not installed. Install Git from https://git-scm.com/download/win"
    }

    # Check if current directory is a git repository
    $isGitRepo = Test-Path ".git" -PathType Container
    if (-not $isGitRepo) {
        return "ERROR: Current directory is not a Git repository. Use 'git init' to initialize."
    }

    try {
        switch ($action.ToLower()) {
            "status" {
                # Get repository information
                $repoUrl = git config --get remote.origin.url 2>$null
                $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
                $commitHash = git rev-parse --short HEAD 2>$null
                $commitMessage = git log -1 --pretty=%B 2>$null
                $uncommitted = (git status --porcelain 2>$null | Measure-Object).Count
                
                $info = @{
                    status         = "initialized"
                    remote_url     = $repoUrl
                    current_branch = $currentBranch
                    latest_commit  = $commitHash
                    commit_message = $commitMessage.Trim()
                    uncommitted    = $uncommitted
                }
                
                return "OK: Git repository initialized`n" + ($info | ConvertTo-Json)
            }
            
            "check" {
                return "OK: Git is initialized in this directory"
            }
            
            "branch" {
                $branch = git rev-parse --abbrev-ref HEAD 2>$null
                return "OK: Current branch is '$branch'"
            }
            
            "remote" {
                $remote = git config --get remote.origin.url 2>$null
                if ([string]::IsNullOrWhiteSpace($remote)) {
                    return "INFO: No remote configured"
                }
                return "OK: Remote URL: $remote"
            }
            
            default {
                return "ERROR: Unknown action '$action'. Available: status, check, branch, remote"
            }
        }
    } catch {
        return "ERROR: Git operation failed - $($_.Exception.Message)"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────
$ToolMeta = @{
    Name        = "git"
    Icon        = "🔍"
    RendersToConsole = $false
    Category    = @("System Administration", "Coding/Development")

    Description = "Checks if git is initialized in the current directory and returns repository info"    
    Behavior    = "Use this tool when the user asks about git status, current branch, uncommitted changes, or repository information. Safe read-only operation."
    
    Parameters  = @{
        action = "string - action to perform: 'status' (default), 'check', 'branch', 'remote'"
    }
    
    Example     = '<tool_call>{"name": "git", "parameters": {"action": "status"}}</tool_call>'
    
    FormatLabel = { param($params) "$($params.action)" }
    
    Execute     = {
        param($params)
        Invoke-GitTool @params
    }
    ToolUseGuidanceMajor = @"
        - Use this tool for git request.
        - When displaying results, present ALL fields from the JSON response verbatim in a structured way (branch, commit hash, message, remote URL, uncommitted count). Do not summarize or paraphrase unless user explicity requests you to.
"@

    ToolUseGuidanceMinor = @"
        - Use this tool for git request.
"@
}
