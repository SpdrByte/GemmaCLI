# ===============================================
# GemmaCLI Tool - bible.ps1 v1.0.3
# Responsibility: AI-driven Bible lookup, topic search,
#                 translation comparison, cross-references,
#                 and commentary via bible.helloao.org
# ===============================================

# ── Constants ───────────────────────────────────────────────────────────────

$script:BIBLE_API = "https://bible.helloao.org/api"

# Book name → API ID map (covers all 66 canonical books + common abbreviations)
$script:BOOK_IDS = @{
    # Old Testament
    "genesis"="GEN";"gen"="GEN"
    "exodus"="EXO";"exo"="EXO";"ex"="EXO"
    "leviticus"="LEV";"lev"="LEV"
    "numbers"="NUM";"num"="NUM"
    "deuteronomy"="DEU";"deu"="DEU";"deut"="DEU"
    "joshua"="JOS";"jos"="JOS"
    "judges"="JDG";"jdg"="JDG"
    "ruth"="RUT";"rut"="RUT"
    "1 samuel"="1SA";"1sa"="1SA";"1samuel"="1SA"
    "2 samuel"="2SA";"2sa"="2SA";"2samuel"="2SA"
    "1 kings"="1KI";"1ki"="1KI";"1kings"="1KI"
    "2 kings"="2KI";"2ki"="2KI";"2kings"="2KI"
    "1 chronicles"="1CH";"1ch"="1CH";"1chronicles"="1CH"
    "2 chronicles"="2CH";"2ch"="2CH";"2chronicles"="2CH"
    "ezra"="EZR";"ezr"="EZR"
    "nehemiah"="NEH";"neh"="NEH"
    "esther"="EST";"est"="EST"
    "job"="JOB"
    "psalms"="PSA";"psalm"="PSA";"psa"="PSA";"ps"="PSA"
    "proverbs"="PRO";"pro"="PRO";"prov"="PRO"
    "ecclesiastes"="ECC";"ecc"="ECC";"eccl"="ECC"
    "song of solomon"="SNG";"song"="SNG";"sng"="SNG";"sos"="SNG"
    "isaiah"="ISA";"isa"="ISA"
    "jeremiah"="JER";"jer"="JER"
    "lamentations"="LAM";"lam"="LAM"
    "ezekiel"="EZK";"ezk"="EZK";"eze"="EZK"
    "daniel"="DAN";"dan"="DAN"
    "hosea"="HOS";"hos"="HOS"
    "joel"="JOL";"jol"="JOL"
    "amos"="AMO";"amo"="AMO"
    "obadiah"="OBA";"oba"="OBA"
    "jonah"="JON";"jon"="JON"
    "micah"="MIC";"mic"="MIC"
    "nahum"="NAH";"nah"="NAH"
    "habakkuk"="HAB";"hab"="HAB"
    "zephaniah"="ZEP";"zep"="ZEP"
    "haggai"="HAG";"hag"="HAG"
    "zechariah"="ZEC";"zec"="ZEC"
    "malachi"="MAL";"mal"="MAL"
    # New Testament
    "matthew"="MAT";"mat"="MAT";"matt"="MAT"
    "mark"="MRK";"mrk"="MRK"
    "luke"="LUK";"luk"="LUK"
    "john"="JHN";"jhn"="JHN";"jn"="JHN"
    "acts"="ACT";"act"="ACT"
    "romans"="ROM";"rom"="ROM"
    "1 corinthians"="1CO";"1co"="1CO";"1cor"="1CO";"1corinthians"="1CO"
    "2 corinthians"="2CO";"2co"="2CO";"2cor"="2CO";"2corinthians"="2CO"
    "galatians"="GAL";"gal"="GAL"
    "ephesians"="EPH";"eph"="EPH"
    "philippians"="PHP";"php"="PHP";"phil"="PHP"
    "colossians"="COL";"col"="COL"
    "1 thessalonians"="1TH";"1th"="1TH";"1thess"="1TH";"1thessalonians"="1TH"
    "2 thessalonians"="2TH";"2th"="2TH";"2thess"="2TH";"2thessalonians"="2TH"
    "1 timothy"="1TI";"1ti"="1TI";"1tim"="1TI";"1timothy"="1TI"
    "2 timothy"="2TI";"2ti"="2TI";"2tim"="2TI";"2timothy"="2TI"
    "titus"="TIT";"tit"="TIT"
    "philemon"="PHM";"phm"="PHM"
    "hebrews"="HEB";"heb"="HEB"
    "james"="JAS";"jas"="JAS"
    "1 peter"="1PE";"1pe"="1PE";"1pet"="1PE";"1peter"="1PE"
    "2 peter"="2PE";"2pe"="2PE";"2pet"="2PE";"2peter"="2PE"
    "1 john"="1JN";"1jn"="1JN";"1john"="1JN"
    "2 john"="2JN";"2jn"="2JN";"2john"="2JN"
    "3 john"="3JN";"3jn"="3JN";"3john"="3JN"
    "jude"="JUD";"jud"="JUD"
    "revelation"="REV";"rev"="REV"
}

