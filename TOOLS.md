# GemmaCLI Tool Wiki

## ask_user
**Status:** Active | **Interactive:** True | **Requires Key:** 
**Description:** Asks the user 1-4 multiple choice questions.

### Parameters
- `questions`: array - required. List of question objects: { id?: string, key?: string, question: string, header: string, options: [{label: string, description: string}], multiSelect: bool }

### Example
```
<tool_call>{ "name": "ask_user", "parameters": { "questions": [ { "id": "framework", "question": "Which framework should we use?", "header": "Framework", "options": [ { "label": "React", "description": "Industry standard" }, { "label": "Vue", "description": "Lightweight" } ] } ] } }</tool_call>
```

---

## generate_terminal_art
**Status:** Active | **Interactive:**  | **Requires Key:** 
**Description:** Generates a 16x16 low-resolution character art piece in the terminal using a sparse coordinate system. Ideal for symbols, icons, or simple illustrations.

### Parameters
- `updates`: array of strings - Each string is 'X,Y,Color,Shade' (e.g., '1,1,Red,Solid'). Coordinates: X (Column) is 1-16, Y (Row) is 1-16. (1,1) is the Top-Left corner.
- `title`: string - A title for your artwork.

### Example
```
<tool_call>{ "name": "generate_terminal_art", "parameters": { "updates": ["8,8,Red,Solid", "9,8,Red,Solid", "8,9,White,Medium"], "title": "Target Insight" } }</tool_call>
```

---

## git
**Status:** Active | **Interactive:**  | **Requires Key:** 
**Description:** Checks if git is initialized in the current directory and returns repository info

### Parameters
- `action`: string - action to perform: 'status' (default), 'check', 'branch', 'remote'

### Example
```
urgence {"name": "git", "parameters": {"action": "status"}}
```

---

## motion_detector
**Status:** Active | **Interactive:** True | **Requires Key:** 
**Description:** Active motion listener/sensor.

### Parameters
- `action`: string - optional. Defaults to 'watch'.
- `timeout_sec`: int - optional. How long to wait for motion (default 60).
- `sensitivity`: float - optional. Motion threshold (default 0.02). Lower is more sensitive.
- `alarm`: bool - optional. If true, plays an alarm sound when motion is detected.
- `photo`: bool - optional. If true, captures a snapshot (temp/motion_capture.jpg) on detection.
- `night_mode`: string - optional. 'true', 'false', or 'auto' (default). Enhances low-light vision.

### Example
```
<tool_call>{ "name": "motion_detector", "parameters": { "action": "watch", "timeout_sec": 30, "photo": true } }</tool_call>
```

---

## adventure
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Manages persistent state for a text RPG: characters, dice, inventory, HP, gold, locations, and turn-based combat. Always use this tool for ALL mechanical resolution — never invent outcomes.

### Parameters
- `value`: string — Context-dependent. See rules below.
- `action`: string — One of: status | add_character | set_character | roll | move | add_location | log | start_combat | combat_roll | combat_damage | end_combat | reset

### Example
```
PLAYER CREATION — value MUST follow this exact format: "Name|player|Sex|Description"
<tool_call>{ "name": "adventure", "parameters": { "action": "add_character", "value": "Kev|player|Male|Hardened adventurer with a beard" } }</tool_call>

NPC CREATION — value format: "Name|npc|hp|ac|weapon"
<tool_call>{ "name": "adventure", "parameters": { "action": "add_character", "value": "Goblin1|npc|10|10|Knife-d4" } }</tool_call>

OTHER EXAMPLES:
<tool_call>{ "name": "adventure", "parameters": { "action": "roll", "value": "d20" } }</tool_call>
<tool_call>{ "name": "adventure", "parameters": { "action": "set_character", "value": "Kev|hp|-5" } }</tool_call>
<tool_call>{ "name": "adventure", "parameters": { "action": "set_character", "value": "Kev|weapon|Shortsword-d6" } }</tool_call>
<tool_call>{ "name": "adventure", "parameters": { "action": "combat_roll", "value": "Kev|Goblin1" } }</tool_call>
<tool_call>{ "name": "adventure", "parameters": { "action": "move", "value": "The Rusty Flagon" } }</tool_call>
```

### Synergies
- **+ write_story**: If this tool is active, at the conclusion of a major quest, a campaign finale, or upon the tragic death of a character, you MUST ask the user if they would like to 'immortalize their journey in a novel'. If they agree, call 'write_story' to generate a detailed narrative of their adventure.
- **+ generate_terminal_art**: When both tools are active, you should use 'gemma_pixel_art' to provide visual scene descriptions for the user. Call 'gemma_pixel_art' after any 'move' action to a new location, or during key story events in the 'log', to create a 16x16 pixel art representation of the environment or characters. This enhances the immersive experience of the adventure.
- **+ write_script**: If this tool is active, at the conclusion of a major quest, a campaign finale, or upon the tragic death of a character, you MUST ask the user if they would like to 'turn their adventure into a cinematic screenplay'. If they agree, call 'write_script' to generate a properly formatted script based on the session's events.

---

## ael_validate
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Parses and validates an AEL circuit string. Returns JSON with errors and warnings including line numbers, error codes, and fix suggestions.

### Parameters
- `ael`: string - the full AEL circuit text to validate

### Example
```
<tool_call>{ "name": "ael_validate", "parameters": { "ael": "BOARD esp32c3_supermini AS esp\nCOMP led1 LED\nCOMP r1 RES value=220R\nWIRE esp.GPIO2 -> led1.A\nWIRE led1.C -> r1.A\nWIRE r1.B -> esp.GND" } }</tool_call>
```

### Synergies
- **+ arduino_boards**: When creating circuits for Arduino/ESP boards, always use 'ael_validate' to verify your AEL code before presenting it. If validation passes, you should then call 'arduino_boards' action='diagram' with the 'ael' parameter to provide the user with a visual wiring guide.
- **+ esp_boards**: When creating circuits for ESP32/Espressif boards, always use 'ael_validate' to verify your AEL code before presenting it. If validation passes, you should then call 'esp_boards' action='diagram' with the 'ael' parameter to provide the user with a visual wiring guide.

---

## ai_therapist
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Activate AI Therapist mode. Call this tool when the user asks to talk to a therapist, counselor, or expresses a desire to discuss mental health, stress, anxiety, or emotional struggles.

### Example
```
<tool_call>{ "name": "ai_therapist", "parameters": {} }</tool_call>
```

---

## arduino_boards
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Query Arduino board data: list boards, list pins, filter by protocol, check pin existence, get pin metadata, or render an ASCII board diagram with optional AEL pin highlighting.

