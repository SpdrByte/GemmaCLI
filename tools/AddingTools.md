# Adding a Tool to Gemma CLI
### A Step-by-Step Tutorial — Building `writefile.ps1` from Scratch

This guide walks through every step required to add a new tool to Gemma CLI.
By the end, Gemma will be able to write or overwrite a file on disk when asked.

---

## How the Tool System Works

When Gemma decides to use a tool, this is what happens:

```
Gemma returns <tool_call>{"name": "writefile", ...}</tool_call>
        ↓
Main loop looks up $script:TOOLS["writefile"]       ← registered by ToolLoader
        ↓
User approves via arrow menu
        ↓
Start-Job dot-sources tools/writefile.ps1           ← your file
        ↓
Calls & $ToolMeta.Execute $params                   ← your Execute block
        ↓
Result string returned to Gemma as TOOL RESULT
```

You only need to touch **two files** to add a tool:
1. `tools/writefile.ps1` — the tool itself
2. `instructions.json` — so Gemma knows the tool exists

---

## Step 1 — Create the Tool File

Create `tools/writefile.ps1`. Every tool file has the same two parts:
a function that does the work, and a `$ToolMeta` block that registers it.

```powershell
# tools/writefile.ps1
# Responsibility: Write or overwrite a file with provided content.

function Invoke-WriteFileTool {
    param(
        [string]$file_path,
        [string]$content
    )

    # Sanitize path — strip quotes that the model sometimes wraps around JSON strings
    $file_path = $file_path.Trim().Trim("'").Trim('"').Replace('\\', '\')

    if ([string]::IsNullOrWhiteSpace($file_path)) {
        return "ERROR: file_path cannot be empty."
    }

    try {
        # Resolve the directory and confirm it exists before writing
        $dir = Split-Path -Parent $file_path
        if ($dir -and -not (Test-Path $dir)) {
            return "ERROR: Directory does not exist: $dir"
        }

        Set-Content -Path $file_path -Value $content -Encoding UTF8 -ErrorAction Stop
        $written = (Get-Item $file_path).Length
        return "OK: Wrote $written bytes to $file_path"

    } catch {
        return "ERROR: Could not write file '$file_path'. $($_.Exception.Message)"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────
# ToolLoader.ps1 dot-sources this file and reads $ToolMeta to register the tool.
# ALL fields are required.

$ToolMeta = @{

    # The name Gemma uses in its <tool_call> JSON — must be lowercase, no spaces
    Name        = "writefile"

    # Human-readable description shown in /tools and used in the system prompt
    Description = "Writes or overwrites a local file with the provided text content."

    # Parameter schema — shown in /tools and injected into the system prompt
    Parameters  = @{
        file_path = "string - absolute or relative path to the file to write"
        content   = "string - the full text content to write into the file"
    }

    # Label shown in the approval menu when Gemma calls this tool
    # $params is the PSCustomObject from Gemma's JSON — access fields with dot notation
    FormatLabel = { param($params) "writefile -> $($params.file_path)" }

    # The actual execution — ALWAYS pass parameters explicitly, never splat (@params)
    # Splatting fails on PSCustomObject (deserialized JSON). Use named parameters.
    Execute     = {
        param($params)
        Invoke-WriteFileTool -file_path $params.file_path -content $params.content
    }
}
```

### Why explicit parameters instead of `@params`?

Gemma's tool call comes back as a `PSCustomObject`, not a hashtable.
PowerShell's splat operator (`@`) only works on hashtables, so splatting silently
passes nothing, and your function receives empty strings. Always pass fields explicitly:

```powershell
# ✗ WRONG — silently passes nothing
Execute = { param($params) Invoke-WriteFileTool @params }

# ✓ CORRECT — explicit named parameters
Execute = { param($params) Invoke-WriteFileTool -file_path $params.file_path -content $params.content }
```

---

## Step 2 — Tell Gemma the Tool Exists

Open `instructions.json` and find the tools section of your system prompt.
Add `writefile` to the list of available tools so Gemma knows it can use it:

```json
{
  "system_prompt": "You are Gemma, a helpful assistant. You have access to the following tools:\n\n<tools>\nreadfile(file_path): Reads the full content of a local file.\nsearchdir(dir_path, recursive): Lists files and folders with metadata.\nwritefile(file_path, content): Writes or overwrites a local file with text content.\n</tools>\n\nTo use a tool, respond with a <tool_call> block containing valid JSON...",
  "guardrails": { ... }
}
```

The exact wording matters. Gemma uses this description to decide when and how to
call the tool, and to construct the JSON parameters correctly.

---

## Step 3 — Verify Registration at Startup

Run the CLI. On startup, `Initialize-Tools` scans the `tools/` folder and loads
every `*.ps1` file it finds. You should see your new tool in the load summary:

```
  [OK] Loaded tool: readfile
  [OK] Loaded tool: searchdir
  [OK] Loaded tool: writefile      ← confirm this appears
  Loaded 3 tool(s).
```

If `writefile` is missing from this list, one of three things went wrong:

| Symptom | Cause | Fix |
|---|---|---|
| Tool not listed at all | File not found in `tools/` | Check filename is exactly `writefile.ps1` |
| Warning: did not define `$ToolMeta` | Missing or misspelled `$ToolMeta =` | Ensure the assignment is `$ToolMeta = @{...}` not just `@{...}` |
| Warning: Error loading tool | Syntax error in the file | Run `. .\tools\writefile.ps1` in a PS session to see the error |

You can also type `/tools` in the CLI at any time to see all registered tools
and confirm `writefile` is listed with its parameters.

---

## Step 4 — Test It

Ask Gemma to write a file:

```
You: write the text "hello from gemma" to test.txt
```

You should see:

```
 Tool request: writefile -> test.txt

╭─────────────────────────────────────────────╮
│ Action Required  •  writefile -> test.txt   │
│                                             │
│ ● Allow once                                │
│   Deny                                      │
╰─────────────────────────────────────────────╯

╭─────────────────────────────────────────────╮
│ ✓  writefile -> test.txt                    │
╰─────────────────────────────────────────────╯

 Gemma: I've written "hello from gemma" to test.txt successfully (18 bytes).
```

Then verify on disk:

```powershell
Get-Content test.txt
# hello from gemma
```

---

## Checklist

```
□ tools/writefile.ps1 created
□ $ToolMeta block present with Name, Description, Parameters, FormatLabel, Execute
□ Execute block uses explicit named parameters (not @params splat)
□ Function returns "ERROR: ..." strings on failure (never throws)
□ instructions.json system prompt updated with tool description
□ Startup shows "[OK] Loaded tool: writefile"
□ /tools command lists writefile with correct parameters
□ End-to-end test passed
```

---

## Quick Reference — Tool File Template

```powershell
# tools/mytool.ps1

function Invoke-MyTool {
    param([string]$param_one, [string]$param_two)
    $param_one = $param_one.Trim().Trim("'").Trim('"')
    try {
        # ... do work ...
        return "OK: result here"
    } catch {
        return "ERROR: $($_.Exception.Message)"
    }
}

$ToolMeta = @{
    Name        = "mytool"
    Description = "One sentence describing what this tool does."
    Parameters  = @{
        param_one = "string - description of first parameter"
        param_two = "string - description of second parameter"
    }
    FormatLabel = { param($params) "mytool -> $($params.param_one)" }
    Execute     = {
        param($params)
        Invoke-MyTool -param_one $params.param_one -param_two $params.param_two
    }
}
```

Drop this file in `tools/`, add the tool to `instructions.json`, restart — done.
