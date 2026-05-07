# ===============================================
# GemmaCLI Tool - Network_Scanner.ps1 v1.2.0
# Responsibility: Probes local networks and returns an enriched intelligence brief.
# ===============================================

function Get-LocalNetworkCandidates {
    $candidates = @()
    $configs = Get-NetIPConfiguration | Where-Object {
        $_.NetAdapter.Status -eq 'Up' -and
        $_.InterfaceAlias -notmatch 'Loopback|Docker|WSL|VMware|VirtualBox|Hyper-V|vEthernet|Tailscale|ZeroTier|TAP|VPN'
    }

    foreach ($cfg in $configs) {
        $ipv4 = $cfg.IPv4Address
        if (-not $ipv4) { continue }

        $ip = $ipv4.IPAddress
        $prefix = [int]$ipv4.PrefixLength

        $ipBytes = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
        [Array]::Reverse($ipBytes)
        $ipInt = [BitConverter]::ToUInt32($ipBytes, 0)
        $maskInt = [uint32]::MaxValue -shl (32 - $prefix)
        $networkInt = $ipInt -band $maskInt
        $networkBytes = [BitConverter]::GetBytes([uint32]$networkInt)
        [Array]::Reverse($networkBytes)
        $networkIp = ([System.Net.IPAddress]::new($networkBytes)).IPAddressToString

        $gateway = ($cfg.IPv4DefaultGateway | Select-Object -First 1).NextHop

        $candidates += [PSCustomObject]@{
            CIDR      = "$networkIp/$prefix"
            IP        = $ip
            Interface = $cfg.InterfaceAlias
            Gateway   = $gateway
        }
    }
    return $candidates
}

function Get-DeviceInference {
    param(
        [string]$IP,
        [string]$MAC,
        [string]$Type,
        [int]$LastOctet
    )

    $oui = "Unknown"
    $category = "Unknown"
    $confidence = "Low"
    $reasoning = @()

    # Robust OUI extraction (handles both dashes and colons)
    if ($MAC -ne "Unknown" -and $MAC -match '^([0-9A-Fa-f]{2}[-:][0-9A-Fa-f]{2}[-:][0-9A-Fa-f]{2})') {
        $oui = ($Matches[1] -replace ':','-').ToUpper()
        $reasoning += "Hardware OUI detected: $oui (identifies manufacturer via IEEE registry)"
    }

    if ($Type -eq "Gateway") {
        $category = "Network Gateway / Router"
        $confidence = "High"
        $reasoning += "Standard gateway IP (.1); this is the internet-facing routing device"
    }
    elseif ($LastOctet -in 2,254) {
        $category = "Possible Secondary Gateway/Switch"
        $confidence = "Low"
        $reasoning += "Common alternate infrastructure address"
    }
    elseif ($LastOctet -ge 100 -and $LastOctet -le 199) {
        $category = "DHCP Client (Phone/Laptop/Tablet/Streaming Device)"
        $confidence = "Medium"
        $reasoning += "Falls within typical consumer/residential DHCP lease pool"
    }
    elseif ($LastOctet -ge 200 -and $LastOctet -le 240) {
        $category = "Static Assignment / IoT / Printer / Server"
        $confidence = "Medium"
        $reasoning += "Upper range often reserved for static leases, printers, NAS, or IoT hubs"
    }
    elseif ($LastOctet -ge 241 -and $LastOctet -le 254) {
        $category = "Infrastructure / Broadcast-Adjacent / Reserved"
        $confidence = "Low"
        $reasoning += "High-octet address; may be reserved for managed switches or access points"
    }
    elseif ($LastOctet -le 20) {
        $category = "Core Infrastructure / Server / Hypervisor"
        $confidence = "Medium"
        $reasoning += "Low-numbered IP typically reserved for servers, domain controllers, or hypervisors"
    }
    else {
        $category = "General Endpoint"
        $confidence = "Low"
        $reasoning += "Mid-range address without strong heuristic fingerprint"
    }

    return [PSCustomObject]@{
        IP               = $IP
        OUI              = $oui
        ProbableCategory = $category
        Confidence       = $confidence
        Reasoning        = $reasoning
    }
}