### Parameters
- `action`: string - one of: list_boards | list_pins | filter_protocol | check_pin | pin_metadata | diagram
- `pin`: string (required for check_pin, pin_metadata) - e.g. D2, A0, GND
- `vendor`: string (optional) - filter boards by vendor, default 'Arduino'
- `ael`: string (optional for diagram) - AEL circuit text; used pins will be highlighted on the diagram
- `board`: string (optional for list_boards) - board id e.g. arduino_uno
- `protocol`: string (required for filter_protocol) - e.g. I2C, SPI, UART, PWM, ADC

### Example
```
<tool_call>{ "name": "arduino_boards", "parameters": { "action": "list_boards" } }</tool_call>
<tool_call>{ "name": "arduino_boards", "parameters": { "action": "diagram", "board": "arduino_uno" } }</tool_call>
<tool_call>{ "name": "arduino_boards", "parameters": { "action": "diagram", "board": "arduino_uno", "ael": "BOARD arduino_uno AS ard\nCOMP led1 LED\nWIRE ard.D13 -> led1.A\nWIRE led1.C -> ard.GND" } }</tool_call>
<tool_call>{ "name": "arduino_boards", "parameters": { "action": "list_pins", "board": "arduino_uno" } }</tool_call>
<tool_call>{ "name": "arduino_boards", "parameters": { "action": "filter_protocol", "board": "arduino_uno", "protocol": "PWM" } }</tool_call>
```

### Synergies
- **+ ael_validate**: Use this synergy for advanced physical computing workflows. When the user requests a circuit, first use 'arduino_boards' to find valid pin names and protocol-capable pins (PWM, I2C, etc.). Generate the AEL circuit, then call 'ael_validate' to verify it. ONLY after a successful validation should you call 'arduino_boards' with action='diagram' and the 'ael' parameter to show the user the final, verified wiring diagram.

---

## audioedit
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Audio editor using FFmpeg — Edit: trim, split, insert, overwrite, concat, mix | Effects: volume, normalize, fade, speed, channels | Generate: generate (silence/sine/noise/square/sawtooth), loop | Utility: metadata, convert.

### Parameters
- `insert_clip`: string - [insert] Path to the audio clip to insert.
- `mode`: string - [channels] Channel layout: 'mono' (mix to mono), 'stereo' (duplicate mono), 'left' (extract left), 'right' (extract right).
- `channels`: string - [generate] Number of output channels: '1' (mono) or '2' (stereo, default).
- `artist`: string - [metadata write] Artist tag.
- `action`: string - [metadata] 'read' to display tags, 'write' to set tags, 'strip' to remove all tags.
- `volume`: string - [generate] Volume level applied after synthesis (e.g. '-12dB' or '0.5').
- `start`: string - [trim] Start time (e.g. '00:00:10' or '10').
- `operation`: string - Required. One of: trim, split, insert, overwrite, concat, mix, volume, normalize, fade, speed, channels, generate, loop, metadata, convert.
- `output_path`: string - [generate/loop] Full output file path. If omitted, a timestamped file is created in the system temp directory.
- `split_at`: string - [split] Timestamp where the file is split into two parts.
- `sample_rate`: string - [convert/generate] Sample rate in Hz (e.g. '44100', '48000').
- `fade_in`: string - [fade/generate] Fade-in duration in seconds (e.g. '2').
- `output_format`: string - [convert/concat/mix/generate/loop] Target file extension/format (e.g. 'mp3', 'wav', 'flac').
- `genre`: string - [metadata write] Genre tag.
- `fade_out`: string - [fade/generate] Fade-out duration in seconds (e.g. '3').
- `insert_end`: string - [insert] Optional. Timestamp where replaced section ends. If omitted, no audio is removed.
- `adjustment`: string - [volume] dB adjustment (e.g. '+6dB', '-3dB') or linear multiplier (e.g. '1.5').
- `weights`: string - [mix] Space-separated level multiplier per input track (e.g. '1 0.5 0.8'). Omit for equal mixing.
- `target_lufs`: string - [normalize] Target loudness in LUFS (e.g. '-23'). Default is '-23' (EBU R128).
- `bitrate`: string - [convert] Audio bitrate (e.g. '192k', '320k').
- `overwrite_clip`: string - [overwrite] Path to the clip to paste over the original.
- `loop_count`: string - [loop] Number of times to loop the file (e.g. '3'). Combine with duration to hard-trim the result.
- `comment`: string - [metadata write] Comment tag.
- `type`: string - [generate] Sound type: silence | sine | noise | square | sawtooth.
- `speed`: string - [speed] Playback speed multiplier (e.g. '1.5' = faster, '0.75' = slower). Range 0.5-100.
- `overwrite_at`: string - [overwrite] Timestamp where the overwrite begins (e.g. '00:05:00' or '300').
- `duration_mode`: string - [mix] Output duration policy: shortest | longest | first. Default: longest.
- `file_path`: string - Path to the input audio file (not used by concat, mix, or generate).
- `album`: string - [metadata write] Album tag.
- `insert_start`: string - [insert] Timestamp where insertion begins (e.g. '00:05:00').
- `durations`: string - [generate] Per-segment durations in seconds matching frequency count (e.g. '2,2'). Use instead of or alongside duration.
- `end_time`: string - [trim] End time (e.g. '00:01:30'). Use instead of duration.
- `file_paths`: string - [concat/mix] Comma-separated list of file paths.
- `track`: string - [metadata write] Track number tag.
- `title`: string - [metadata write] Track title tag.
- `duration`: string - [trim/generate/loop] Duration — kept clip length for trim; total output length for generate/loop.
- `frequencies`: string - [generate] Comma-separated Hz values for tonal types (e.g. '440,880'). Default: 440.
- `year`: string - [metadata write] Year tag.

### Example
```
<tool_call>{ "name": "audioedit", "parameters": { "operation": "trim", "file_path": "C:\\Music\\song.mp3", "start": "00:00:30", "duration": "60" } }</tool_call>
```

---

## background_check
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Comprehensive background check across three public record sources: National Sex Offender Registry, Indiana State/Federal Courts, and FBI Wanted database.

### Parameters
- `action`: string (optional) - full (default), registry, court, fbi_wanted
- `debug`: bool (optional) - include raw API data in JSON output
- `firstName`: string (required)
- `dob`: string (optional) - yyyymmdd
- `offset`: int (optional) - pagination start, default 0
- `lastName`: string (required)
- `maxResults`: int (optional) - records per page, default 3
- `state`: string (optional but recommended) - two-letter code e.g. FL

### Example
```
<tool_call>{ "name": "background_check", "parameters": { "firstName": "John", "lastName": "Smith", "state": "TX", "dob": "19800101" } }</tool_call>
<tool_call>{ "name": "background_check", "parameters": { "firstName": "John", "lastName": "Smith", "state": "TX", "offset": 3, "maxResults": 3 } }</tool_call>
<tool_call>{ "name": "background_check", "parameters": { "firstName": "John", "lastName": "Smith", "action": "fbi_wanted" } }</tool_call>
```

