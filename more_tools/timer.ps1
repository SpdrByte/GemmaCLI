  # ===============================================
  # Gemma CLI - timer.ps1 v1.2.1
  # Responsibility: Simple countdown timer that plays a sound upon completion.
  #                 Runs in a loop to keep the GemmaCLI spinner active.
  # ===============================================


  function Invoke-TimerTool {
      param(
          [int]$length_seconds,
          [int]$sound_index = 1
      )

      if ($length_seconds -le 0) {
          return "ERROR: length_seconds must be a positive integer."
      }
      
      # Validate sound index
      if ($sound_index -lt 1 -or $sound_index -gt 10) { $sound_index = 1 }
      $soundFile = "Alarm$($sound_index.ToString('00'))"

      try {
          $started = [System.Diagnostics.Stopwatch]::StartNew()

          $spinner = @("⏳", "⌛")
          $i = 0
          while ($started.Elapsed.TotalSeconds -lt $length_seconds) {
              Write-Host "`r  $($spinner[$i % 2]) Timer running... ($([int]($length_seconds - $started.Elapsed.TotalSeconds))s left)" -NoNewline
              $i++
              Start-Sleep -Milliseconds 500
          }
          Write-Host "`r                                              " -NoNewline

          # Capture the exact time the timer finished
          $finishTime = Get-Date -Format "HH:mm:ss"
          Write-Host "`r  ✅ Timer finished at $finishTime" -ForegroundColor Green

          # Return with the PLAY_SOUND instruction for the main thread.
          return "CONSOLE::PLAY_SOUND:$soundFile::Timer for $length_seconds seconds finished at $finishTime::END_CONSOLE::OK: Timer finished at $finishTime."

      } catch {
          return "ERROR: Timer failed. $($_.Exception.Message)"
      }
  }

  # ── Self-registration ────────────────────────────────────────────────────────

  $ToolMeta = @{
      Name             = "timer"
      Icon             = "⏲️"
      Interactive      = $true
      RendersToConsole = $true
      Category         = @("Utility", "Time")
      Behavior         = "Use this tool to set a countdown timer for a specific number of seconds. The CLI will show a spinner until the time is up, then play an alarm sound. Sound index (1-10) corresponds to Alarm01.wav to Alarm10.wav."
      Description      = "Sets a countdown timer for X seconds and plays a selectable alarm sound when finished."
      Parameters       = @{
          length_seconds = "integer - required. The number of seconds to wait."
          sound_index    = "integer - optional. 1-10 (default 1), maps to Alarm01-Alarm10.wav."
      }
      Example          = "<tool_call>{ ""name"": ""timer"", ""parameters"": { ""length_seconds"": 60, ""sound_index"": 3 } }</tool_call>"
      FormatLabel      = { param($p) "$($p.length_seconds)s" }
      Execute          = { param($params) Invoke-TimerTool @params }
  }