function Invoke-NetworkScannerTool {
    param (
        [string]$Subnet = "",
        [bool]$AutoDetect = $false,
        [bool]$Stealth = $false
    )

    $consoleOutput = New-Object System.Text.StringBuilder
    [void]$consoleOutput.AppendLine("CONSOLE::PLAY_SOUND:tada")

    # ── Auto-detect subnet if not provided ───────────────────────────────────
    if ([string]::IsNullOrWhiteSpace($Subnet) -or $AutoDetect) {
        $candidates = Get-LocalNetworkCandidates

        if ($candidates.Count -eq 0) {
            [void]$consoleOutput.AppendLine("ERROR: No active local network interfaces found. Are you connected to Wi-Fi or Ethernet?")
            [void]$consoleOutput.Append("::END_CONSOLE::")
            return "$($consoleOutput.ToString())Error: Network auto-detection failed."
        }

        if ($candidates.Count -gt 1) {
            [void]$consoleOutput.AppendLine("Multiple networks detected. Please specify one with the 'subnet' parameter:")
            foreach ($c in $candidates) {
                [void]$consoleOutput.AppendLine("  • $($c.CIDR)  [$($c.Interface)]  Gateway: $($c.Gateway)")
            }
            [void]$consoleOutput.Append("::END_CONSOLE::")
            return "$($consoleOutput.ToString())Error: Auto-detect found multiple subnets. Please specify subnet manually."
        }

        $Subnet = $candidates[0].CIDR
        [void]$consoleOutput.AppendLine("Auto-detected subnet: $Subnet [$($candidates[0].Interface)]")
    }

    # ── Parse CIDR ───────────────────────────────────────────────────────────
    $baseSubnet = ""
    $prefix = 24

    if ($Subnet -match "^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(\d{1,2})$") {
        $networkAddr = $Matches[1]
        $prefix = [int]$Matches[2]

        if ($prefix -ne 24) {
            [void]$consoleOutput.AppendLine("PLAY_SOUND:error ERROR: Only /24 subnets are currently supported for scanning. You provided /$prefix.")
            [void]$consoleOutput.Append("::END_CONSOLE::")
            return "$($consoleOutput.ToString())Error: Prefix /$prefix not supported."
        }

        $octets = $networkAddr -split '\.'
        if ([int]$octets[3] -ne 0) {
            [void]$consoleOutput.AppendLine("WARNING: $networkAddr does not look like a standard /24 network address (expected x.x.x.0).")
            [void]$consoleOutput.Append("::END_CONSOLE::")
            return "$($consoleOutput.ToString())Error: Invalid network address for /24."
        }
        $baseSubnet = "$($octets[0]).$($octets[1]).$($octets[2])"
    } else {
        [void]$consoleOutput.AppendLine("PLAY_SOUND:error ERROR: Invalid subnet format. Use CIDR notation (e.g., 192.168.1.0/24).")
        [void]$consoleOutput.Append("::END_CONSOLE::")
        return "$($consoleOutput.ToString())Error: Subnet '$Subnet' is invalid."
    }

    [void]$consoleOutput.AppendLine("Scanning $Subnet... (Stealth: $Stealth)")

    # ── Scan ─────────────────────────────────────────────────────────────────
    $results = @()
    $scanRange = 1..254
    if ($Stealth) { $scanRange = 1..50 }

    foreach ($i in $scanRange) {
        $ip = "$baseSubnet.$i"
        $ping = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue

        if ($ping) {
            $mac = "Unknown"
            $neighbor = Get-NetNeighbor -IPAddress $ip -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($neighbor) { $mac = $neighbor.LinkLayerAddress }

            $results += [PSCustomObject]@{
                IP       = $ip
                Status   = "Active"
                Hardware = $mac
                Type     = if ($i -eq 1) { "Gateway" } else { "Node" }
            }

            if (-not $Stealth) {
                [void]$consoleOutput.AppendLine("Found node at $ip")
            }
        }

        if ($Stealth) {
            Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 500)
        }
    }

    # ── Enrich data for AI reporting ─────────────────────────────────────────
    $enrichedNodes = foreach ($r in $results) {
        $lastOctet = [int]($r.IP -split '\.')[-1]
        $inference = Get-DeviceInference -IP $r.IP -MAC $r.Hardware -Type $r.Type -LastOctet $lastOctet
        [PSCustomObject]@{
            IP        = $r.IP
            Status    = $r.Status
            MAC       = $r.Hardware
            Type      = $r.Type
            Inference = $inference
        }
    }

    $uniqueMacs = ($results | Where-Object { $_.Hardware -ne "Unknown" } | Select-Object -ExpandProperty Hardware -Unique)
    $gatewayNode = $results | Where-Object { $_.Type -eq "Gateway" } | Select-Object -First 1

    $dhcpRangeCount = ($results | Where-Object { 
        $o = [int]($_.IP -split '\.')[-1]; $o -ge 100 -and $o -le 199 
    }).Count

    $staticRangeCount = ($results | Where-Object { 
        $o = [int]($_.IP -split '\.')[-1]; $o -ge 200 -and $o -le 254 
    }).Count

    $infraRangeCount = ($results | Where-Object { 
        $o = [int]($_.IP -split '\.')[-1]; $o -le 20 
    }).Count

    $macResolutionRate = if ($results.Count -gt 0) { 
        [math]::Round((($results | Where-Object { $_.Hardware -ne "Unknown" }).Count / $results.Count) * 100, 1) 
    } else { 0 }

    # Simple health score algorithm
    $healthScore = 40
    if ($gatewayNode) { $healthScore += 30 }
    if ($macResolutionRate -gt 50) { $healthScore += 15 }
    if ($results.Count -ge 2 -and $results.Count -le 40) { $healthScore += 15 }
    $healthScore = [math]::Min(100, $healthScore)

    $observations = @()
    if (-not $gatewayNode) { 
        $observations += "Gateway ($baseSubnet.1) did not respond to ICMP; it may have ping disabled, be under load, or reside on a separate management VLAN." 
    }
    if (($results | Where-Object { $_.Hardware -eq "Unknown" }).Count -gt 0) { 
        $observations += "Several active nodes lack visible MAC addresses in the ARP cache. This can indicate cross-subnet routing, VLAN segmentation, or ARP inspection/filtering." 
    }
    if ($Stealth) { 
        $observations += "Stealth mode was active. Scan range was truncated to .1-.50 with randomized delays; devices above .50 were not probed." 
    }
    if ($results.Count -eq 0) { 
        $observations += "Zero responsive nodes. Verify the subnet, check local firewall rules, or confirm physical connectivity." 
    }

    $report = @{
        scan_metadata = @{
            subnet_scanned        = $Subnet
            scan_mode             = if ($Stealth) { "Stealth (reduced range + jitter)" } else { "Full ICMP sweep" }
            total_ips_tested      = $scanRange.Count
            responsive_nodes      = $results.Count
            response_rate_percent = [math]::Round(($results.Count / $scanRange.Count) * 100, 2)
            scan_timestamp        = (Get-Date -Format "yyyy-MM-dd HH:mm:ss K")
        }
        gateway_analysis = @{
            ip           = if ($gatewayNode) { $gatewayNode.IP } else { "$baseSubnet.1" }
            status       = if ($gatewayNode) { "Online / Responsive" } else { "Offline / ICMP Filtered" }
            mac          = if ($gatewayNode) { $gatewayNode.Hardware } else { "N/A" }
            oui          = if ($gatewayNode -and $gatewayNode.Hardware -match '^([0-9A-Fa-f]{2}[-:][0-9A-Fa-f]{2}[-:][0-9A-Fa-f]{2})') { 
                ($Matches[1] -replace ':','-').ToUpper() 
            } else { "N/A" }
            significance = "The gateway is the default route to external networks. Its availability determines internet reachability for this subnet."
        }
        node_inventory = @($enrichedNodes)
        network_topology_inferences = @{
            estimated_dhcp_pool       = "$baseSubnet.100 - $baseSubnet.199"
            dhcp_pool_devices_found   = $dhcpRangeCount
            static_upper_range_devices= $staticRangeCount
            low_range_infrastructure  = $infraRangeCount
            total_unique_ouis         = $uniqueMacs.Count
            network_health_score      = $healthScore
            topology_guess            = if ($results.Count -eq 0) { "Empty / Filtered" } elseif ($results.Count -le 5) { "Minimal / Lab" } elseif ($results.Count -le 15) { "Small Office / Home Office" } else { "Active Multi-Device Network" }
        }
        security_and_observations = @{
            stealth_mode_engaged       = $Stealth
            mac_address_resolution_rate= $macResolutionRate
            unknown_mac_nodes          = ($results | Where-Object { $_.Hardware -eq "Unknown" }).Count
            notable_observations       = $observations
        }
        ai_narrative_guidance = @"
INSTRUCTIONS FOR THE AI ASSISTANT:
1. DO NOT repeat the console table to the user. They already see it rendered above.
2. Write a narrative "Network Reconnaissance Report" in prose.
3. For EACH active node, describe what it likely is based on its IP address, MAC/OUI signature, and the confidence-scored category inference provided.
4. Group devices into sections: "Infrastructure" (.1-.20), "DHCP Clients / Consumer Devices" (.100-.199), and "Static / IoT / Servers" (.200+).
5. Comment on overall network health using the provided score, MAC resolution rate, and any security observations.
6. If the gateway was unresponsive, treat that as a significant network or security configuration note.
7. Conclude with 1-2 actionable next steps (e.g., "Investigate the unknown device at .248," "Run a port scan on .160," or "Verify why the gateway is not responding to ICMP").
8. Maintain an analytical, concise tone.
"@
    }

    # ── Console output (exactly once) ────────────────────────────────────────
    if ($results.Count -gt 0) {
        [void]$consoleOutput.AppendLine("Scan complete. Found $($results.Count) active nodes on $Subnet.")
        [void]$consoleOutput.AppendLine(($results | Format-Table -AutoSize | Out-String))
    } else {
        [void]$consoleOutput.AppendLine("Scan complete. No active nodes found on $Subnet.")
    }
    [void]$consoleOutput.Append("::END_CONSOLE::")

    $aiPayload = $report | ConvertTo-Json -Depth 5

    return "$($consoleOutput.ToString())$aiPayload"
}

