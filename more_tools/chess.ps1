# ===============================================
# GemmaCLI Tool - chess.ps1
# Responsibility: Stateful chess game with perfect legal-move validation.
# Uses Unicode pieces (♘ ♞ etc.) and python-chess for 100% correct rules.
# ===============================================

function Invoke-ChessTool {
    param(
        [ValidateSet("newgame", "show", "move", "undo", "status", "exportfen")]
        [string]$action = "show",

        [string]$move = ""   # UCI (e2e4) or SAN (Nf3, O-O, e8=Q, etc.)
    )

    $stateDir  = Join-Path $env:APPDATA "GemmaCLI"
    $stateFile = Join-Path $stateDir "chess_state.json"
    if (-not (Test-Path $stateDir)) { New-Item -Path $stateDir -ItemType Directory -Force | Out-Null }

    # Temporary Python script
    $tempPy = Join-Path $env:TEMP "gemma_chess_$(Get-Random).py"

    $env:CHESS_STATE = $stateFile
    $env:CHESS_ACTION = $action
    $env:CHESS_MOVE = $move

    $pyCode = @'
import sys
sys.stdout = open(sys.stdout.fileno(), mode='w', encoding='utf-8', buffering=1)
import chess
import json
import os
b = chess.Board()
p = b.piece_at(chess.square(0, 6))  # a7 = black pawn
print(f"DEBUG: color={p.color} symbol={p.symbol()}")

state_file = os.environ["CHESS_STATE"]
action = os.environ["CHESS_ACTION"]
move_str = os.environ.get("CHESS_MOVE", "")

# Load or create board
try:
    with open(state_file, "r", encoding="utf-8") as f:
        data = json.load(f)
    board = chess.Board(data.get("fen", chess.STARTING_FEN))
except:
    board = chess.Board()

result = ""

if action == "newgame":
    board = chess.Board()
    result = "♟️ New game started! White to move."

elif action == "show":
    pass  # just render below

elif action == "move":
    try:
        if len(move_str) == 4 or (len(move_str) == 5 and move_str[4] in "qrbn"):
            m = chess.Move.from_uci(move_str)
        else:
            m = board.parse_san(move_str)

        if m in board.legal_moves:
            board.push(m)
            result = f"✅ Move accepted: {move_str}"
        else:
            result = f"❌ ILLEGAL MOVE: {move_str}\nLegal moves start with: {list(board.legal_moves)[:8]}..."
    except Exception as e:
        result = f"❌ Invalid move format: {move_str}\nUse UCI (e2e4) or SAN (Nf3, O-O, e8=Q)."

elif action == "undo":
    if board.move_stack:
        board.pop()
        result = "↩️ Last move undone."
    else:
        result = "Nothing to undo."

elif action == "status":
    turn = "White" if board.turn else "Black"
    result = f"Turn: {turn}\nIn check: {board.is_check()}\nCheckmate: {board.is_checkmate()}\nStalemate: {board.is_stalemate()}\nHalfmove clock: {board.halfmove_clock}"

elif action == "exportfen":
    result = board.fen()

# Save state
with open(state_file, "w", encoding="utf-8") as f:
    json.dump({"fen": board.fen()}, f, indent=2)

# Block-based board using ASCII piece letters on light/dark squares
# White: P N B R Q K   Black: p n b r q k   Empty: light=░░░ dark=███
def render_board(b):
    piece_map = {
        (chess.PAWN,   False): 'P', (chess.PAWN,   True):  'p',
        (chess.KNIGHT, False): 'N', (chess.KNIGHT, True):  'n',
        (chess.BISHOP, False): 'B', (chess.BISHOP, True):  'b',
        (chess.ROOK,   False): 'R', (chess.ROOK,   True):  'r',
        (chess.QUEEN,  False): 'Q', (chess.QUEEN,  True):  'q',
        (chess.KING,   False): 'K', (chess.KING,   True):  'k',
    }
    s = "  a  b  c  d  e  f  g  h\n"
    for rank in range(7, -1, -1):
        row = f"{rank+1} "
        for file in range(8):
            is_light = (rank + file) % 2 == 1
            piece = b.piece_at(chess.square(file, rank))
            if piece:
                sym = piece_map[(piece.piece_type, piece.color)]
                bg = "." if is_light else "#"
                row += f"{bg}{sym}{bg}"
            else:
                row += "..." if is_light else "###"
        s += row + f" {rank+1}\n"
    s += "   a  b  c  d  e  f  g  h\n"
    return s

if action in ["show", "move", "newgame", "undo"]:
    result = render_board(board) + "\n" + result

print(result)
'@

    try {
        $pyCode | Set-Content -Path $tempPy -Encoding UTF8 -Force

        $output = & python $tempPy 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "Python exited with code $LASTEXITCODE"
        }

        Remove-Item $tempPy -Force -ErrorAction SilentlyContinue

        $lines = $output -join "`n"
        $processedLines = $lines -split "`n" | Where-Object { $_ -notmatch '^DEBUG:' } | ForEach-Object {
            if ($_ -match '^[1-8] ') {
                $_.Replace('.','░').Replace('#','█').Replace('P','♙').Replace('N','♘').Replace('B','♗').Replace('R','♖').Replace('Q','♕').Replace('K','♔').Replace('p','♟').Replace('n','♞').Replace('b','♝').Replace('r','♜').Replace('q','♛').Replace('k','♚')
            } else { $_ }
        }

        Write-Host ""
        foreach ($line in $processedLines) {
            if ($line -match '^[1-8]') {
                Write-Host "  " -NoNewline
                Write-Host $line.Substring(0, 2) -NoNewline -ForegroundColor Cyan
                Write-Host $line.Substring(2) -ForegroundColor White
            } elseif ($line -match '^ {3}[a-h]') {
                Write-Host "     $line" -ForegroundColor DarkGray
            } elseif (-not [string]::IsNullOrWhiteSpace($line)) {
                Write-Host "  $line" -ForegroundColor Yellow
            }
        }
        Write-Host ""

        $resultMsg = ($processedLines | Where-Object { $_ -and $_ -notmatch '^ {3}[a-h]' -and $_ -notmatch '^[1-8]' } | Select-Object -Last 1)
        $consoleSummary = if ($resultMsg) { $resultMsg.Trim() } else { "Board displayed." }
        $instruction = switch ($action) {
            "newgame" { "Board is rendered. Do NOT redraw it. Wait for the player to state their move. When they do, you MUST call chess(action=move, move=<their_move>) to register it into the engine BEFORE playing your own reply." }
            "show"    { "Board is rendered. Do NOT redraw it. Wait for the player's move, then call chess(action=move, move=<their_move>) to register it." }
            "move"    { "Board is rendered. Do NOT redraw it. If you just registered the player's move, now call chess(action=move, move=<your_reply>) to play your response. If you just played your own reply, acknowledge briefly and wait for the player." }
            "undo"    { "Board is rendered after undo. Do NOT redraw it. Wait for the player's move." }
            default   { "Board is rendered. Do NOT redraw it." }
        }
        return "CONSOLE::$consoleSummary::END_CONSOLE::{`"action`":`"$action`",`"move`":`"$move`"}`n→ INSTRUCTION: $instruction"


    }
    catch {
        Remove-Item $tempPy -Force -ErrorAction SilentlyContinue
        return "ERROR: $($output -join "`n")"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────
$ToolMeta = @{
    Name        = "chess"
    Icon        = "♟️"
    RendersToConsole = $true
    Interactive      = $false
    Version          = "1.1.2"
    Category    = @("Gaming/Entertainment")
    Behavior    = "Stateful chess game. IMPORTANT: ALL moves — the player's AND yours — must be submitted via this tool. When the player states a move, call chess(action=move, move=<their_move>) FIRST, then play your reply with a second call."
    Description = "Full chess engine with Unicode board (♘ ♞ etc.), perfect legal-move validation, undo, and persistent state."
    Keywords    = @("chess", "game", "strategy", "entertainment", "puzzle")
    Parameters  = @{
        action = "'newgame', 'show', 'move', 'undo', 'status', or 'exportfen' (default: show)"
        move   = "The move to play (UCI e2e4 or SAN Nf3, O-O, e8=Q, etc.) — only used with action=move"
    }
    Example     = '<tool_call>{ "name": "chess", "parameters": { "action": "move", "move": "e2e4" } }</tool_call>'
    FormatLabel = { param($p) "$($p.action)$(if($p.move){" $($p.move)"})" }
    Execute     = { param($p) Invoke-ChessTool @p }

    ToolUseGuidanceMajor = @"
        - The board renders directly to the terminal. NEVER redraw it. NEVER use markdown tables. Acknowledge briefly.
        - NEVER move pieces in your head or assume a move is registered — EVERY move (yours AND the player's) MUST go through this tool.
        - Turn sequence (repeat every turn):
            1. Player types their move → YOU call chess(action=move, move=<their move>) to register it.
            2. Tool renders the updated board.
            3. YOU call chess(action=move, move=<your response move>) to play your reply.
            4. Tool renders the updated board. Acknowledge briefly and wait.
        - You play as BLACK unless the user says otherwise.
        - If a move is rejected, try a different legal move — do not give up.
"@
    ToolUseGuidanceMinor = @"
        - EVERY move (player's and yours) must be submitted via action=move. Never skip this.
        - Show board: action=show  |  New game: action=newgame  |  Undo: action=undo
        - Do NOT draw the board yourself in any format.
"@
}
