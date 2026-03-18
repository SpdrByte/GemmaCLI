# ===============================================
# GemmaCLI Tool - background_check.ps1 v0.3.1
# Responsibility: Comprehensive background screening tool.
#                 Sources: Registry, State Courts, FBI Wanted.
#                 Built on working v2.3.0 PSCustomObject foundation.
#                 Full unified card schema, all fields, Draw-Box wrapping.
# Depends on: none
# ===============================================

# ====================== HELPERS ======================

function Wrap-Line {
    param([string]$text, [int]$maxWidth, [string]$continuationPrefix = "  ")
    if ([string]::IsNullOrWhiteSpace($text)) { return @("") }
    if ($text.Length -le $maxWidth) { return @($text) }
    $wrapped = @()
    $remaining = $text
    $first = $true
    while ($remaining.Length -gt 0) {
        $width = $maxWidth
        if (-not $first) { $width = $maxWidth - $continuationPrefix.Length }
        if ($remaining.Length -le $width) {
            if ($first) { $wrapped += $remaining } else { $wrapped += ($continuationPrefix + $remaining) }
            break
        }
        $slice = $remaining.Substring(0, $width)
        $breakAt = $slice.LastIndexOf(' ')
        if ($breakAt -le 0) { $breakAt = $width }
        $line = $remaining.Substring(0, $breakAt).TrimEnd()
        $remaining = $remaining.Substring($breakAt).TrimStart()
        if ($first) { $wrapped += $line } else { $wrapped += ($continuationPrefix + $line) }
        $first = $false
    }
    return $wrapped
}

function Draw-Box {
    param(
        [string[]]$Lines,
        [string]$Title = "",
        [string]$Color = "Cyan",
        [int]$MaxWidth = 110
    )
    if ($null -eq $Lines -or $Lines.Count -eq 0) { return }
    $TL = [string][char]0x256D; $TR = [string][char]0x256E
    $BL = [string][char]0x2570; $BR = [string][char]0x256F
    $H  = [string][char]0x2500; $V  = [string][char]0x2502

    $wrapped = @()
    foreach ($l in $Lines) {
        if ($null -eq $l) { continue }
        $res = Wrap-Line -text $l.ToString() -maxWidth $MaxWidth
        foreach ($wl in $res) { $wrapped += $wl }
    }

    $innerW = 2
    foreach ($l in $wrapped) { if ($l.Length -gt $innerW) { $innerW = $l.Length } }
    $titleText = ""
    if ($Title) { $titleText = " $Title " }
    if ($titleText.Length -gt $innerW) { $innerW = $titleText.Length }
    if ($innerW -gt $MaxWidth) { $innerW = $MaxWidth }

    $titleFill = ($innerW + 2) - $titleText.Length
    $fillL = [Math]::Floor($titleFill / 2)
    $fillR = $titleFill - $fillL
    if ($fillR -lt 0) { $fillR = 0 }

    $top = $TL + ($H * $fillL) + $titleText + ($H * $fillR) + $TR

    Write-Host ""
    Write-Host ("  " + $top) -ForegroundColor $Color
    foreach ($l in $wrapped) {
        Write-Host ("  " + $V + " " + $l.PadRight($innerW) + " " + $V) -ForegroundColor $Color
    }
    Write-Host ("  " + $BL + ($H * ($innerW + 2)) + $BR) -ForegroundColor $Color
}

function Format-Date {
    param($d)
    $s = Val $d ""
    if ($s -eq "" -or $s -eq "N/A") { return "N/A" }
    if ($s -match '[a-zA-Z]') { return $s }
    $clean = $s -replace "[^0-9]", ""
    if ($clean.Length -ge 8) { return "$($clean.Substring(4,2))/$($clean.Substring(6,2))/$($clean.Substring(0,4))" }
    return $s
}

function Val {
    param($v, [string]$fallback = "N/A")
    if ($null -eq $v) { return $fallback }
    $s = $v.ToString()
    if ([string]::IsNullOrWhiteSpace($s)) { return $fallback }
    return $s
}

function Truncate-Url {
    param($url, [int]$len = 80)
    $s = Val $url ""
    if ($s -eq "" -or $s -eq "N/A" -or $s -eq "None") { return "None" }
    if ($s.Length -le $len) { return $s }
    return $s.Substring(0, $len) + "..."
}