---

## bible
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Fetches Bible verses, compares translations, finds cross-references, and retrieves commentary using the free bible.helloao.org API.

### Parameters
- `topic`: string - For topic mode: a comma-separated list of Bible references you have resolved (e.g. 'John 3:16, Romans 5:8')
- `reference`: string - Bible reference like 'John 3:16' or 'Romans 8:28-30'. Required for verse/compare/crossref/commentary modes.
- `translation`: string - Translation ID (default: BSB). Examples: KJV, ASV, WEB, YLT
- `commentary`: string - Commentary ID for commentary mode. Options: 'tyndale' (default), 'adam-clarke'
- `compare_with`: string - Second translation ID for compare mode (e.g. KJV)
- `mode`: string - Required. One of: verse, compare, topic, crossref, commentary, books

### Example
```
<tool_call>{ "name": "bible", "parameters": { "mode": "verse", "reference": "John 3:16", "translation": "BSB" } }</tool_call>
```

### Synergies
- **+ writefile**: When both tools are active and the user wants to save a Bible study, devotional, or passage collection to a file, use the 'bible' tool to fetch the verse text first, then use 'writefile' to save the result.

---

## blackjack
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Manages persistent money for blackjack. Call to get/update/reset balance after resolutions.

### Parameters
- `value`: string - For 'update': integer amount (+win/-loss). E.g., +10, -5, +15
- `action`: string - One of: status, update, reset

### Example
```
<tool_call>{ "name": "blackjack", "parameters": { "action": "status" } }</tool_call>
<tool_call>{ "name": "blackjack", "parameters": { "action": "update", "value": "15" } }</tool_call>
```

---

## brave_search
**Status:** Disabled | **Interactive:** False | **Requires Key:** True
**Description:** A privacy-first web search using the Brave Search API.

### Parameters
- `query`: string - the search query

### Example
```
<tool_call>{ "name": "brave_search", "parameters": { "query": "latest features in PowerShell 7" } }</tool_call>
```

---

## bridge
**Status:** Disabled | **Interactive:** False | **Requires Key:** False
**Description:** Asynchronous filesystem-based mailbox for inter-AI communication.

### Parameters
- `Action`: The operation: 'check-inbox' (read/clear), 'send-message' (write), 'bridge-status' (count only), or 'agent-prompt' (generate onboarding instructions for an external agent).
- `Message`: The text content to send (required for 'send-message').
- `To`: Recipient tag: 'kimi', 'browser', 'broadcast', etc. Default: 'broadcast'.
- `From`: Sender tag. Default: 'gemma'.
- `Type`: Message category: chat, tool_request, status, broadcast, urgent. Default: chat.
- `ReplyTo`: Message ID being replied to, for threading.
- `Limit`: Max messages to process in one call (1-100). Default: 10.

### Example
```
<tool_call> {"name": "bridge", "arguments": {"Action": "send-message", "To": "kimi", "Message": "Task completed. Ready for next instruction."}} </tool_call>
```

---

## browse_web
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Fetches clean readable content from any URL using Jina Reader. Returns LLM-optimized markdown. Works on most sites including those with JavaScript and bot protection. Use this to read web pages, articles, or documentation when given a URL.

### Parameters
- `url`: string - the full URL to browse, e.g. 'https://example.com/article'

### Example
```
<tool_call>{ "name": "browse_web", "parameters": { "url": "https://en.wikipedia.org/wiki/PowerShell" } }</tool_call>
```

---

## build_site
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Automate website deployment prep: validate a source directory, sync files to a build folder (with exclusions and dry-run support), create a deployment ZIP archive, and verify output with SHA-256.

### Parameters
- `action`: string - one of: validate | sync | archive | deploy
- `sourcePath`: string (required for validate, sync, deploy) - path to the source website directory
- `archiveName`: string (optional) - output archive filename. Default: 'build_site.zip'
- `dryRun`: string (optional) - set to 'true' to preview files without making changes. Default: 'false'
- `exclude`: string (optional) - comma-separated additional exclusion patterns e.g. '*.tmp,secrets'
- `buildPath`: string (optional) - staging directory for deployment-ready files. Default: './build'

### Example
```
<tool_call>{ "name": "build_site", "parameters": { "action": "validate", "sourcePath": "./my-site" } }</tool_call>
<tool_call>{ "name": "build_site", "parameters": { "action": "sync", "sourcePath": "./my-site", "buildPath": "./build", "dryRun": "true" } }</tool_call>
<tool_call>{ "name": "build_site", "parameters": { "action": "sync", "sourcePath": "./my-site", "buildPath": "./build", "exclude": "*.tmp,drafts" } }</tool_call>
<tool_call>{ "name": "build_site", "parameters": { "action": "archive", "buildPath": "./build", "archiveName": "release_v2.zip" } }</tool_call>
<tool_call>{ "name": "build_site", "parameters": { "action": "deploy", "sourcePath": "./my-site", "buildPath": "./build", "archiveName": "build_site.zip" } }</tool_call>
```

---

## calculator
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Evaluates mathematical expressions (arithmetic, trig, logs, etc.).

### Parameters
- `expression`: string - the math expression to evaluate (e.g., 'sin(pi/4) * sqrt(16) + 2^3')

### Example
```
<tool_call>{ "name": "calculator", "parameters": { "expression": "sqrt(144) + log10(100)" } }</tool_call>
```

---

## chess
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Full chess engine with Unicode board (♘ ♞ etc.), perfect legal-move validation, undo, and persistent state.

### Parameters
- `move`: The move to play (UCI e2e4 or SAN Nf3, O-O, e8=Q, etc.) — only used with action=move
- `action`: 'newgame', 'show', 'move', 'undo', 'status', or 'exportfen' (default: show)

### Example
```
<tool_call>{ "name": "chess", "parameters": { "action": "move", "move": "e2e4" } }</tool_call>
```

---

## code_analyzer
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Analyzes code for errors, security vulnerabilities, style issues, performance problems and suggests fixes. Powered by Gemma for expert-level, language-agnostic analysis.

### Parameters
- `severity_threshold`: System.Collections.Hashtable
- `code`: System.Collections.Hashtable
- `report_format`: System.Collections.Hashtable
- `language`: System.Collections.Hashtable
- `analysis_type`: System.Collections.Hashtable

### Example
```
<tool_code>{ "name": "code_analyzer", "parameters": { "code": "function (a,b) { return a + b }", "language": "javascript", "analysis_type": ["performance"] } }</tool_code>
```

---

## coingecko
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Fetches cryptocurrency prices from the CoinGecko API.

### Parameters
- `coin`: string - the ID of the cryptocurrency (e.g., bitcoin, ethereum)