# ── Helper Functions ─────────────────────────────────────────────────────────

function Resolve-BookId {
    param([string]$bookName)
    $key = $bookName.Trim().ToLower()
    if ($script:BOOK_IDS.ContainsKey($key)) { return $script:BOOK_IDS[$key] }
    # Fuzzy: find first key that starts with or contains the input
    foreach ($k in $script:BOOK_IDS.Keys) {
        if ($k.StartsWith($key) -or $k -like "*$key*") { return $script:BOOK_IDS[$k] }
    }
    return $null
}

function Invoke-BibleApi {
    param([string]$endpoint)
    try {
        $uri = "$script:BIBLE_API$endpoint"
        $response = Invoke-RestMethod -Uri $uri -Method GET -TimeoutSec 15 -ErrorAction Stop -ResponseHeadersVariable headers
        
        # Check Content-Type header
        if ($headers.'Content-Type' -notmatch "application/json") {
            return $null # Not JSON, treat as failure
        }
        
        return $response
    } catch {
        return $null
    }
}

function Get-VerseText {
    param($verseContent)
    $parts = @()
    foreach ($item in $verseContent) {
        if ($item -is [string]) {
            $parts += $item
        } elseif ($item.text) {
            $parts += $item.text
        } elseif ($item.heading) {
            # inline heading — skip for verse text
        }
    }
    return ($parts -join " ").Trim()
}

function Format-Reference {
    param([string]$book, [int]$chapter, [int]$verse, [int]$endVerse = 0)
    $bookDisplay = $book
    # Map ID back to common name for display
    $displayNames = @{
        "GEN"="Genesis";"EXO"="Exodus";"LEV"="Leviticus";"NUM"="Numbers";"DEU"="Deuteronomy"
        "JOS"="Joshua";"JDG"="Judges";"RUT"="Ruth";"1SA"="1 Samuel";"2SA"="2 Samuel"
        "1KI"="1 Kings";"2KI"="2 Kings";"1CH"="1 Chronicles";"2CH"="2 Chronicles"
        "EZR"="Ezra";"NEH"="Nehemiah";"EST"="Esther";"JOB"="Job";"PSA"="Psalms"
        "PRO"="Proverbs";"ECC"="Ecclesiastes";"SNG"="Song of Solomon";"ISA"="Isaiah"
        "JER"="Jeremiah";"LAM"="Lamentations";"EZK"="Ezekiel";"DAN"="Daniel"
        "HOS"="Hosea";"JOL"="Joel";"AMO"="Amos";"OBA"="Obadiah";"JON"="Jonah"
        "MIC"="Micah";"NAH"="Nahum";"HAB"="Habakkuk";"ZEP"="Zephaniah";"HAG"="Haggai"
        "ZEC"="Zechariah";"MAL"="Malachi";"MAT"="Matthew";"MRK"="Mark";"LUK"="Luke"
        "JHN"="John";"ACT"="Acts";"ROM"="Romans";"1CO"="1 Corinthians";"2CO"="2 Corinthians"
        "GAL"="Galatians";"EPH"="Ephesians";"PHP"="Philippians";"COL"="Colossians"
        "1TH"="1 Thessalonians";"2TH"="2 Thessalonians";"1TI"="1 Timothy";"2TI"="2 Timothy"
        "TIT"="Titus";"PHM"="Philemon";"HEB"="Hebrews";"JAS"="James";"1PE"="1 Peter"
        "2PE"="2 Peter";"1JN"="1 John";"2JN"="2 John";"3JN"="3 John";"JUD"="Jude";"REV"="Revelation"
    }
    if ($displayNames.ContainsKey($book)) { $bookDisplay = $displayNames[$book] }
    if ($endVerse -gt 0 -and $endVerse -ne $verse) {
        return "$bookDisplay $chapter`:$verse-$endVerse"
    }
    return "$bookDisplay $chapter`:$verse"
}