function Strip-Html {
    param($text)
    $s = Val $text ""
    if ($s -eq "") { return "" }
    $clean = $s -replace '<[^>]+>', ' ' -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&nbsp;', ' ' -replace '&quot;', '"' -replace 'Â', ''
    $clean = $clean.Trim()
    while ($clean -match '  ') { $clean = $clean -replace '  ', ' ' }
    return $clean
}

# ====================== DATA ACCESS HELPERS ======================
# Use PSCustomObject dot-property access — reliable in all PS contexts including Start-Job

function Get-P {
    param($obj, $prop, $fallback = "N/A")
    if ($null -eq $obj) { return $fallback }
    try {
        $val = $obj.$prop
        if ($null -eq $val) { return $fallback }
        if ($val -is [Array] -or $val -is [System.Collections.IDictionary]) { return $fallback }
        $s = $val.ToString()
        if ([string]::IsNullOrWhiteSpace($s)) { return $fallback }
        return $s
    } catch { return $fallback }
}

function Get-A {
    param($obj, $prop)
    if ($null -eq $obj) { return @() }
    try {
        $val = $obj.$prop
        if ($null -eq $val) { return @() }
        return @($val)
    } catch { return @() }
}

# ====================== UNIFIED CARD BUILDER ======================
# $raw is always a PSCustomObject. Get-P/Get-A use dot-property access.