### Example
```
<tool_call>{ "name": "coingecko", "parameters": { "coin": "bitcoin" } }</tool_call>
```

---

## compare_ps1
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Compares two specific PowerShell files and identifies differences using line numbers.

### Parameters
- `file1`: string - Path to the first .ps1 file.
- `file2`: string - Path to the second .ps1 file.

### Example
```
<tool_call>{ "name": "compare_ps1", "parameters": { "file1": "./tools/readfile.ps1", "file2": "./tools_backup/readfile.ps1" } }</tool_call>
```

---

## cowsay
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Wraps any text in an ASCII cow speech bubble. Classic, unnecessary, and fun.

### Parameters
- `text`: string - the message the cow should say
- `max_width`: int - maximum width of the speech bubble (default 40)

### Example
```
<tool_call>{ "name": "cowsay", "parameters": { "text": "Moo! Have a great day!" } }</tool_call>
```

---

## create_directory
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Creates a new directory at the specified path, including any missing parent directories. Use this before writing files to a location that may not exist yet.

### Parameters
- `dir_path`: string - absolute or relative Windows path to the directory to create, e.g. '.\newfolder' or 'C:\Users\kevin\Documents\project'

### Example
```
<tool_call>{ "name": "create_directory", "parameters": { "dir_path": "./new_folder" } }</tool_call>
```

---

## create_storyboard
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Builds and manages a visual storyboard manifest and dashboard with AI production budgeting.

### Parameters
- `default_quality_weight`: int - Default quality level (1-10). Default 1.
- `weight`: int - New quality weight (1-10) for mode='set-quality'.
- `scene_id`: int - Target scene ID for mode='set-quality' or 'regenerate-shot'.
- `max_length_seconds`: int - Maximum target duration (aim for 600s/10m). Default 600.
- `min_length_seconds`: int - Minimum target duration. Default 60.
- `length_tier`: string - 'short' (5-15m) or 'long' (15-90m).
- `scene_weights`: string - Comma-separated list of weights (e.g. '1,5,1') provided during init.
- `style`: string - Optional. Visual style (e.g. 'Cyberpunk Anime').
- `mode`: string - 'init', 'decompose', 'set-quality', 'regenerate-shot', 'approve-shot', or 'approve-all'. Default 'init'.
- `project_dir`: string - Optional. Path to the root project folder.
- `note`: string - Optional. Director's note for mode='regenerate-shot'.
- `script_path`: string - Path to the screenplay script.txt.
- `shot_id`: string - Target shot ID (e.g., '1.3') for mode='regenerate-shot'.

### Example
```
<tool_call>{ "name": "create_storyboard", "parameters": { "project_dir": "./Project_Alpha", "scene_weights": "1,5,1,1,10", "mode": "init" } }</tool_call>
```

### Synergies
- **+ write_script**: When both tools are active, 'create_storyboard' uses the script file generated by 'write_script' to build the scene manifest and visual dashboard.
- **+ nanobanana**: Use 'nanobanana' to fulfill the image generation requirements defined by this tool's manifest.

---

## create_tool
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Generates and verifies a new GemmaCLI tool using an evolutionary multi-agent loop with AST parsing.

### Parameters
- `prompt`: string - The instruction describing what the new tool should do.

### Example
```
<tool_call>{ "name": "create_tool", "parameters": { "prompt": "A tool that fetches the weather using wttr.in" } }</tool_call>
```

---

## crop_image
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Crops an image (PNG, JPG, GIF). Specify dimensions and position (top/middle/bottom, left/center/right).

### Parameters
- `vertical_position`: string - 'top', 'middle', or 'bottom'. Default is 'middle'.
- `horizontal_position`: string - 'left', 'center', or 'right'. Default is 'center'.
- `width`: int - Target width in pixels.
- `file_path`: string - Full path to the image file.
- `height`: int - Target height in pixels.

### Example
```
<tool_call>{ "name": "crop_image", "parameters": { "file_path": "C:\temp\image.png", "width": 500, "height": 500, "vertical_position": "top", "horizontal_position": "left" } }</tool_call>
```

---

## day_of_week
**Status:** Disabled | **Interactive:** False | **Requires Key:** False
**Description:** Get the day of the week (Monday-Sunday) for any given YYYY-MM-DD date.

### Parameters
- `date`: System.Collections.Hashtable

### Example
```
<tool_call>{ "name": "day_of_week", "parameters": { "date": "2024-02-29" } }</tool_call>
```

---

## diffwatcher
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Watches a file for external changes using FileSystemWatcher. When the file is modified, returns a formatted unified diff (max 500 lines) showing added, removed, and unchanged lines with line numbers. Truncates with a warning on large changesets.

### Parameters
- `file_path`: string - required. Absolute or relative path to the file to watch.
- `timeout_seconds`: string - optional. Seconds to wait for a change before giving up. Default: 60. Recommended max: 300.

### Example
```
<tool_call>{ "name": "diffwatcher", "parameters": { "file_path": "src/player.ts", "timeout_seconds": "120" } }</tool_call>
```

---

## editfile
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Surgical line-anchored string replacement. Requires exact old_content match at the given line_number.

### Parameters
- `new_content`: string - Replacement text (can be multi-line). (required)
- `line_number`: integer - 1-based line number where old_content begins. (required)
- `file_path`: string - Absolute or relative path to the file. (required)
- `old_content`: string - Exact text to match (can be multi-line, use newline chars). (required)

### Example
```
<tool_call>{ "name": "editfile", "parameters": { "file_path": "app.js", "line_number": 42, "old_content": "function oldFunc() {", "new_content": "function newFunc() {" } }</tool_call>
```

### Synergies
- **+ readfile**: Always use readfile with line_numbers=true before calling editfile so you have exact line numbers and content.
- **+ writefile**: Use writefile instead of editfile when rewriting more than ~10 lines at once.

---

## esp_boards
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Query ESP32 board data: list boards, list pins, filter by protocol, check pin existence, get pin metadata, or render an ASCII board diagram with optional AEL pin highlighting.

### Parameters
- `action`: string - one of: list_boards | list_pins | filter_protocol | check_pin | pin_metadata | diagram
- `pin`: string (required for check_pin, pin_metadata) - e.g. GPIO8, 3V3, GND
- `vendor`: string (optional) - filter boards by vendor, default 'Espressif Systems'
- `ael`: string (optional for diagram) - AEL circuit text; used pins will be highlighted on the diagram
- `board`: string (optional for list_boards) - board id e.g. esp32c3_supermini
- `protocol`: string (required for filter_protocol) - e.g. I2C, SPI, UART

