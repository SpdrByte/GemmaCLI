# ===============================================
# GemmaCLI Tool - server_manager.ps1 v1.0.2
# Responsibility: Manages active server processes by listing listening ports or killing specific PIDs.
# ===============================================

function Invoke-ServerManagerTool {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("list", "kill")]
        [string]$action,

        [Parameter(Mandatory = $false)]
        [int]$port
    )

    $results = @()
    $consoleOutput = ""
    $aiData = ""

    try {
        if ($action -eq "list") {
            # Get netstat output for listening ports
            $netstatLines = netstat -ano | Select-String "LISTENING"
            
            foreach ($line in $netstatLines) {
                # Parse netstat line: Protocol LocalAddress ForeignAddress State PID
                $parts = $line.ToString().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
                if ($parts.Count -ge 4) {
                    $localAddr = $parts[1]
                    $currentPort = $localAddr.Split(':')[-1]
                    $processid = $parts[-1] # PID is usually the last element

                    # Resolve Process Name using tasklist
                    $taskInfo = tasklist /FI "PID eq $processid" /NH /FO CSV | ConvertFrom-Csv -Header "ProcessName", "PID", "SessionName", "Session#", "MemUsage"
                    $procName = if ($taskInfo) { $taskInfo.ProcessName } else { "Unknown" }

                    $results += [PSCustomObject]@{
                        Port        = $currentPort
                        PID         = $processid
                        ProcessName = $procName
                    }
                }
            }

            # Deduplicate (netstat often shows 0.0.0.0 and [::] for same port)
            $uniqueResults = $results | Group-Object Port | ForEach-Object { $_.Group[0] }

            $consoleOutput = "BEEP:440,50 Found $($uniqueResults.Count) active listeners."
            if ($uniqueResults.Count -gt 0) {
                # Use Draw-Box if available in the environment, otherwise fallback to simple formatting
                if (Get-Command Draw-Box -ErrorAction SilentlyContinue) {
                    $boxContent = $uniqueResults | Format-Table Port, PID, ProcessName | Out-String
                    Draw-Box -Title "Active Server Processes" -Content $boxContent -Color Cyan
                } else {
                    $consoleOutput += "`n" + ($uniqueResults | Format-Table Port, PID, ProcessName | Out-String)
                }
            }
            
            $aiData = $uniqueResults | ConvertTo-Json
        }
        elseif ($action -eq "kill") {
            if (-not $port) {
                return "CONSOLE::ERROR: Port parameter is required for 'kill' action.::END_CONSOLE::port_missing"
            }

            # Find the PID for the specific port
            $targetLine = netstat -ano | Select-String ":$port\s+.*LISTENING" | Select-Object -First 1
            
            if ($targetLine) {
                $parts = $targetLine.ToString().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
                $processid = $parts[-1]

                # Attempt to kill
                Stop-Process -Id $processid -Force -ErrorAction Stop
                $consoleOutput = "PLAY_SOUND:tada::Successfully terminated process on port $port (PID: $processid)."
                $aiData = @{ status = "success"; port = $port; pid = $processid; message = "Process terminated" } | ConvertTo-Json
            } else {
                $consoleOutput = "BEEP:200,200 No active process found listening on port $port."
                $aiData = @{ status = "not_found"; port = $port; message = "No process found" } | ConvertTo-Json
            }
        }
    }
    catch {
        $consoleOutput = "ERROR: $($_.Exception.Message)"
        $aiData = @{ status = "error"; error = $_.Exception.Message } | ConvertTo-Json
    }

    return "CONSOLE::$consoleOutput::END_CONSOLE::$aiData"
}

$ToolMeta = @{
    Name = "server_manager"
    Icon = "🌐"
    Version = "1.0.2"
    Author = "GemmaCLI Team"
    Description = "Lists processes listening on network ports or terminates a process by port number."
    Category = @("System", "Network", "Utilities")
    Keywords = @("port", "process", "kill", "netstat", "server")
    RendersToConsole = $true
    Interactive = $false
    RequiresBilling = $false
    RequiresKey = $false
    Relationships = @{"network_scanner" = "Tool for discovering devices on network. Use when the user asks 'what is running on my network' or 'network security check' or just to do a more complete diagnostic."}
    Behavior = "This tool uses native Windows commands (netstat, tasklist, taskkill) to manage network-bound processes. It is useful for debugging 'address already in use' errors or identifying which application is hosting a service."
    Parameters = @{
        action = @{
            Type = "string"
            Description = "The action to perform: 'list' (show all listening ports) or 'kill' (stop process on a port)."
            Required = $true
        }
        port = @{
            Type = "integer"
            Description = "The port number to target when using the 'kill' action."
            Required = $false
        }
    }
    Example = "<tool_call>server_manager(action='kill', port=8080)</tool_call>"
    FormatLabel = { 
        param($params) 
        "Server Manager ($($params.action)$(if($params.port){': ' + $params.port}))" 
    }
    Execute = { 
        param($params) 
        Invoke-ServerManagerTool @params 
    }
    ToolUseGuidanceMajor = "Use 'list' first to identify the correct PID before attempting to 'kill' a process to avoid accidental termination of critical services."
    ToolUseGuidanceMinor = "Note that 'list' resolves process names, which may take a few seconds if many ports are open."
}