function New-UnifiedCard {
    param($raw)

    $BUL = [string][char]0x2022

    $risk = (Get-P $raw "Risk" "N/A").ToUpper()
    $src  = Get-P $raw "Source" ""

    $color = "Cyan"
    if ($risk -match "HIGH|TERROR|MURDER") { $color = "Red" }
    elseif ($src -match "FBI|Registry" -or $risk -match "MEDIUM|FUGITIVE|DEFAULT") { $color = "Yellow" }
    elseif ($risk -match "LOW") { $color = "Green" }

    # Crimes
    $crimeLines = @()
    $crimes = Get-A $raw "Crimes"
    if ($crimes.Count -gt 0) {
        foreach ($c in $crimes) {
            $desc = Get-P $c "Description" ""
            if ($desc -eq "") { $desc = Get-P $c "Charge" "Unknown charge" }
            $crimeLines += "  $BUL $desc"
            $v = Get-P $c "CaseNo"       ""; if ($v -ne "") { $crimeLines += "     Case#: $v" }
            $v = Get-P $c "Role"         ""; if ($v -ne "") { $crimeLines += "     Role: $v" }
            $v = Get-P $c "CaseCaption"  ""; if ($v -ne "") { $crimeLines += "     Case: $v" }
            $v = Get-P $c "CaseType"     ""; if ($v -ne "") { $crimeLines += "     Type: $v" }
            $v = Get-P $c "FiledDate"    ""; if ($v -ne "") { $crimeLines += "     Filed: $(Format-Date $v)" }
            $v = Get-P $c "Disposition"  ""; if ($v -ne "") { $crimeLines += "     Disposition: $v" }
            $v = Get-P $c "ConvictionDate" ""; if ($v -ne "") { $crimeLines += "     Convicted: $(Format-Date $v)" }
            $v = Get-P $c "ConvictionState" ""; if ($v -ne "") { $crimeLines += "     Conv. State: $v" }
            $v = Get-P $c "CrimeCity"   ""; if ($v -ne "") { $crimeLines += "     City: $v" }
            $v = Get-P $c "VictimSex"   ""; if ($v -ne "") { $crimeLines += "     Victim Sex: $v" }
            $v = Get-P $c "Subjects"    ""; if ($v -ne "") { $crimeLines += "     Subjects: $v" }
            $v = Get-P $c "Classification" ""; if ($v -ne "") { $crimeLines += "     Classification: $v" }
            $v = Get-P $c "Caution"     ""; if ($v -ne "") { $crimeLines += "     Caution: $v" }
            $v = Get-P $c "Warning"     ""; if ($v -ne "") { $crimeLines += "     Warning: $v" }
            $v = Get-P $c "Remarks"     ""; if ($v -ne "") { $crimeLines += "     Remarks: $v" }
            $v = Get-P $c "AddlInfo"    ""; if ($v -ne "") { $crimeLines += "     Info: $v" }
        }
    } else { $crimeLines = @("  None on record") }

    # Marks
    $tatLines = @()
    $tats = Get-A $raw "Marks"
    foreach ($t in $tats) { $s = Val $t ""; if ($s -ne "") { $tatLines += "  $BUL $s" } }
    if ($tatLines.Count -eq 0) { $tatLines = @("  None on record") }

    # Vehicles
    $vecLines = @()
    $vecs = Get-A $raw "Vehicles"
    foreach ($v in $vecs) { $s = Val $v ""; if ($s -ne "") { $vecLines += "  $BUL $s" } }
    if ($vecLines.Count -eq 0) { $vecLines = @("  None on record") }

    # Photos
    $imgLines = @()
    $imgs = Get-A $raw "Photos"
    foreach ($img in $imgs) { $s = Val $img ""; if ($s -ne "") { $imgLines += "  $BUL $(Truncate-Url $s)" } }
    if ($imgLines.Count -eq 0) { $imgLines = @("  None on record") }

    return [PSCustomObject]@{
        Source      = $src
        FullName    = Get-P $raw "FullName"
        FirstName   = Get-P $raw "FirstName"
        MiddleName  = Get-P $raw "MiddleName"
        LastName    = Get-P $raw "LastName"
        Suffix      = Get-P $raw "Suffix"
        Aliases     = Get-P $raw "Aliases"
        DOB         = Get-P $raw "DOB"
        Age         = Get-P $raw "Age"
        Sex         = Get-P $raw "Sex"
        Ethnicity   = Get-P $raw "Ethnicity"
        BirthPlace  = Get-P $raw "BirthPlace"
        Height      = Get-P $raw "Height"
        Weight      = Get-P $raw "Weight"
        EyeColor    = Get-P $raw "EyeColor"
        HairColor   = Get-P $raw "HairColor"
        Skin        = Get-P $raw "Skin"
        Phone       = Get-P $raw "Phone"
        Email       = Get-P $raw "Email"
        Address     = Get-P $raw "Address"
        Address2    = Get-P $raw "Address2"
        AddressType = Get-P $raw "AddressType"
        City        = Get-P $raw "City"
        State       = Get-P $raw "State"
        Zip         = Get-P $raw "Zip"
        County      = Get-P $raw "County"
        AddressDate = Get-P $raw "AddressDate"
        PrevAddress = Get-P $raw "PrevAddress"
        Employer    = Get-P $raw "Employer"
        WorkAddress = Get-P $raw "WorkAddress"
        WorkCity    = Get-P $raw "WorkCity"
        WorkState   = Get-P $raw "WorkState"
        WorkZip     = Get-P $raw "WorkZip"
        WorkCounty  = Get-P $raw "WorkCounty"
        Status      = Get-P $raw "Status"
        Risk        = $risk
        Registered  = Get-P $raw "Registered"
        Released    = Get-P $raw "Released"
        VictimMinor = Get-P $raw "VictimMinor"
        VictimSex   = Get-P $raw "VictimSex"
        SourceId    = Get-P $raw "SourceId"
        ProfileUrl  = Get-P $raw "ProfileUrl"
        Reward      = Get-P $raw "Reward"
        FieldOffice = Get-P $raw "FieldOffice"
        Nationality = Get-P $raw "Nationality"
        Languages   = Get-P $raw "Languages"
        Countries   = Get-P $raw "Countries"
        Build       = Get-P $raw "Build"
        CrimeLines  = $crimeLines
        TatLines    = $tatLines
        VecLines    = $vecLines
        ImgLines    = $imgLines
        Color       = $color
    }
}

# ====================== CARD RENDERER ======================