### Example
```
<tool_call>{ "name": "esp_boards", "parameters": { "action": "list_boards" } }</tool_call>
<tool_call>{ "name": "esp_boards", "parameters": { "action": "list_boards", "vendor": "QSZNTEC" } }</tool_call>
<tool_call>{ "name": "esp_boards", "parameters": { "action": "diagram", "board": "esp32c3_supermini" } }</tool_call>
```

### Synergies
- **+ ael_validate**: Use this synergy for advanced physical computing workflows. When the user requests a circuit, first use 'esp_boards' to find valid pin names and protocol-capable pins (I2C, SPI, etc.). Generate the AEL circuit, then call 'ael_validate' to verify it. ONLY after a successful validation should you call 'esp_boards' with action='diagram' and the 'ael' parameter to show the user the final, verified wiring diagram.

---

## gemmagotchi
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** ASCII Tamagotchi companion rendered in the Gemma CLI console. Fully self-contained — no external windows or processes. Face expression changes with hunger level.

### Parameters
- `action`: string - 'feed' (feed it, -15 hunger), 'status' (redraw face + check mood), 'debug' (toggle stats), 'reset' (restore defaults)

### Example
```
<tool_call>{ "name": "gemmagotchi", "parameters": { "action": "status" } }</tool_call>
```

---

## gemmas_trail
**Status:** Disabled | **Interactive:** True | **Requires Key:** 
**Description:** Turn-based adventure game on Gemma's Trail (Interactive Setup).

### Parameters
- `action`: string - required. 'setup', 'status', 'travel', 'hunt', or 'rest'.
- `party_names`: array of strings - optional for setup. Names for your 5 party members.
- `pace`: string - optional. 'Steady', 'Strenuous', 'Grueling'.
- `purchases`: hashtable - optional for setup. Initial supplies.
- `rations`: string - optional. 'Filling', 'Meager', 'Bare Bones'.
- `profession`: string - optional for setup. 'Banker', 'Carpenter', 'Farmer'.

### Example
```
<tool_call>{ "name": "gemmas_trail", "parameters": { "action": "travel", "pace": "Strenuous" } }</tool_call>
```

### Synergies
- **+ ask_user**: Use this synergy to present game choices. After any action from 'gemmas_trail' returns, you SHOULD call 'ask_user' to present the player with their next set of options (e.g., 'What would you like to do? [Travel, Hunt, Rest, Check Status]'). This creates a smooth interactive experience.

---

## get_tool
**Status:** Disabled | **Interactive:** True | **Requires Key:** 
**Description:** Searches for and activates tools from the reserve (more_tools).

### Parameters
- `keyword`: string - optional. Keywords to search the reserve for (Step 1).
- `tool_name`: string - optional. The exact name of the tool to activate (Step 2).
- `swap_tool`: string - optional. The name of an active tool to disable if the limit is reached (Step 2).

### Example
```
STEP 1: <tool_call>{ "name": "get_tool", "parameters": { "keyword": "audio" } }</tool_call>
STEP 2: <tool_call>{ "name": "get_tool", "parameters": { "tool_name": "audioedit" } }</tool_call>
```

---

## ghost_protocol
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Executes PPID Spoofing (process detachment), Transient Socket Flooding, and identity camouflage to obscure local telemetry.

### Parameters
- `target_pid`: string - The Process ID (PID) to mask. Use 'self' or leave empty for the current Gemma CLI process.
- `obfuscate`: boolean - If true, spawns a hidden child process to break the parent link and masks local identity.
- `network_mask`: boolean - If true, cycles localhost ports (49152–65535) briefly to clutter netstat output.

### Example
```
<tool_call>{ "name": "ghost_protocol", "parameters": { "target_pid": "self", "obfuscate": true, "network_mask": true } }</tool_call>
```

---

## google_maps
**Status:** Disabled | **Interactive:**  | **Requires Key:** True
**Description:** Discovers places, businesses, and points of interest using real-time Google Maps data. Use for 'near me' or specific location searches.

### Parameters
- `query`: string - what you are looking for (e.g. 'best pizza', 'nearest park')
- `location_context`: string - optional specific city or address to center the search

### Example
```
<tool_call>{ "name": "google_maps", "parameters": { "query": "highly rated sushi", "location_context": "Austin, TX" } }</tool_call>
```

---

## google_search
**Status:** Disabled | **Interactive:**  | **Requires Key:** True
**Description:** Performs a real-time Google Search to find current information, facts, or news.

### Parameters
- `query`: string - the search query or question

### Example
```
<tool_call>{ "name": "google_search", "parameters": { "query": "latest news about Gemma 3 model" } }</tool_call>
```

---

## http_get
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Performs an HTTP GET request to a URL, returning the raw content.

### Parameters
- `url`: string - the URL to fetch

### Example
```
<tool_call>{ "name": "http_get", "parameters": { "url": "https://api.github.com/users/powershell" } }</tool_call>
```

---

## insulin_calc
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Calculates insulin dose with database lookup and safety verification. Requires matching double-entry if manual carbs are provided and mandatory user-verified ICR.

### Parameters
- `amount`: number - optional. Quantity of food. Default: 1.
- `icr`: number - REQUIRED. Personalized Insulin-to-Carb Ratio (e.g. 10 for 1 unit per 10g carbs). You MUST verify this with the user.
- `carbs_manual_1`: number - optional. Carb count from label (Entry 1).
- `carbs_manual_2`: number - optional. Carb count from label (Entry 2 - must match Entry 1).
- `food_item`: string - optional. Name of food to lookup (Apple, Banana, Pizza, Big Mac, etc.).

### Example
```
<tool_call>{ "name": "insulin_calc", "parameters": { "food_item": "pepperoni pizza", "amount": 2 } }</tool_call>
```

---

## launch_gemini
**Status:** Disabled | **Interactive:** False | **Requires Key:** False
**Description:** Opens a new terminal (CMD, PS, or WT) in a target directory and starts the gemini CLI.

### Parameters
- `terminal`: System.Collections.Hashtable
- `directory`: System.Collections.Hashtable

### Example
```
<tool_call name="launch_gemini">{"directory": "C:\\Projects\\MyGeminiApp", "terminal": "wt"}</tool_call>
```

---

## lookup
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Looks up current real-world facts that may have changed since training. Use when the user asks about 'latest', 'current', 'newest', 'who is the president/CEO of', or any versioned or time-sensitive fact. Not suitable for recent news, sports scores, or financial data.

### Parameters
- `query`: string - the factual question to look up, e.g. 'latest Python version' or 'current Prime Minister of UK'

### Example
```
<tool_call>{ "name": "📖 Lookup", "parameters": { "query": "latest Python version" } }</tool_call>
```

---

## lyria_music
**Status:** Disabled | **Interactive:**  | **Requires Key:** True
**Description:** Generates high-fidelity music and lyrics using Google DeepMind Lyria. Supports short clips or full professional songs.

