# Adding a Tool to Gemma CLI
### A Step-by-Step Tutorial — Building `writefile.ps1` from Scratch

This guide walks through every step required to add a new tool to Gemma CLI v0.5.0+.
By the end, Gemma will be able to write or overwrite a file on disk when asked.

---

## How the Tool System Works

The modern tool system is dynamic. You no longer need to manually edit the system prompt.

```
Gemma decides to use a tool based on the dynamic prompt
        ↓
Gemma returns <tool_call>{"name": "writefile", ...}</tool_call>
        ↓
Main loop looks up $script:TOOLS["writefile"]       ← registered by ToolLoader
        ↓
User approves via arrow menu
        ↓
Start-Job executes the tool in a background process
        ↓
Calls & $ToolMeta.Execute $params                   ← your Execute block
        ↓
Result string returned to Gemma as TOOL RESULT
```

You only need to touch **one file** to add a tool:
1. `tools/writefile.ps1` — the tool itself

---

## Step 1 — Create the Tool File

Create `tools/writefile.ps1`. Every tool file consists of a worker function and a `$ToolMeta` registration block.

```powershell
# tools/writefile.ps1
# Responsibility: Write or overwrite a file with provided content.

function Invoke-WriteFileTool {
    param(
        [string]$file_path,
        [string]$content
    )

    # Sanitize path — strip quotes and handle escapes
    $file_path = $file_path.Trim().Trim("'").Trim('"').Replace('\\', '\')

    if ([string]::IsNullOrWhiteSpace($file_path)) {
        return "ERROR: file_path cannot be empty."
    }

    try {
        # Ensure parent directory exists
        $parentDir = Split-Path -Path $file_path -Parent
        if (![string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }

        Set-Content -Path $file_path -Value $content -Encoding UTF8 -Force -ErrorAction Stop
        
        # Standard result format:
        return "OK: Wrote $($content.Length) characters to '$file_path'"

    } catch {
        return "ERROR: Could not write file '$file_path'. $($_.Exception.Message)"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────
# ToolLoader.ps1 dynamically scans this block to build Gemma's instructions.

$ToolMeta = @{
    # The name Gemma uses in its <tool_call> JSON (lowercase, no spaces)
    Name        = "writefile"

    # RendersToConsole: 
    # $false (default) -> Shows an "Executing..." spinner while running.
    # $true            -> Hides the spinner (use if your tool draws its own UI).
    RendersToConsole = $false

    # Behavior: Detailed instructions for the model on HOW and WHEN to use this tool.
    # Injected into the system prompt for high-reasoning models (e.g., 27B).
    Behavior    = "Use this tool to write content to a file. It can create new files or overwrite existing ones. Always confirm the path is safe before writing."

    # Description: A concise summary shown in /tools and used for smaller models.
    Description = "Writes or overwrites a local file with the provided text content."

    # Parameters: Schema defining what Gemma must provide.
    Parameters  = @{
        file_path = "string - path to the file to write"
        content   = "string - the full text content to write"
    }

    # Example: A sample tool call to guide the model's output format.
    Example     = "<tool_call>{ ""name"": ""writefile"", ""parameters"": { ""file_path"": ""hello.txt"", ""content"": ""Hello!"" } }</tool_call>"

    # FormatLabel: The text shown in the user's "Action Required" approval menu.
    FormatLabel = { param($params) "🔍 writefile -> $($params.file_path)" }

    # Execute: How the CLI invokes your function. 
    # $params is automatically converted to a Hashtable, so you can use splatting (@params).
    Execute     = {
        param($params)
        Invoke-WriteFileTool @params
    }
}
```

---

## Advanced Features

### 1. Console vs. Model Communication
You can return text that is shown to the user but hidden from the model (e.g., for ASCII art or UI elements) using the `CONSOLE::` tag:

```powershell
return "CONSOLE::(This text appears in the CLI only)::END_CONSOLE::(This text goes to Gemma)"
```

### 2. Multi-Tier Guidance
You can provide different instructions based on model size (e.g., simplified for 4B, detailed for 27B) by adding these properties to `$ToolMeta`:

- `ToolUseGuidanceMajor`: Detailed guidance for high-capacity models (27B, 12B).
- `ToolUseGuidanceMinor`: Simplified guidance for smaller models (4B, 1B).

### 3. Returning Images (Multimodal)
Tools can return images to Gemma's vision system by using the `IMAGE_DATA` protocol:

```powershell
return "IMAGE_DATA::$mimeType::$base64Data::$optionalPrompt"
```

---

## Step 2 — Zero-Config Integration

The CLI uses a dynamic instruction system. Ensure your `instructions.json` contains the `%%AVAILABLE_TOOLS%%` placeholder:

```json
{
  "system_prompt": "You are Gemma... \n\n%%AVAILABLE_TOOLS%%",
  ...
}
```

When the script starts, `ToolLoader.ps1` reads your `.ps1` files in `tools/`, extracts the metadata, and injects it directly into the prompt. **You no longer need to manually list tools in the JSON file.**

---

## Step 3 — Verify and Test

1. **Startup:** Run the CLI. You should see:
   `[OK] Loaded tool: writefile`
2. **List Tools:** Type `/tools` to see your new tool and its parameters.
3. **Unicode Support:** You can safely use emojis like `🔍` or `💾` in your `FormatLabel` or `Description`.
4. **Test Call:** 
   `You: write "hello" to test.txt`
   Confirm the approval menu appears and the file is created.

---

## Checklist

```
□ tools/writefile.ps1 created with UTF-8 encoding
□ $ToolMeta contains Name, RendersToConsole, Behavior, Description, etc.
□ Execute block uses @params splatting for cleanliness
□ Function returns "OK: ..." or "ERROR: ..." strings (or uses CONSOLE:: protocol)
□ instructions.json contains the %%AVAILABLE_TOOLS%% placeholder
□ Startup shows "[OK] Loaded tool: writefile"
□ End-to-end test passed
```

---

## Quick Reference — Modern Tool Template

```powershell
# tools/mytool.ps1

function Invoke-MyTool {
    param([string]$target)
    try {
        # Optional: return "CONSOLE::UI text::END_CONSOLE::Model text"
        return "OK: Handled $target"
    } catch {
        return "ERROR: $($_.Exception.Message)"
    }
}

$ToolMeta = @{
    Name             = "mytool"
    RendersToConsole = $false
    Behavior         = "Use this tool when the user needs X."
    Description      = "Does X to the target."
    Parameters       = @{ target = "string - the thing to act upon" }
    Example          = "<tool_call>{ ""name"": ""mytool"", ""parameters"": { ""target"": ""abc"" } }</tool_call>"
    FormatLabel      = { param($p) "🚀 mytool -> $($p.target)" }
    Execute          = { param($p) Invoke-MyTool @p }
}
```