function Render-Card {
    param($r, [int]$idx, [int]$total)

    $box = @(
        "SOURCE:       $($r.Source)",
        "─────────────────────────────── IDENTITY ───────────────────────────────",
        "Full Name:    $($r.FullName)",
        "First:        $($r.FirstName)   Middle: $($r.MiddleName)   Last: $($r.LastName)   Suffix: $($r.Suffix)",
        "Aliases:      $($r.Aliases)",
        "DOB:          $(Format-Date $r.DOB)   Age: $($r.Age)",
        "Sex:          $($r.Sex)   Ethnicity: $($r.Ethnicity)   Birth Place: $($r.BirthPlace)"
    )
    if ($r.Nationality -ne "N/A") { $box += "Nationality:  $($r.Nationality)   Languages: $($r.Languages)" }
    if ($r.Countries   -ne "N/A") { $box += "Poss. Countries: $($r.Countries)" }

    $box += "─────────────────────────────── PHYSICAL ───────────────────────────────"
    $box += "Height:       $($r.Height)   Weight: $($r.Weight)"
    if ($r.Build -ne "N/A") { $box += "Build:        $($r.Build)" }
    $box += "Eyes:         $($r.EyeColor)   Hair: $($r.HairColor)   Skin: $($r.Skin)"

    $box += @(
        "─────────────────────────────── CONTACT ────────────────────────────────",
        "Phone:        $($r.Phone)   Email: $($r.Email)",
        "──────────────────────────── RESIDENCE ─────────────────────────────────",
        "Address:      $($r.Address)   ($($r.AddressType))",
        "Address 2:    $($r.Address2)",
        "City:         $($r.City)   State: $($r.State)   ZIP: $($r.Zip)",
        "County:       $($r.County)   Address Since: $(Format-Date $r.AddressDate)",
        "Prev Address: $($r.PrevAddress)",
        "──────────────────────────── EMPLOYMENT ────────────────────────────────",
        "Employer:     $($r.Employer)",
        "Work:         $($r.WorkAddress)   $($r.WorkCity), $($r.WorkState) $($r.WorkZip)",
        "Work County:  $($r.WorkCounty)",
        "──────────────────────────── REGISTRY STATUS ───────────────────────────",
        "Status:       $($r.Status)   Risk/Class: $($r.Risk)",
        "Registered:   $(Format-Date $r.Registered)   Released: $(Format-Date $r.Released)",
        "Victim Minor: $($r.VictimMinor)   Victim Sex: $($r.VictimSex)",
        "Source ID:    $($r.SourceId)",
        "Profile:      $($r.ProfileUrl)"
    )

    if ($r.Reward -ne "N/A") {
        $box += "──────────────────────────────── REWARD ────────────────────────────────"
        $box += "Reward:       $($r.Reward)   Field Office: $($r.FieldOffice)"
    }

    $box += "─────────────────────────────── CRIMES ─────────────────────────────────"
    foreach ($cl in $r.CrimeLines) { $box += $cl }
    $box += "──────────────────────────── MARKS / TATTOOS ───────────────────────────"
    foreach ($tl in $r.TatLines) { $box += $tl }
    $box += "─────────────────────────────── VEHICLES ───────────────────────────────"
    foreach ($vl in $r.VecLines) { $box += $vl }
    $box += "──────────────────────────────── PHOTOS ────────────────────────────────"
    foreach ($il in $r.ImgLines) { $box += $il }

    Draw-Box -Lines $box -Title "Record $idx of $total" -Color $r.Color
}

# ====================== CORE SEARCH LOGIC ======================