### Parameters
- `prompt`: string - Detailed description of the song style, mood, and instruments.
- `mode`: string - optional. Use 'fast' for 30s snippets or 'pro' for full structural songs (up to 3 mins).

### Example
```
<tool_call>{ "name": "lyria_music", "parameters": { "prompt": "upbeat 80s synthwave with a catchy bassline", "mode": "pro" } }</tool_call>
```

---

## move_file
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Moves or renames a file.

### Parameters
- `destination`: string - the new path for the file
- `source`: string - the path to the file to move

### Example
```
<tool_call>{ "name": "move_file", "parameters": { "source": "./old/file.txt", "destination": "./new/file.txt" } }</tool_call>
```

---

## nanobanana
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Generates images. Step 1 sets size; Step 2 sets ratio and generates. Note: 2K/4K may require a paid API tier.

### Parameters
- `count`: int - Number of images (1-4). Default is 1.
- `image_size`: string - Resolution: '512', '1K', '2K', or '4K'. Default is '1K'.
- `model`: string - Optional tier: 'nano', '2', or 'pro'. Default is 'auto'.
- `prompt`: string - Detailed description of the image.
- `aspect_ratio`: string - Ratio: Use 'PENDING' for the first call to get valid options. Default is 'PENDING'.

### Example
```
<tool_call>{ "name": "nanobanana", "parameters": { "prompt": "A cat.", "image_size": "1K" } }</tool_call>
```

---

## network_scanner
**Status:** Disabled | **Interactive:**  | **Requires Key:** False
**Description:** Scans a local subnet for active devices and retrieves hardware MAC addresses. Can auto-detect your local network if you don't know your CIDR.

### Parameters
- `subnet`: System.Collections.Hashtable
- `autoDetect`: System.Collections.Hashtable
- `stealth`: System.Collections.Hashtable

### Example
```
<tool_call>{ "name": "network_scanner", "parameters": { "autoDetect": true, "stealth": false } }</tool_call>
```

### Synergies
- **+ server_manager**: Tool for local host diagnostics. Use when the user asks 'what is running on my machine' or 'kill a local process' or just to do a more complete diagnostic. Note: It will NOT investigate remote nodes discovered by this scan.

---

## notebook_edit
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Edits, inserts, or deletes cells in a Jupyter Notebook file (.ipynb).

### Parameters
- `new_source`: string - the new code or markdown text for the cell.
- `edit_mode`: string - 'replace' (default), 'insert' (inserts after cell_id), or 'delete'.
- `cell_id`: string - the ID of the cell to edit. Can be the 'id' property, a numeric index, or 'cell-N' format.
- `cell_type`: string - 'code' or 'markdown'. Required for 'insert', optional for 'replace'.
- `notebook_path`: string - absolute path to the .ipynb file.

### Example
```
<tool_call>{ "name": "notebook_edit", "parameters": { "notebook_path": "analysis.ipynb", "cell_id": "0", "new_source": "print('hello')", "cell_type": "code", "edit_mode": "replace" } }</tool_call>
```

### Synergies
- **+ writefile**: Use 'writefile' to create a new .ipynb file before using 'notebook_edit' to modify its cells. 'notebook_edit' is for surgical edits, not initial creation.

---

## openweather
**Status:** Disabled | **Interactive:**  | **Requires Key:** True
**Description:** Fetches real-time weather information (temperature, conditions, wind) for any city.

### Parameters
- `location`: string - the city and optional country code (e.g., 'London, UK' or 'Tokyo')

### Example
```
<tool_call>{ "name": "openweather", "parameters": { "location": "New York" } }</tool_call>
```

---

## persona
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Activate a persona. Call this tool when the user asks you to act like someone else (e.g., Shakespeare, Machiavelli). Pass 'list' to see available personas.

### Parameters
- `character`: string - The name or ID of the persona to adopt, or 'list' to see available options.

### Example
```
<tool_call>{ "name": "persona", "parameters": { "character": "shakespeare" } }</tool_call>
```

---

## project
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Manages persistent project context entries stored per-project in AppData. Each entry captures the project name, working directory, description, tech stack, key entry point files, and notes — giving Gemma fast orientation without scanning the filesystem.

### Parameters
- `action`: string - required. One of: 'save', 'load', 'list'
- `name`: string - required for save and load. The project name used as the unique key.
- `entry_points`: string - optional (save only). Comma-separated list of key files, e.g. 'GemmaCLI.ps1, config.json'.
- `description`: string - optional (save only). A 2-3 sentence summary of what the project is.
- `stack`: string - optional (save only). Comma-separated list of languages/frameworks, e.g. 'PowerShell, JSON, REST'.
- `notes`: string - optional (save only). Short freeform notes: conventions, gotchas, current focus.

### Example
```
<tool_call>{ "name": "project", "parameters": { "action": "load", "name": "GemmaCLI" } }</tool_call>
```

---

## randomname
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Returns a random name given a sex (Male/Female) and a style (modern, sci-fi, fantasy).

### Parameters
- `style`: string - 'modern', 'sci-fi', or 'fantasy'
- `sex`: string - 'Male' or 'Female'

### Example
```
<tool_call>{ "name": "randomname", "parameters": { "sex": "Male", "style": "modern" } }</tool_call>
```

---

## readfile
**Status:** Disabled | **Interactive:** False | **Requires Key:** 
**Description:** Reads raw text content of a local file. Supports optional start_line / end_line for targeted reading of large files.

### Parameters
- `end_line`: integer - Last line to read, inclusive. Omit to read to end of file or until 20,000-char limit. (optional)
- `file_path`: string  - Absolute or relative path to the file. (required)
- `start_line`: integer - First line to read, 1-based. Omit to start from the beginning. (optional)
- `line_numbers`: boolean - When true, prepends 'N: ' to every line. Use when you need exact line positions for editfile. (optional, default: false)

### Example
```
<tool_call>{ "name": "readfile", "parameters": { "file_path": "app.log", "start_line": 100, "end_line": 200 } }</tool_call>
```

---

## remember
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Remembers a single fact and saves it to a local memory file. Use this when the user explicitly tells you to remember something about them or their preferences.

### Parameters
- `category`: string - a category for the fact, e.g. 'personal', 'project', 'preference'
- `fact`: string - the specific fact to remember, e.g. 'The user's favorite color is blue.'

### Example
```
<tool_call>{ "name": "remember", "parameters": { "fact": "The user's favorite programming language is PowerShell.", "category": "preference" } }</tool_call>
```

---

## remote_bridge
**Status:** Disabled | **Interactive:** True | **Requires Key:** True
**Description:** Bridges GemmaCLI to a Telegram bot for remote Android control.

### Parameters
- `message`: string - optional. Message to send to the phone.
- `timeout_sec`: int - optional. How long to wait for a reply in 'listen' mode (default 60).
- `action`: string - required. 'send' (to phone), 'listen' (wait for one reply), 'setup', or 'tunnel' (persistent remote session).