$ToolMeta = @{
    Name = "network_scanner"
    Icon = "📡"
    Description = "Scans a local subnet for active devices and retrieves hardware MAC addresses. Can auto-detect your local network if you don't know your CIDR."
    Keywords = @("network", "scan", "ip", "subnet", "hardware", "discovery")
    Category = @("Productivity", "Other")
    RendersToConsole = $true
    RequiresBilling = $false
    RequiresKey = $false
    Relationships = @{"server_manager" = "Tool for local host diagnostics. Use when the user asks 'what is running on my machine' or 'kill a local process' or just to do a more complete diagnostic. Note: It will NOT investigate remote nodes discovered by this scan."}
    Behavior = "Performs a sequential ICMP ping sweep. If no subnet is provided, it auto-detects the local network by inspecting active physical interfaces (ignoring VPN, Docker, WSL, and virtual adapters). In stealth mode, it adds jitter/delays and limits the range."
    Parameters = @{
        subnet = @{
            Type = "string"
            Description = "Target network in CIDR notation (e.g., 192.168.1.0/24). Omit this to auto-detect."
            Required = $false
        }
        autoDetect = @{
            Type = "boolean"
            Description = "Automatically detect the local subnet. Defaults to true if subnet is omitted."
            Required = $false
        }
        stealth = @{
            Type = "boolean"
            Description = "Enable high-stealth mode (randomized delays, reduced range)"
            Required = $false
        }
    }
    Example = "<tool_call>{ ""name"": ""network_scanner"", ""parameters"": { ""autoDetect"": true, ""stealth"": false } }</tool_call>"
    FormatLabel = {
        param($p)
        if ($p.subnet) { "Scanning: $($p.subnet) $(if($p.stealth){'(STEALTH)'})" }
        else { "Auto-detecting local network $(if($p.stealth){'(STEALTH)'})" }
    }
    Execute = {
        param($params)
        Invoke-NetworkScannerTool @params
    }
    ToolUseGuidanceMajor = "Use this tool when the user wants to discover devices on their local network. If the user does not provide a subnet, set autoDetect to true. Only /24 ranges are currently optimized. After execution, the AI MUST NOT repeat the console table. Instead, synthesize a narrative Network Reconnaissance Report describing each node's likely identity, grouping by IP ranges, and commenting on topology and security."
    ToolUseGuidanceMinor = "If no subnet is given, the tool will find the active local network automatically. It filters out virtual adapters (Docker, WSL, VPN). The returned payload contains rich inference data including OUI extraction, device category guessing, and network health scoring. Use this data to write an analytical prose report, not a raw data dump."
}