function Invoke-BackgroundCheck {
    param(
        [string]$firstName,
        [string]$lastName,
        [string]$state       = "",
        [string]$dob         = "",
        [int]$maxResults     = 3,
        [int]$offset         = 0,
        [bool]$debug         = $false,
        [string]$action      = "full"
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $BUL = [string][char]0x2022

    if ([string]::IsNullOrWhiteSpace($firstName) -or [string]::IsNullOrWhiteSpace($lastName)) {
        return "ERROR: firstName and lastName are required."
    }

    $results  = @()
    $debugLog = @{}

    # ---- SOURCE 1: SEX OFFENDER REGISTRY ----
    if ($action -match "full|registry") {
        if ($state) {
            $regKey = "OvrH3Z51jo5jEu83tDvg24e19sLPCBkF9v4FFVHK"
            $regUrl = "https://sexoffenders.api.intsurfing.com/sex-offenders/offenders?state=$state&firstName=$firstName&lastName=$lastName"
            if ($dob) { $regUrl += "&dob=$dob" }
            try {
                $resp = Invoke-RestMethod -Uri $regUrl -Method GET -Headers @{"x-api-key"=$regKey} -ErrorAction Stop
                $debugLog["registry_raw"] = $resp
                $items = @()
                if ($resp.Offenders) { $items = @($resp.Offenders) }
                elseif ($resp.offenders) { $items = @($resp.offenders) }
                elseif ($resp -is [Array]) { $items = $resp }

                foreach ($i in $items) {
                    $fn = $i.Fullname; if (-not $fn) { $fn = $i.FullName }; if (-not $fn) { $fn = "$($i.Firstname) $($i.Lastname)".Trim() }
                    $bd = $i.BirthDate; if (-not $bd) { $bd = $i.Birthdate }; if (-not $bd) { $bd = $i.DOB }
                    $wt = Val $i.Weight ""; if ($wt -ne "" -and $wt -notmatch "lbs") { $wt = "$wt lbs" }
                    $aliasArr = @(); if ($i.Aliases) { $aliasArr = @($i.Aliases) }
                    $aliases = if ($aliasArr.Count -gt 0) { $aliasArr -join ", " } else { "None" }
                    $vecs = @(); if ($i.Vehicles) { foreach($v in @($i.Vehicles)) { $vecs += "$(Val $v.Make) $(Val $v.Model) $(Val $v.Year) ($(Val $v.LicensePlate))".Trim() } }
                    $photos = @(); if ($i.Photos) { $photos = @($i.Photos) } elseif ($i.ImageUrl) { $photos = @($i.ImageUrl) }
                    $crimeObjs = @(); if ($i.Crimes) { $crimeObjs = @($i.Crimes) } elseif ($i.Offenses) { $crimeObjs = @($i.Offenses) }
                    $crimes = @()
                    foreach ($c in $crimeObjs) {
                        $desc = $c.Description; if (-not $desc) { $desc = $c.Charge }
                        $crimes += [PSCustomObject]@{
                            Description     = $desc
                            CaseNo          = $c.CaseNo
                            ConvictionDate  = $c.ConvictionDate
                            ConvictionState = $c.ConvictionState
                            CrimeCity       = $c.CrimeCity
                            VictimSex       = $c.VictimSex
                        }
                    }
                    $marks = @(); if ($i.Marks) { $marks = @($i.Marks) } elseif ($i.Tattoos) { $marks = @($i.Tattoos) }

                    $data = [PSCustomObject]@{
                        Source      = "National Sex Offender Registry"
                        FullName    = $fn
                        FirstName   = Val $i.Firstname
                        MiddleName  = Val $i.Middlename
                        LastName    = Val $i.Lastname
                        Suffix      = Val $i.NameSuffix
                        Aliases     = $aliases
                        DOB         = $bd
                        Age         = $i.Age
                        Sex         = $i.Sex
                        Ethnicity   = if ($i.Ethnicity) { $i.Ethnicity } else { $i.Race }
                        BirthPlace  = $i.BirthPlace
                        Height      = $i.Height
                        Weight      = $wt
                        EyeColor    = $i.EyeColor
                        HairColor   = $i.HairColor
                        Skin        = $i.Skin
                        Phone       = $i.Phone
                        Email       = $i.Email
                        Address     = $i.Address
                        Address2    = $i.Address2
                        AddressType = $i.AddressType
                        City        = $i.City
                        State       = $i.State
                        Zip         = $i.Zip
                        County      = $i.CountyName
                        AddressDate = $i.AddressDate
                        PrevAddress = $i.PrevAddress
                        Employer    = $i.Employer
                        WorkAddress = $i.WorkAddress
                        WorkCity    = $i.WorkCity
                        WorkState   = $i.WorkState
                        WorkZip     = $i.WorkZip
                        WorkCounty  = $i.WorkCountyName
                        Status      = $i.Status
                        Risk        = $i.Risk
                        Registered  = $i.Registered
                        Released    = $i.ReleaseDate
                        VictimMinor = $i.VictimMinor
                        VictimSex   = $i.VictimSex
                        SourceId    = $i.SourceId
                        ProfileUrl  = $i.OffenderLink
                        Crimes      = $crimes
                        Marks       = $marks
                        Vehicles    = $vecs
                        Photos      = $photos
                    }
                    $results += New-UnifiedCard -raw $data
                }
            } catch { $debugLog["registry_error"] = $_.Exception.Message }
        }
    }

    # ---- SOURCE 2: STATE COURTS ----
    if ($action -match "full|court") {
        $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("demo:demo"))
        $url  = "https://demo-api.doxpop.com/actors_cases.json?fullname=$lastName,+$firstName"
        try {
            $resp = Invoke-RestMethod -Uri $url -Method GET -Headers @{"Authorization"="Basic $auth"} -ErrorAction Stop
            $debugLog["courts_raw"] = $resp
            $items = @()
            try {
                $valProp = $resp | Select-Object -ExpandProperty value -ErrorAction Stop
                if ($valProp) { $items = @($valProp) }
            } catch { }
            if ($items.Count -eq 0) {
                if ($resp -is [Array]) { $items = $resp } else { $items = @($resp) }
            }

            foreach ($i in $items) {
                if (-not $i.case) { continue }
                $a = $i.actor; $c = $i.case
                $addrObj = $null
                if ($a.addresses -and @($a.addresses).Count -gt 0) { $addrObj = $a.addresses[0] }

                $crime = [PSCustomObject]@{
                    Description = $c.case_caption
                    CaseNo      = $c.case_number
                    Role        = $i.assigned_case_role
                    CaseType    = $c.case_local_type_code
                    FiledDate   = $c.case_filed_date
                    Disposition = $c.case_global_disposition_code
                }
                $marks = @(); if ($a.actor_person_scars_marks_tattoos) { $marks = @($a.actor_person_scars_marks_tattoos) }

                $data = [PSCustomObject]@{
                    Source      = "State Courts"
                    FullName    = $a.actor_full_name
                    FirstName   = $a.actor_person_first_name
                    MiddleName  = $a.actor_person_middle_name
                    LastName    = $a.actor_person_last_name
                    DOB         = $a.actor_person_date_of_birth
                    Sex         = $a.actor_person_gender_code
                    Ethnicity   = $a.actor_person_ethnicity
                    Height      = if ($a.actor_person_height) { "$($a.actor_person_height) in" } else { $null }
                    Weight      = if ($a.actor_person_weight) { "$($a.actor_person_weight) lbs" } else { $null }
                    EyeColor    = $a.actor_person_eye_color
                    HairColor   = $a.actor_person_hair_color
                    Address     = if ($addrObj) { $addrObj.address_line1 } else { $null }
                    Address2    = if ($addrObj) { $addrObj.address_line2 } else { $null }
                    City        = if ($addrObj) { $addrObj.address_city } else { $null }
                    State       = if ($addrObj) { $addrObj.address_state_province_code } else { "Indiana" }
                    Zip         = if ($addrObj) { $addrObj.address_postal_code } else { $null }
                    Status      = $c.case_global_disposition_code
                    SourceId    = $c.case_number
                    Crimes      = @($crime)
                    Marks       = $marks
                }
                $results += New-UnifiedCard -raw $data
            }
        } catch { $debugLog["courts_error"] = $_.Exception.Message }
    }

    # ---- SOURCE 3: FBI WANTED ----
    if ($action -match "full|fbi_wanted") {
        $url = "https://api.fbi.gov/wanted/v1/list?title=$firstName+$lastName&pageSize=10"
        try {
            $resp = Invoke-RestMethod -Uri $url -Method GET -ErrorAction Stop
            $debugLog["fbi_raw"] = $resp
            if ($resp.items) {
                foreach ($w in @($resp.items)) {
                    $fbiDob = "N/A"; if ($w.dates_of_birth_used -and @($w.dates_of_birth_used).Count -gt 0) { $fbiDob = $w.dates_of_birth_used[0] }
                    $fbiStates = "N/A"; if ($w.possible_states -and @($w.possible_states).Count -gt 0) { $fbiStates = @($w.possible_states) -join ", " }
                    $fbiCountries = "N/A"; if ($w.possible_countries -and @($w.possible_countries).Count -gt 0) { $fbiCountries = @($w.possible_countries) -join ", " }
                    $fbiLangs = "N/A"; if ($w.languages -and @($w.languages).Count -gt 0) { $fbiLangs = @($w.languages) -join ", " }
                    $fbiAliases = "None"; if ($w.aliases -and @($w.aliases).Count -gt 0) { $fbiAliases = @($w.aliases) -join ", " }
                    $fbiSubjects = ""; if ($w.subjects -and @($w.subjects).Count -gt 0) { $fbiSubjects = @($w.subjects) -join ", " }
                    $fbiFieldOff = "N/A"; if ($w.field_offices -and @($w.field_offices).Count -gt 0) { $fbiFieldOff = (@($w.field_offices) -join ", ").ToUpper() }
                    $fbiReward = "N/A"; if ($w.reward_max -and $w.reward_max -gt 0) { $fbiReward = "$($w.reward_max.ToString('N0'))" }
                    $fbiHMin = $w.height_min; $fbiHMax = $w.height_max
                    $fbiHeight = "N/A"; if ($fbiHMin) { if ($fbiHMax -and $fbiHMax -ne $fbiHMin) { $fbiHeight = "$fbiHMin - $fbiHMax in" } else { $fbiHeight = "$fbiHMin in" } }
                    $fbiWMin = $w.weight_min; $fbiWMax = $w.weight_max
                    $fbiWeight = "N/A"; if ($fbiWMin) { if ($fbiWMax -and $fbiWMax -ne $fbiWMin) { $fbiWeight = "$fbiWMin - $fbiWMax lbs" } else { $fbiWeight = "$fbiWMin lbs" } }
                    $fbiAge = "N/A"; if ($w.age_min -and $w.age_max) { $fbiAge = "$($w.age_min) - $($w.age_max)" } elseif ($w.age_min) { $fbiAge = "$($w.age_min)" }
                    $fbiPhotos = @(); if ($w.images) { foreach ($img in @($w.images)) { if ($img.large) { $fbiPhotos += $img.large } elseif ($img.original) { $fbiPhotos += $img.original } elseif ($img.thumb) { $fbiPhotos += $img.thumb } } }
                    $fbiMarks = @(); if ($w.scars_and_marks) { $fbiMarks = @($w.scars_and_marks) }

                    $crime = [PSCustomObject]@{
                        Description    = Strip-Html $w.description
                        Subjects       = $fbiSubjects
                        Classification = $w.poster_classification
                        Caution        = Strip-Html $w.caution
                        Warning        = Strip-Html $w.warning_message
                        Remarks        = Strip-Html $w.remarks
                        AddlInfo       = Strip-Html $w.additional_information
                    }

                    $data = [PSCustomObject]@{
                        Source      = "FBI Wanted"
                        FullName    = Strip-Html $w.title
                        Aliases     = $fbiAliases
                        DOB         = $fbiDob
                        Age         = $fbiAge
                        Sex         = $w.sex
                        Ethnicity   = $w.race
                        Height      = $fbiHeight
                        Weight      = $fbiWeight
                        EyeColor    = $w.eyes
                        HairColor   = $w.hair
                        Build       = $w.build
                        State       = $fbiStates
                        Countries   = $fbiCountries
                        Languages   = $fbiLangs
                        Nationality = $w.nationality
                        Status      = $w.status
                        Risk        = $w.poster_classification
                        Registered  = $w.publication
                        SourceId    = $w.uid
                        ProfileUrl  = $w.url
                        Reward      = $fbiReward
                        FieldOffice = $fbiFieldOff
                        Crimes      = @($crime)
                        Marks       = $fbiMarks
                        Photos      = $fbiPhotos
                    }
                    $results += New-UnifiedCard -raw $data
                }
            }
        } catch { $debugLog["fbi_error"] = $_.Exception.Message }
    }

    # ---- RENDER ----
    if ($results.Count -eq 0) {
        Draw-Box -Lines @("No records found.", "", "  Query: $firstName $lastName", "  State: $state") -Title "Search: No Results" -Color Red
        if ($debug) { $dbgStr = $debugLog | ConvertTo-Json -Depth 15; if ($dbgStr.Length -gt 2000) { $dbgStr = $dbgStr.Substring(0, 2000) + "`n... [truncated]" }; Write-Host $dbgStr -ForegroundColor DarkGray }
        $noRes = @{ ok=$true; count=0 }
        return "CONSOLE::No results.::END_CONSOLE::$($noRes | ConvertTo-Json -Depth 5)"
    }

    $toShow = @($results | Select-Object -Skip $offset -First $maxResults)
    $idx = $offset
    foreach ($r in $toShow) {
        $idx++
        Render-Card -r $r -idx $idx -total $results.Count
    }

    $sum = @(
        "Search complete",
        "",
        "  Sources:  Sex Offender Registry, State Courts, FBI Wanted",
        "  Total:    $($results.Count) record(s)",
        "  Shown:    $($offset + 1) to $($offset + $toShow.Count)"
    )
    if ($results.Count -gt ($offset + $maxResults)) {
        $next = $offset + $maxResults
        $sum += ""
        $sum += "  NOTE: More results available. Call with offset=$next"
    }
    Draw-Box -Lines $sum -Title "Background Check Summary" -Color Green

    if ($debug) { $dbgStr = $debugLog | ConvertTo-Json -Depth 15; if ($dbgStr.Length -gt 2000) { $dbgStr = $dbgStr.Substring(0, 2000) + "`n... [truncated]" }; Write-Host $dbgStr -ForegroundColor DarkGray }
    $sourceCounts = @{}
    foreach ($r in $results) {
        $src = $r.Source
        if (-not $sourceCounts.ContainsKey($src)) { $sourceCounts[$src] = 0 }
        $sourceCounts[$src]++
    }
    $final = @{ ok=$true; count=$results.Count; displayed=$toShow.Count; sources=$sourceCounts; results=$results }
    return "CONSOLE::Search complete.::END_CONSOLE::$($final | ConvertTo-Json -Depth 5)"
}