function Wrap-Text {
    param([string]$text, [int]$width = 68)
    $words = $text -split '\s+'
    $lines = @()
    $current = ""
    foreach ($word in $words) {
        if (($current + " " + $word).TrimStart().Length -le $width) {
            $current = ($current + " " + $word).TrimStart()
        } else {
            if ($current) { $lines += $current }
            $current = $word
        }
    }
    if ($current) { $lines += $current }
    return $lines
}

# ── Main Tool Function ───────────────────────────────────────────────────────

function Invoke-BibleTool {
    param(
        [string]$mode,
        [string]$reference   = "",
        [string]$topic       = "",
        [string]$translation = "BSB",
        [string]$compare_with = "",
        [string]$commentary  = ""
    )

    $translation  = $translation.ToUpper().Trim()
    $compare_with = $compare_with.ToUpper().Trim()

    # ── MODE: verse ──────────────────────────────────────────────────────────
    if ($mode -eq "verse") {
        if ([string]::IsNullOrWhiteSpace($reference)) {
            return "ERROR: Please provide a reference (e.g. 'John 3:16' or 'Romans 8:28-30')."
        }

        # Parse reference: "Book Chapter:Verse" or "Book Chapter:Verse-EndVerse"
        $refPattern = '^(.+?)\s+(\d+):(\d+)(?:-(\d+))?$'
        if ($reference -notmatch $refPattern) {
            return "ERROR: Could not parse reference '$reference'. Use format: 'Book Chapter:Verse' (e.g. 'John 3:16')."
        }
        $bookName  = $Matches[1]
        $chapter   = [int]$Matches[2]
        $verseStart = [int]$Matches[3]
        $verseEnd   = if ($Matches[4]) { [int]$Matches[4] } else { $verseStart }

        $bookId = Resolve-BookId $bookName
        if (-not $bookId) { return "ERROR: Could not identify book '$bookName'. Try spelling it out fully." }

        $chapterData = Invoke-BibleApi "/$translation/$bookId/$chapter.json"
        if (-not $chapterData) {
            return "ERROR: Could not fetch $bookName $chapter from translation '$translation'. Check that the translation ID is valid (e.g. BSB, KJV, NIV, ESV, ASV)."
        }

        # Extract requested verses
        $verses = $chapterData.chapter.content | Where-Object { $_.type -eq "verse" -and $_.number -ge $verseStart -and $_.number -le $verseEnd }
        if (-not $verses) { return "ERROR: Verses $verseStart-$verseEnd not found in $bookName $chapter." }

        $refLabel = Format-Reference $bookId $chapter $verseStart $verseEnd
        $transName = $chapterData.translation.shortName
        $consoleLines = @()
        $resultLines  = @()

        # Title line
        $consoleLines += "  $refLabel  ($transName)"
        $consoleLines += ""

        foreach ($v in $verses) {
            $text = Get-VerseText $v.content
            $wrapped = Wrap-Text "[$($v.number)] $text" 68
            foreach ($line in $wrapped) {
                $consoleLines += "  $line"
            }
            $resultLines += "[$($v.number)] $text"
        }

        # Footnotes for these verses?
        $noteIds = ($verses | ForEach-Object { $_.content } | Where-Object { $_ -is [hashtable] -or ($_.PSObject.Properties.Name -contains 'noteId') } | ForEach-Object { $_.noteId }) | Select-Object -Unique
        $footnotes = $chapterData.chapter.footnotes | Where-Object { $noteIds -contains $_.noteId }
        if ($footnotes) {
            $consoleLines += ""
            $consoleLines += "  ── Footnotes ──"
            foreach ($fn in $footnotes) {
                $fnLines = Wrap-Text "* $($fn.text)" 66
                foreach ($l in $fnLines) { $consoleLines += "  $l" }
            }
        }

        Draw-Box -Lines $consoleLines -Title "📖 Bible" -Color Cyan

        $resultText = "$refLabel ($transName): " + ($resultLines -join " | ")
        return "CONSOLE::Rendered.::END_CONSOLE::$resultText"
    }

    # ── MODE: compare ─────────────────────────────────────────────────────────
    elseif ($mode -eq "compare") {
        if ([string]::IsNullOrWhiteSpace($reference)) { return "ERROR: Provide a reference to compare." }
        if ([string]::IsNullOrWhiteSpace($compare_with)) { return "ERROR: Provide a second translation in compare_with (e.g. KJV)." }

        $refPattern = '^(.+?)\s+(\d+):(\d+)(?:-(\d+))?$'
        if ($reference -notmatch $refPattern) { return "ERROR: Could not parse reference '$reference'." }
        $bookName   = $Matches[1]
        $chapter    = [int]$Matches[2]
        $verseStart = [int]$Matches[3]
        $verseEnd   = if ($Matches[4]) { [int]$Matches[4] } else { $verseStart }
        $bookId     = Resolve-BookId $bookName
        if (-not $bookId) { return "ERROR: Could not identify book '$bookName'." }

        $refLabel = Format-Reference $bookId $chapter $verseStart $verseEnd
        $translations = @($translation, $compare_with)
        $consoleLines = @("  $refLabel — Translation Comparison", "")
        $resultParts  = @()
        $firstCall = $true

        foreach ($t in $translations) {
            if (-not $firstCall) {
                Start-Sleep -Seconds 10 # Delay between API calls
            }
            $firstCall = $false
            $data = Invoke-BibleApi "/$t/$bookId/$chapter.json"
            if (-not $data) {
                $consoleLines += "  [$t] — Could not retrieve (invalid translation ID?)"
                $consoleLines += ""
                $resultParts += "$t`: [Translation could not be retrieved]"
                continue
            }
            $verses = $data.chapter.content | Where-Object { $_.type -eq "verse" -and $_.number -ge $verseStart -and $_.number -le $verseEnd }
            if (-not $verses) {
                $resultParts += "$t`: [Translation could not be retrieved]"
                $consoleLines += "  [$t] — Could not retrieve (invalid translation ID or API issue)."
                continue
            }
            $transDisplay = $data.translation.shortName
            $consoleLines += "  ── $transDisplay ──"
            $allText = @()
            foreach ($v in $verses) {
                $text = Get-VerseText $v.content
                $wrapped = Wrap-Text "[$($v.number)] $text" 64
                foreach ($line in $wrapped) { $consoleLines += "  $line" }
                $allText += "[$($v.number)] $text"
            }
            $consoleLines += ""
            $resultParts += "$transDisplay`: " + ($allText -join " ")
        }

        Draw-Box -Lines $consoleLines -Title "📖 Compare Translations" -Color Magenta
        $result = "$refLabel — " + ($resultParts -join " || ")
        return "CONSOLE::Rendered.::END_CONSOLE::$result"
    }

    # ── MODE: topic ───────────────────────────────────────────────────────────
    elseif ($mode -eq "topic") {
        if ([string]::IsNullOrWhiteSpace($topic)) { return "ERROR: Provide a topic or keyword to search." }

        # Gemma already knows which passages are relevant — the topic param
        # should be a comma-separated list of references OR a plain topic.
        # If it looks like references, fetch them directly.
        # If it's a plain topic, use AI knowledge to map to key passages.
        # The tool fetches them and returns the text for Gemma to synthesize.

        $refList = @()

        # Try to detect if the topic is actually a list of references like "John 3:16, Romans 8:28"
        $isRefList = $topic -match '^\s*[A-Za-z0-9 ]+\d+:\d+'
        if ($isRefList) {
            $rawRefs = $topic -split ',\s*'
            foreach ($raw in $rawRefs) {
                $raw = $raw.Trim()
                if ($raw -match '^(.+?)\s+(\d+):(\d+)(?:-(\d+))?$') {
                    $refList += @{
                        BookName  = $Matches[1]
                        Chapter   = [int]$Matches[2]
                        VerseStart = [int]$Matches[3]
                        VerseEnd  = if ($Matches[4]) { [int]$Matches[4] } else { [int]$Matches[3] }
                    }
                }
            }
        }

        if ($refList.Count -eq 0) {
            # Return a signal to Gemma to resolve the topic to references first
            return "ERROR: The bible tool's 'topic' mode requires you (the AI) to first resolve the topic '$topic' into specific Bible references, then call the tool again with those references as a comma-separated list in the 'topic' parameter. Example: topic='John 3:16, Romans 5:8, Ephesians 2:8-9'"
        }

        $consoleLines = @("  Topic: $topic", "  Translation: $translation", "")
        $resultParts  = @()

        foreach ($ref in $refList) {
            $bookId = Resolve-BookId $ref.BookName
            if (-not $bookId) { continue }
            $data = Invoke-BibleApi "/$translation/$bookId/$($ref.Chapter).json"
            if (-not $data) { continue }
            $verses = $data.chapter.content | Where-Object { $_.type -eq "verse" -and $_.number -ge $ref.VerseStart -and $_.number -le $ref.VerseEnd }
            if (-not $verses) { continue }

            $refLabel = Format-Reference $bookId $ref.Chapter $ref.VerseStart $ref.VerseEnd
            $consoleLines += "  ── $refLabel ──"
            $allText = @()
            foreach ($v in $verses) {
                $text = Get-VerseText $v.content
                $wrapped = Wrap-Text "[$($v.number)] $text" 64
                foreach ($line in $wrapped) { $consoleLines += "  $line" }
                $allText += "[$($v.number)] $text"
            }
            $consoleLines += ""
            $resultParts += "$refLabel`: " + ($allText -join " ")
        }

        Draw-Box -Lines $consoleLines -Title "📖 Bible — Topic Search" -Color Green
        $result = "Passages on '$topic' ($translation): " + ($resultParts -join " | ")
        return "CONSOLE::Rendered.::END_CONSOLE::$result"
    }

    # ── MODE: crossref ────────────────────────────────────────────────────────
    elseif ($mode -eq "crossref") {
        if ([string]::IsNullOrWhiteSpace($reference)) { return "ERROR: Provide a reference to find cross-references for." }

        $refPattern = '^(.+?)\s+(\d+):(\d+)$'
        if ($reference -notmatch $refPattern) { return "ERROR: Cross-reference lookup requires a single verse (e.g. 'John 3:16')." }
        $bookName  = $Matches[1]
        $chapter   = [int]$Matches[2]
        $verse     = [int]$Matches[3]
        $bookId    = Resolve-BookId $bookName
        if (-not $bookId) { return "ERROR: Could not identify book '$bookName'." }

        # Fetch the original verse text
        $sourceData = Invoke-BibleApi "/$translation/$bookId/$chapter.json"
        $sourceVerse = $null
        if ($sourceData) {
            $sourceVerse = $sourceData.chapter.content | Where-Object { $_.type -eq "verse" -and $_.number -eq $verse } | Select-Object -First 1
        }

        # Fetch cross-reference dataset
        $xrefData = Invoke-BibleApi "/d/open-cross-ref/$bookId/$chapter.json"
        if (-not $xrefData) { return "ERROR: Could not retrieve cross-references for $reference." }

        $verseRefs = $xrefData.chapter.content | Where-Object { $_.verse -eq $verse } | Select-Object -First 1
        if (-not $verseRefs -or $verseRefs.references.Count -eq 0) {
            return "ERROR: No cross-references found for $reference in the dataset."
        }

        # Take top 8 by score
        $topRefs = $verseRefs.references | Sort-Object -Property score -Descending | Select-Object -First 8

        $refLabel = Format-Reference $bookId $chapter $verse
        $consoleLines = @()

        # Show source verse
        if ($sourceVerse) {
            $sourceText = Get-VerseText $sourceVerse.content
            $consoleLines += "  SOURCE: $refLabel"
            $wrapped = Wrap-Text $sourceText 64
            foreach ($l in $wrapped) { $consoleLines += "    $l" }
            $consoleLines += ""
        }

        $consoleLines += "  CROSS-REFERENCES (top $($topRefs.Count) by relevance):"
        $consoleLines += ""

        $resultParts = @("Source: $refLabel")

        foreach ($xref in $topRefs) {
            $xBookId  = $xref.book
            $xChapter = $xref.chapter
            $xVerse   = $xref.verse
            $xEnd     = if ($xref.endVerse) { $xref.endVerse } else { $xVerse }
            $xLabel   = Format-Reference $xBookId $xChapter $xVerse $xEnd

            $xData = Invoke-BibleApi "/$translation/$xBookId/$xChapter.json"
            if ($xData) {
                $xVerses = $xData.chapter.content | Where-Object { $_.type -eq "verse" -and $_.number -ge $xVerse -and $_.number -le $xEnd }
                $xText = ($xVerses | ForEach-Object { Get-VerseText $_.content }) -join " "
                $wrapped = Wrap-Text "$xLabel — $xText" 66
                foreach ($l in $wrapped) { $consoleLines += "  $l" }
                $consoleLines += ""
                $resultParts += "$xLabel`: $xText"
            } else {
                $consoleLines += "  $xLabel (could not retrieve text)"
                $consoleLines += ""
                $resultParts += $xLabel
            }
        }

        Draw-Box -Lines $consoleLines -Title "📖 Cross-References: $refLabel" -Color Yellow
        $result = $resultParts -join " | "
        return "CONSOLE::Rendered.::END_CONSOLE::$result"
    }

    # ── MODE: commentary ──────────────────────────────────────────────────────
    elseif ($mode -eq "commentary") {
        if ([string]::IsNullOrWhiteSpace($reference)) { return "ERROR: Provide a reference for commentary lookup." }

        $refPattern = '^(.+?)\s+(\d+):(\d+)(?:-(\d+))?$'
        if ($reference -notmatch $refPattern) { return "ERROR: Could not parse reference '$reference'." }
        $bookName   = $Matches[1]
        $chapter    = [int]$Matches[2]
        $verseStart = [int]$Matches[3]
        $verseEnd   = if ($Matches[4]) { [int]$Matches[4] } else { $verseStart }
        $bookId     = Resolve-BookId $bookName
        if (-not $bookId) { return "ERROR: Could not identify book '$bookName'." }

        # Default commentary
        $commentaryId = if ([string]::IsNullOrWhiteSpace($commentary)) { "tyndale" } else { $commentary.ToLower().Trim() }

        $refLabel    = Format-Reference $bookId $chapter $verseStart $verseEnd
        $commentData = Invoke-BibleApi "/c/$commentaryId/$bookId/$chapter.json"
        if (-not $commentData) {
            return "ERROR: Could not retrieve commentary '$commentaryId' for $refLabel. Available: 'tyndale', 'adam-clarke'."
        }

        $commentaryName = $commentData.commentary.englishName
        $verses = $commentData.chapter.content | Where-Object { $_.type -eq "verse" -and $_.number -ge $verseStart -and $_.number -le $verseEnd }
        if (-not $verses) { return "ERROR: Commentary notes for verses $verseStart-$verseEnd not found in $bookName $chapter." }

        $consoleLines = @("  $refLabel  — $commentaryName", "")
        $resultParts  = @()

        foreach ($v in $verses) {
            $text = Get-VerseText $v.content
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            $consoleLines += "  [v.$($v.number)]"
            # Commentary notes can be long — truncate at 500 chars for display
            $displayText = if ($text.Length -gt 500) { $text.Substring(0, 500) + "..." } else { $text }
            $wrapped = Wrap-Text $displayText 66
            foreach ($l in $wrapped) { $consoleLines += "    $l" }
            $consoleLines += ""
            $resultParts += "v.$($v.number)`: $text"
        }

        Draw-Box -Lines $consoleLines -Title "📖 Commentary" -Color DarkCyan
        $result = "$refLabel ($commentaryName): " + ($resultParts -join " | ")
        return "CONSOLE::Rendered.::END_CONSOLE::$result"
    }

    # ── MODE: books ───────────────────────────────────────────────────────────
    elseif ($mode -eq "books") {
        # Supports three sources:
        #   translation  -> /api/{translation}/books.json         (default, e.g. BSB)
        #   commentary   -> /api/c/{commentary}/books.json        (e.g. tyndale, adam-clarke)
        #   dataset      -> /api/d/{dataset}/books.json           (e.g. open-cross-ref)

        $source = if (-not [string]::IsNullOrWhiteSpace($commentary)) { "commentary" }
                  elseif ($translation -eq "open-cross-ref") { "dataset" }
                  else { "translation" }

        switch ($source) {
            "commentary" {
                $commentaryId = $commentary.ToLower().Trim()
                $data = Invoke-BibleApi "/c/$commentaryId/books.json"
                if (-not $data) { return "ERROR: Could not retrieve book list for commentary '$commentaryId'. Try 'tyndale' or 'adam-clarke'." }
                $sourceName = $data.commentary.englishName
                $books = $data.books
            }
            "dataset" {
                $datasetId = "open-cross-ref"
                $data = Invoke-BibleApi "/d/$datasetId/books.json"
                if (-not $data) { return "ERROR: Could not retrieve book list for dataset '$datasetId'." }
                $sourceName = $data.dataset.englishName
                $books = $data.books
            }
            default {
                $data = Invoke-BibleApi "/$translation/books.json"
                if (-not $data) { return "ERROR: Could not retrieve book list for translation '$translation'. Check the translation ID." }
                $sourceName = $data.translation.englishName
                $books = $data.books
            }
        }

        # Split into OT (order 1-39) and NT (order 40+)
        $ot = $books | Where-Object { $_.order -le 39 } | Sort-Object order
        $nt = $books | Where-Object { $_.order -ge 40 } | Sort-Object order

        $consoleLines = @("  Source: $sourceName", "  $($books.Count) books available", "")

        # Old Testament
        $consoleLines += "  -- Old Testament ($($ot.Count) books) --"
        $row = @()
        foreach ($b in $ot) {
            $name = if ($b.commonName) { $b.commonName } else { $b.id }
            $entry = "$($b.order.ToString().PadLeft(2)). $name"
            $row += $entry.PadRight(26)
            if ($row.Count -eq 3) {
                $consoleLines += "  " + ($row -join "")
                $row = @()
            }
        }
        if ($row.Count -gt 0) { $consoleLines += "  " + ($row -join "") }

        $consoleLines += ""

        # New Testament
        $consoleLines += "  -- New Testament ($($nt.Count) books) --"
        $row = @()
        foreach ($b in $nt) {
            $name = if ($b.commonName) { $b.commonName } else { $b.id }
            $entry = "$($b.order.ToString().PadLeft(2)). $name"
            $row += $entry.PadRight(26)
            if ($row.Count -eq 3) {
                $consoleLines += "  " + ($row -join "")
                $row = @()
            }
        }
        if ($row.Count -gt 0) { $consoleLines += "  " + ($row -join "") }

        Draw-Box -Lines $consoleLines -Title "📖 Books -- $sourceName" -Color Blue

        $bookNames = $books | ForEach-Object { if ($_.commonName) { $_.commonName } else { $_.id } }
        $result = "Books in $sourceName ($($books.Count) total): " + ($bookNames -join ", ")
        return "CONSOLE::Rendered.::END_CONSOLE::$result"
    }

    else {
        return "ERROR: Unknown mode '$mode'. Valid modes: verse, compare, topic, crossref, commentary, books."
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name             = "bible"
    Icon             = "✝"
    RendersToConsole = $true
    Interactive      = $false
    Version          = "1.0.3"
    Category         = @("Religion/Philosophy")
    Description      = "Fetches Bible verses, compares translations, finds cross-references, and retrieves commentary using the free bible.helloao.org API."

    Behavior = @"
Use this tool whenever the user asks about Bible verses, passages, scripture references, theological topics, or wants to explore the Bible. You control all logic — decide the mode and parameters based on natural language:

MODES:
- mode="verse"      -> Fetch a specific verse or passage. Requires: reference (e.g. "John 3:16" or "Romans 8:28-30"). Optional: translation (default BSB).
- mode="compare"    -> Show the same passage in two translations side by side. Requires: reference + compare_with (e.g. compare_with="KJV"). Optional: translation (default BSB).
- mode="topic"      -> Find Bible passages on a topic. YOU must first resolve the topic to a list of known Bible references based on your training knowledge, then pass them as a comma-separated string in the 'topic' parameter (e.g. topic="John 3:16, Romans 5:8, Ephesians 2:8-9"). The tool fetches and displays the actual text. Call the tool TWICE if needed: first attempt will return an error explaining to supply references.
- mode="crossref"   -> Find cross-references for a single verse. Requires: reference (single verse only, e.g. "Psalm 23:1").
- mode="commentary" -> Get scholarly commentary on a passage. Requires: reference. Optional: commentary="tyndale" (default) or commentary="adam-clarke".
- mode="books"      -> List all books available in a translation, commentary, or dataset. Optional: translation (default BSB), commentary (e.g. "tyndale"), or set translation="open-cross-ref" for the cross-reference dataset.

TRANSLATION IDs (common English):
BSB (Berean Standard Bible, default), KJV (King James), ASV (American Standard), WEB (World English Bible), YLT (Young's Literal Translation), NASB, NIV, ESV — note: only public domain / open license translations are available. If a translation fails, fall back to BSB.

BOOK IDs are auto-resolved from natural names (e.g. "Genesis", "Gen", "1 Cor", "Rev" all work).

WORKFLOW GUIDANCE:
- If a user says "show me John 3:16" -> mode="verse", reference="John 3:16"
- If a user says "compare Romans 8:28 in KJV and BSB" -> mode="compare", reference="Romans 8:28", translation="BSB", compare_with="KJV"
- If a user says "what does the Bible say about forgiveness?" -> mode="topic", topic="Matthew 6:14-15, Luke 17:3-4, Ephesians 4:32, Colossians 3:13"
- If a user says "find verses connected to Psalm 23:1" -> mode="crossref", reference="Psalm 23:1"
- If a user says "get commentary on John 1:1" -> mode="commentary", reference="John 1:1"
After the tool returns text, synthesize and explain it in your own words — don't just repeat the raw output.
"@

    Keywords = @("bible", "scripture", "verse", "passage", "gospel", "testament", "psalm", "proverb", "genesis", "revelation", "jesus", "god", "holy", "christian", "theology", "cross-reference", "commentary", "translation", "kjv", "bsb", "esv")

    Parameters = @{
        mode         = "string - Required. One of: verse, compare, topic, crossref, commentary, books"
        reference    = "string - Bible reference like 'John 3:16' or 'Romans 8:28-30'. Required for verse/compare/crossref/commentary modes."
        topic        = "string - For topic mode: a comma-separated list of Bible references you have resolved (e.g. 'John 3:16, Romans 5:8')"
        translation  = "string - Translation ID (default: BSB). Examples: KJV, ASV, WEB, YLT"
        compare_with = "string - Second translation ID for compare mode (e.g. KJV)"
        commentary   = "string - Commentary ID for commentary mode. Options: 'tyndale' (default), 'adam-clarke'"
    }

    Example = '<tool_call>{ "name": "bible", "parameters": { "mode": "verse", "reference": "John 3:16", "translation": "BSB" } }</tool_call>'

    FormatLabel = { param($p) "📖 bible [$($p.mode)] -> $($p.reference)$($p.topic)$($p.compare_with)" }

    Execute = {
        param($params)
        Invoke-BibleTool @params
    }

    Tutorial = "I can look up Bible verses, compare translations, find cross-references, and pull commentary! Try: 'Show me Psalm 23', 'Compare John 1:1 in KJV and BSB', 'What does the Bible say about hope?', or 'Find cross-references for Romans 8:28'."

    ToolUseGuidanceMajor = "You are the intelligence layer for this tool. The API has no search — you must translate topics into specific references using your own knowledge, then call the tool to fetch the actual text. Always pick the most relevant 3-5 passages for topic queries. After the tool returns raw verse text, synthesize and add context for the user. For crossref results, briefly explain the thematic connections between the passages."

    ToolUseGuidanceMinor = "Use mode=verse for specific verses, mode=topic with comma-separated references for topics, mode=compare for translation comparison, mode=crossref for related verses, mode=commentary for scholarly notes."

    Relationships = @{
        "writefile" = "When both tools are active and the user wants to save a Bible study, devotional, or passage collection to a file, use the 'bible' tool to fetch the verse text first, then use 'writefile' to save the result."
    }
}