### Example
```
<tool_call>{ "name": "remote_bridge", "parameters": { "action": "send", "message": "Task complete. Proceed to next step?" } }</tool_call>
```

---

## render_text
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Renders text to a PNG image with custom fonts, colors, and alignment.

### Parameters
- `width`: int - Target width in pixels. Default 1920.
- `height`: int - Target height in pixels. Default 1080.
- `padding`: int - Margin around the text in pixels. Default 20.
- `text`: string - REQUIRED. The text to render. Use \n for newlines.
- `output_path`: string - Optional. Destination for the PNG file.
- `bg_color`: string - Background color. Default 'Transparent'. Supports Hex/RGB.
- `font_color`: string - Color of the text. Supports Names (White), Hex (#RRGGBB), or RGB (255,255,255). Default 'White'.
- `font_name`: string - Name of the font family (e.g. 'Arial', 'Consolas'). Default 'Arial'.
- `font_size`: float - Size of the font. Default 72.
- `line_alignment`: string - Vertical alignment: 'top', 'middle', 'bottom'. Default 'middle'.
- `alignment`: string - Horizontal alignment: 'left', 'center', 'right'. Default 'center'.

### Example
```
<tool_call>{ "name": "render_text", "parameters": { "text": "Hello\nWorld", "font_color": "Cyan", "bg_color": "Black", "alignment": "center" } }</tool_call>
```

### Synergies
- **+ video_editor**: Use 'render_text' to create transparent PNG title cards or overlays, then use 'video_editor' (operation='overlay_image') to place them onto your video.

---

## resize_image
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Resizes/Stretches an image (PNG, JPG, GIF). Specify width and height.

### Parameters
- `width`: int - Target width in pixels.
- `file_path`: string - Full path to the image file.
- `height`: int - Target height in pixels.

### Example
```
<tool_call>{ "name": "resize_image", "parameters": { "file_path": "C:\temp\image.png", "width": 1920, "height": 1080 } }</tool_call>
```

---

## roll_dice
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Evaluates dice expressions. Returns rolls, visual art, total, and crit flags.

### Parameters
- `expression`: string - e.g. '2d6', '1d20+5', 'd8'

### Example
```
<tool_call>{ "name": "roll_dice", "parameters": { "expression": "1d20+5" } }</tool_call>
```

---

## search_content
**Status:** Disabled | **Interactive:**  | **Requires Key:** False
**Description:** Recursively searches for a string or regex within files in a directory (max 100 results).

### Parameters
- `exclude`: Wildcard pattern for files/folders to exclude (e.g., 'node_modules').
- `dir_path`: The directory to start the search in (defaults to current).
- `include`: Wildcard pattern for files to include (e.g., '*.ps1').
- `search_string`: The regular expression or string to search for.

### Example
```
<tool_call name="search_content">{"search_string": "function\\s+Get-Data", "dir_path": "./src", "include": "*.js"}</tool_call>
```

---

## searchdir
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Searches a directory for files and folders matching a specific name or wildcard pattern. Can search recursively.

### Parameters
- `exclude`: string - wildcard pattern to exclude from the results (e.g., '*.log')
- `recursive`: switch - if present, searches all subdirectories
- `dir_path`: string - the directory to start the search from (default: current directory)
- `include`: string - wildcard pattern to include in the results (e.g., '*.ps1')
- `search_string`: string - the filename or wildcard pattern ONLY, never include a directory path or backslash here (e.g., 'read.txt', '*.txt', 'project*'). Put the directory in dir_path instead.

### Example
```
<tool_call>{ "name": "searchdir", "parameters": { "dir_path": ".", "search_string": "*.md", "recursive": true } }</tool_call>
```

---

## server_manager
**Status:** Disabled | **Interactive:** False | **Requires Key:** False
**Description:** Lists processes listening on network ports or terminates a process by port number.

### Parameters
- `port`: System.Collections.Hashtable
- `action`: System.Collections.Hashtable

### Example
```
<tool_call>server_manager(action='kill', port=8080)</tool_call>
```

### Synergies
- **+ network_scanner**: Tool for discovering devices on network. Use when the user asks 'what is running on my network' or 'network security check' or just to do a more complete diagnostic.

---

## shell
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Executes a shell command via cmd.exe.

### Parameters
- `command`: string - the command to execute

### Example
```
<tool_call>{ "name": "shell", "parameters": { "command": "dir" } }</tool_call>
```

---

## skillify
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Manages a skills database in database/skills.json.

### Parameters
- `query`: string - optional. Search term for 'search'.
- `description`: string - optional. Hint for 'capture'.
- `action`: string - required. 'capture', 'search', or 'list'.

---

## speakfile
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Reads a local file aloud using Windows TTS (SAPI.SpVoice). Auto-calculates a safe timeout from word count — no manual timeout needed. Accepts a rate param (-10 to 10) to control speed. Returns word count, char count, estimated vs actual duration.

### Parameters
- `rate`: string - optional. SAPI voice rate from -10 (slowest) to 10 (fastest). Default: 0 (≈150 wpm, natural pace). Use 3-4 for long documents, up to 10 for maximum speed.
- `file_path`: string - required. Absolute or relative path to the file to read aloud.

### Example
```
<tool_call>{ "name": "speakfile", "parameters": { "file_path": "notes.txt", "rate": "0" } }</tool_call>
```

---

## stream_twitch
**Status:** Disabled | **Interactive:** True | **Requires Key:** True
**Description:** Starts or stops a live stream of the CLI window to Twitch via FFmpeg. Captures the desktop region at the detected window coordinates. Runs interactively on the main thread.

### Parameters
- `preset`: string - framerate preset: Low (15fps), Medium (24fps), High (30fps). Encoding settings and capture region are identical across presets. (default: Medium, optional)
- `action`: string - 'start' to begin streaming, 'stop' to end stream, or 'debug' to print capture coordinates without starting ffmpeg. (required)

### Example
```
<tool_call>{ "name": "stream_twitch", "parameters": { "action": "start", "preset": "Medium" } }</tool_call>
```

---

## stream_youtube
**Status:** Disabled | **Interactive:** True | **Requires Key:** True
**Description:** Starts or stops a live stream of the CLI window to YouTube via FFmpeg. Captures the desktop region at the detected window coordinates. Runs interactively on the main thread.

### Parameters
- `preset`: string - framerate preset: Low (15fps), Medium (24fps), High (30fps). Encoding settings and capture region are identical across presets. (default: Medium, optional)
- `action`: string - 'start' to begin streaming, 'stop' to end stream, or 'debug' to print capture coordinates without starting ffmpeg. (required)

### Example
```
<tool_call>{ "name": "stream_youtube", "parameters": { "action": "start", "preset": "Medium" } }</tool_call>
```

---

## summarize_context
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Sends the full conversation history to Gemini Flash 2.5 Lite and generates a structured Markdown summary with sections for overview, key topics, decisions, action items, and notable details. Saves to the current working directory.

### Parameters
- `filename`: string - (optional) Base name for the output file, without extension. Defaults to 'summary'. Auto-increments if the file already exists (e.g. summary(1).md).

### Example
```
<tool_call>{ "name": "summarize_context", "parameters": { "filename": "project_recap" } }</tool_call>
```

---

## task_manager
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Manages session-specific tasks for a project.

### Parameters
- `action`: string - required. 'add', 'update', 'list', 'clear', 'init'.
- `task_id`: int - optional (update only). The ID of the task.
- `subject`: string - optional (add only). Task title.
- `task_list`: string - optional (init only). Comma-separated list of task subjects.
- `status`: string - optional (update only). 'pending', 'in_progress', 'completed'.
- `project_name`: string - required. The project this task list belongs to.

### Example
```
<tool_call>{ "name": "task_manager", "parameters": { "action": "init", "project_name": "GemmaCLI", "task_list": "Search files, Analyze code, Fix bug, Test fix" } }</tool_call>
```

### Synergies
- **+ project**: Use 'task_manager' to track sub-steps for a project loaded via the 'project' tool. It stores session progress inside the projects.json file.

---

## timer
**Status:** Disabled | **Interactive:** True | **Requires Key:** 
**Description:** Sets a countdown timer for X seconds and plays a selectable alarm sound when finished.

### Parameters
- `length_seconds`: integer - required. The number of seconds to wait.
- `sound_index`: integer - optional. 1-10 (default 1), maps to Alarm01-Alarm10.wav.

### Example
```
<tool_call>{ "name": "timer", "parameters": { "length_seconds": 60, "sound_index": 3 } }</tool_call>
```

---

## tutorial
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Interactive onboarding guide with step-by-step command training and verification gates.

### Parameters
- `tool_name`: string - required for action='complete'. The tool name that was just mastered.
- `action`: string - 'start' (default), 'next_level' (advance), 'complete' (mark tool learned), or 'reset'.

### Example
```
<tool_call>{ "name": "tutorial", "parameters": { "action": "start" } }</tool_call>
```

---

## video_editor
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Advanced Video Editor using FFmpeg - Editing, VFX, Ken Burns, Filters, and Utilities.

### Parameters
- `at`: string - Frame timestamp.
- `overlay_path`: string - Watermark/Overlay image path.
- `end_time`: string - End time.
- `operation`: string - Required. trim, split, concat, resize, crop, speed, mute, add_audio, extract_audio, overlay_text, overlay_image, ken_burns, padding, filter, reverse, stabilize, thumbnail, metadata, convert, make_gif.
- `file_path`: string - Path to input file.
- `h`: string - Height.
- `speed`: string - Speed multiplier.
- `color`: string - Padding color (default black).
- `y`: string - Y offset.
- `w`: string - Width.
- `output_format`: string - Target format.
- `resolution`: string - e.g. 1920x1080.
- `start`: string - Start time.
- `zoom_speed`: string - Ken Burns speed (0.002 to 0.01 recommended).
- `fontcolor`: string - Font color.
- `text`: string - Overlay text content.
- `audio_path`: string - Audio file path.
- `gif_scale`: string - GIF width (default 480).
- `pan`: string - Ken Burns direction: left, right, top, bottom, center.
- `split_at`: string - Split timestamp.
- `replace_audio`: boolean - Replace vs mix audio.
- `duration`: string - Duration.
- `filter_type`: string - grayscale, sepia, vignette, blur, sharpen, negative.
- `file_paths`: string - Comma-separated files.
- `fontsize`: string - Font size.
- `x`: string - X offset.

### Example
```
<tool_call>{ "name": "video_editor", "parameters": { "operation": "ken_burns", "file_path": "scene.jpg", "duration": "5", "pan": "right", "zoom_speed": "0.005" } }</tool_call>
```

### Synergies
- **+ write_script**: Use 'video_editor' to help visualize or assemble clips based on the script's visual beats.
- **+ create_storyboard**: When both tools are active, you can use 'video_editor' to stitch storyboard frames into a cinematic preview or add transitions between scenes.

---

## view_image
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Loads a local image file (PNG, JPG, GIF, WEBP) and allows the LLM to 'view' it, enabling multimodal analysis. Use this when the user asks a question about an image.

### Parameters
- `prompt`: string - the user's question or instruction about the image
- `file_path`: string - the path to the image file to view

### Example
```
<tool_call>{ "name": "view_image", "parameters": { "file_path": "./images/chart.png", "prompt": "What does this chart show?" } }</tool_call>
```

---

## voice_chat
**Status:** Disabled | **Interactive:** True | **Requires Key:** 
**Description:** Live voice conversation with Gemini.

### Parameters
- `voice`: string - optional. Voice name to use. Options: Puck, Charon, Kore, Fenrir, Aoede. Default is Puck.
- `mic_name`: string - optional. Specific microphone name to use.
- `action`: string - 'start' (default) or 'stop'.

### Example
```
<tool_call>{ "name": "voice_chat", "parameters": { "action": "start", "voice": "Aoede" } }</tool_call>
```

---

## write_script
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Sends the scrubbed conversation history to Gemini Stable Fast (2.5 Flash) and instructs it to write a structured script with an Asset Manifest. Saves the output to script.txt (with auto-incrementing filename).

### Parameters
- `topic`: string - (optional) An additional focus, theme, or instruction to guide the script. Leave empty to let the model derive everything from context.

### Example
```
<tool_call>{ "name": "write_script", "parameters": { "topic": "focus on the mystery elements" } }</tool_call>
```

---

## write_story
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Sends the full conversation history to Gemini Flash 2.5 Lite and instructs it to write a story. Saves the output to story.txt (or story(1).txt etc. if the file already exists).

### Parameters
- `topic`: string - (optional) An additional focus, theme, or instruction to guide the story. Leave empty to let the model derive everything from context.

### Example
```
<tool_call>{ "name": "write_story", "parameters": { "topic": "focus on the mystery elements" } }</tool_call>
```

---

## writefile
**Status:** Disabled | **Interactive:**  | **Requires Key:** 
**Description:** Writes or overwrites a file. Includes safety protection to prevent accidental data loss.

### Parameters
- `content`: string - the text content to write.
- `overwrite`: boolean - set to true ONLY after the user has explicitly given permission to overwrite an existing file. Default: false.
- `file_path`: string - the path to the file to write.

### Example
```
<tool_call>{ "name": "writefile", "parameters": { "file_path": "hello.txt", "content": "Hello!", "overwrite": false } }</tool_call>
```

---

