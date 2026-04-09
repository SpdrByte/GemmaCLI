# Adding a Tool to Gemma CLI v0.2.2
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

Create `tools/writefile.ps1`. 


## Step 2 - Create the header
ex.

# ===============================================
# GemmaCLI Tool - writefile.ps1 v1.0.0
# Responsibility: Writes content to a file. Includes overwrite protection.
# ===============================================


## Step 3

Every tool file consists of a worker function and a `$ToolMeta` registration block.

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

### 1. Console Output — Two Approaches

Tools have two ways to show output to the user. Choosing the wrong one is a common
mistake — read this carefully before building any tool with visual output.

---

#### Approach A — `Draw-Box` (color, live rendering)

`Draw-Box` is available inside tool jobs (UI.ps1 is dot-sourced automatically).
It calls `Write-Host` directly, so output renders immediately in full color
BEFORE the tool returns. You can also use bare `Write-Host` calls for custom
colored output (see `esp_boards.ps1` for a full example).
```powershell
Draw-Box -Lines @("Pin GPIO8", "Type: IO", "Voltage: 3.3V") -Title "Pin Info" -Color Green
Write-Host "  Extra line in yellow" -ForegroundColor Yellow
return "CONSOLE::Rendered.::END_CONSOLE::$resultForGemma"
```

**Rules when using Draw-Box / Write-Host:**
- Set `RendersToConsole = $true` in `$ToolMeta` — this hides the spinner,
  which would otherwise overlap your output.
- Still return a `CONSOLE::...::END_CONSOLE::$result` string. The CONSOLE
  portion is just a short acknowledgement (e.g. `"Rendered."`) — the main
  loop prints it in grey after your colored output, but it's ignorable.
- The actual content for Gemma goes in the `END_CONSOLE::` part as usual.

**Use when:** you need color, multiple colors per line, background colors,
or a polished formatted result (board diagrams, pin tables, status dashboards).

---

#### Approach B — `CONSOLE::` protocol (always grey, no color)

The `CONSOLE::` return string is printed by the main loop with
`Write-Host -ForegroundColor DarkGray`. There is no way to change this color
from within the protocol — it is always grey.
```powershell
return "CONSOLE::$asciiArt::END_CONSOLE::$resultForGemma"
```

**Rules:**
- Set `RendersToConsole = $false` (default) — the spinner shows while the
  tool runs, then the grey output appears after it completes.