# ====================== TOOL REGISTRATION ======================

$ToolMeta = @{
    Name             = "background_check"
    RendersToConsole = $true
    Category    = @("Search and Discover")
    Behavior         = "Unified background check tool. Searches Sex Offender Registry, State Courts, and FBI Wanted simultaneously. Call ONLY after gathering firstName, lastName, and ideally state and DOB from the user."
    Description      = "Comprehensive background check across three public record sources: National Sex Offender Registry, Indiana State/Federal Courts, and FBI Wanted database."
    Parameters       = @{
        firstName  = "string (required)"
        lastName   = "string (required)"
        state      = "string (optional but recommended) - two-letter code e.g. FL"
        dob        = "string (optional) - yyyymmdd"
        offset     = "int (optional) - pagination start, default 0"
        maxResults = "int (optional) - records per page, default 3"
        action     = "string (optional) - full (default), registry, court, fbi_wanted"
        debug      = "bool (optional) - include raw API data in JSON output"
    }
    Example          = @"
<tool_call>{ "name": "background_check", "parameters": { "firstName": "John", "lastName": "Smith", "state": "TX", "dob": "19800101" } }</tool_call>
<tool_call>{ "name": "background_check", "parameters": { "firstName": "John", "lastName": "Smith", "state": "TX", "offset": 3, "maxResults": 3 } }</tool_call>
<tool_call>{ "name": "background_check", "parameters": { "firstName": "John", "lastName": "Smith", "action": "fbi_wanted" } }</tool_call>
"@
    FormatLabel      = { param($p)
        $off = if ($p.offset) { " [offset:$($p.offset)]" } else { "" }
        $src = if ($p.action -and $p.action -ne "full") { " [$($p.action)]" } else { "" }
        "background_check  $([string][char]0x2192)  $($p.firstName) $($p.lastName)$src$off"
    }
    Execute          = {
        param($params)
        $fName = $params.firstName
        $lName = $params.lastName
        $st = ""; if ($params.state)  { $st  = $params.state }
        $db = ""; if ($params.dob)    { $db  = $params.dob }
        $off = 0; if ($params.offset) { $off = [int]$params.offset }
        $max = 3; if ($params.maxResults) { $max = [int]$params.maxResults }
        $dbg = $false; if ($params.debug -eq "true" -or $params.debug -eq $true) { $dbg = $true }
        $act = "full"; if ($params.action) { $act = $params.action }

        Invoke-BackgroundCheck `
            -firstName  $fName `
            -lastName   $lName `
            -state      $st `
            -dob        $db `
            -offset     $off `
            -maxResults $max `
            -debug      $dbg `
            -action     $act
    }
    ToolUseGuidanceMajor = @"
- FLOW: Ask for firstName, lastName, state, and DOB before calling. State is required for registry search.
- TRIPLE SEARCH: Searches Sex Offender Registry, State/Federal Courts, AND FBI Wanted in one call.
- SPELLING RETRY: If ALL sources return 0 results, attempt alternate spellings before giving up:
    1. Try common first name alternates (Jon/John, Mike/Michael, Chris/Christopher, etc.)
    2. Try common last name alternates (Anderson/Andersen, Smith/Smyth, Johnson/Johnston, etc.)
    3. Try phonetic variations
    4. Make a separate tool call per variation
    5. Only report no results after exhausting at least 2-3 spelling variations
    6. Tell the user which spellings were tried
- PAGINATION: Use offset/maxResults only when user asks to see more results.
- RESPONSE GUIDANCE: All details are in boxes. Do NOT reprint them. Summarise findings briefly.
- FBI WANTED HITS: Explicitly flag to the user when a result comes from FBI Wanted.
"@
}