- Do NOT use ANSI escape codes (e.g. `` `e[93m `` or `[char]27`). They will
  print literally because the string passes through `Write-Host -ForegroundColor`
  which overrides them. Plain Unicode characters only.

**Use when:** supplementary metadata about the result. Things the user might want to see but Gemma doesn't need. A confirmation that something happened, a secondary readout, a simple status. It's passive — the tool already did its work and this is a footnote.

---

### 9. Interactive Tools (Main Thread Access)
By default, all tools run in a **background job** for safety and to allow the user to cancel them with `Esc`. However, background jobs cannot access the "Interactive Console Handle" — they cannot read key presses or show interactive menus.

If your tool needs to ask the user a question (via `Read-Host` or `Show-ArrowMenu`), you must set:
`Interactive = $true`

**Impact:**
- **Main Thread Execution:** The tool runs in the main CLI process rather than a job.
- **Security Warning:** A ⚠ warning icon appears in the permission menu, and a "Main Thread" disclaimer is shown to the user.
- **No Spinner:** The "Gemma is thinking" spinner is automatically hidden.

---

#### Decision Rule (Visuals & Interaction)

| I need... | Use | RendersToConsole | Interactive |
|---|---|---|---|
| Multiple colors / colored boxes | `Draw-Box` + `Write-Host` | `$true` | `$false` |
| **User Input (Menus, Read-Host)** | **Interactive Logic** | **$true** | **$true** |
| Simple monochrome ASCII art | `CONSOLE::` protocol | `$false` | `$false` |
| No visual output at all | Plain `return "OK: ..."` | `$false` | `$false` |

---

## Step 4 — Zero-Config Integration
You can provide different instructions based on model size (e.g., simplified for 4B, detailed for 27B) by adding these properties to `$ToolMeta`:

- `ToolUseGuidanceMajor`: Detailed guidance for high-capacity models (27B, 12B).
- `ToolUseGuidanceMinor`: Simplified guidance for smaller models (4B, 1B).

### 3. Returning Images (Multimodal)
Tools can return images to Gemma's vision system by using the `IMAGE_DATA` protocol:

```powershell
return "IMAGE_DATA::$mimeType::$base64Data::$optionalPrompt"
```

### 4. Control Instructions (Audio/System)
Background jobs cannot reliably access the interactive audio system. To trigger system alerts, include these instructions in your `CONSOLE::` portion. The main loop will execute them and strip them from the user's view.

- **`PLAY_SOUND:filename`**: Plays a `.wav` from `C:\Windows\Media` (e.g., `PLAY_SOUND:tada`, `PLAY_SOUND:chord`). Best for user-facing feedback.
- **`BEEP:freq,dur;...`**: Chains system beeps (e.g., `BEEP:523,80;659,80`). Use for low-level alerts.

```powershell
# Example: Play 'tada' and show a message
return "CONSOLE::PLAY_SOUND:tada::END_CONSOLE::Model result text"
```

### 5. Tutorial Onboarding
Gemma CLI includes a guided onboarding system via the `tutorial` tool. You can provide a specific "Live Demo" script for your tool by adding a `Tutorial` field. This helps new users understand your tool's specific syntax and power.

```powershell
$ToolMeta = @{
    Name     = "mytool"
    Tutorial = "I can do X. Try saying: 'Show me X for ABC' to see a live demo!"
    # ...
}
```

### 6. Billing Awareness (Paid Tier)
If your tool uses a feature of the Gemini API that requires a billing-enabled project (like Grounding with Google Search or Maps), set `RequiresBilling = $true`. 

**Impact:**
- A ⚠️ warning icon and "Paid Tier" label appear in the `/tools` list.
- A financial disclaimer is injected into Gemma's instructions for this tool.
- This helps users understand why they might see quota errors if they are on the free tier.

### 7. Seamless Key Management
If your tool requires its own external API key (e.g., Brave Search, OpenWeather), use `RequiresKey = $true` and provide a `KeyUrl`.

**Impact:**
- **Auto-Setup**: When the user enables the tool in `/settings`, the CLI immediately detects the missing key and prompts the user to enter it.
- **Guidance**: The `KeyUrl` is displayed to the user so they can Ctrl+Click to get their key instantly.
- **Secure Storage**: Keys are encrypted using Windows DPAPI and stored separately from the main Gemma key.
- **Implementation**: Inside your tool's worker function, retrieve the key using:
  `$apiKey = Get-StoredKey -keyName "your_tool_name"`

### 8. Tool Synergies (Relationships)
The Synergy System allows tools to "see" each other. When two related tools are both active, the CLI automatically injects expanded behavioral instructions into the system prompt. This allows for complex workflows (like "Validate -> Render Diagram") without hardcoding one tool's name into another's base documentation.

**How to implement:**
Add a `Relationships` hashtable to your `$ToolMeta`. 
- **Key:** The name of the related tool.
- **Value:** The specific instruction for how Gemma should use the two together.

```powershell
$ToolMeta = @{
    Name = "my_rendering_tool"
    Relationships = @{
        "data_source_tool" = "When both are active, always use 'data_source_tool' to fetch the raw metrics before using 'my_rendering_tool' to draw the chart."
    }
    # ...
}
```

**Benefits:**
- **Zero Hallucination:** Instructions only appear if BOTH tools are enabled. If the user disables one, the synergy disappears, so Gemma won't try to call a tool she doesn't have.
- **Decoupled Logic:** Your tool's main `Behavior` stays focused on its core task, while the "glue" logic lives in the synergy layer.

---

## Step 4 — Zero-Config Integration

The CLI uses a dynamic instruction system. Ensure your `instructions.json` contains the `%%AVAILABLE_TOOLS%%` placeholder:

```json
{
  "system_prompt": "You are Gemma... \n\n%%AVAILABLE_TOOLS%%",
  ...
}
```

When the script starts, `ToolLoader.ps1` reads your `.ps1` files in `tools/`, extracts the metadata, and injects it directly into the prompt. **You no longer need to manually list tools in the JSON file.**

---

## Step 5 — Verify and Test

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
□ tools/writefile.ps1 created with UTF-8 with BOM encoding (Required for emojis)
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
    Interactive      = $false
    Behavior         = "Use this tool when the user needs X."
    Relationships    = @{ "other_tool" = "When both are active, do Y after doing X." }
    Tutorial         = "I can do X. Try saying: 'Use mytool on target' to see me in action!"
    Description      = "Does X to the target."
    Parameters       = @{ target = "string - the thing to act upon" }
    Example          = "<tool_call>{ ""name"": ""mytool"", ""parameters"": { ""target"": ""abc"" } }</tool_call>"
    FormatLabel      = { param($p) "🚀 mytool -> $($p.target)" }
    Execute          = { param($p) Invoke-MyTool @p }
}
```
