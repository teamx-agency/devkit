# ╔══════════════════════════════════════════════════╗
# ║      TeamX Dev Kit — install.ps1                 ║
# ║      Windows (PowerShell 5.1+)                   ║
# ╚══════════════════════════════════════════════════╝
#
# Uso:
#   irm https://raw.githubusercontent.com/teamx-agency/devkit/main/install.ps1 | iex
#   .\install.ps1

$ErrorActionPreference = "Stop"

$DEVKIT_BASE = "https://raw.githubusercontent.com/teamx-agency/devkit/main"
$MCP_URL     = "https://teamx.agency/mcp/v1/message"

function Log   ($msg) { Write-Host "[teamx] $msg"    -ForegroundColor Cyan }
function Ok    ($msg) { Write-Host "  $([char]0x2713) $msg" -ForegroundColor Green }
function Warn  ($msg) { Write-Host "  ! $msg"        -ForegroundColor Yellow }
function Skip  ($msg) { Write-Host "  - $msg (no detectado, skip)" -ForegroundColor DarkGray }

function Fetch($url, $dest) {
  $dir = Split-Path $dest
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

function HasCommand($cmd) {
  return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

Write-Host ""
Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       TeamX Dev Kit — Installer        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Claude Code ───────────────────────────────────────────────────────────────
if (HasCommand "claude") {
  Log "Claude Code → instalando..."

  $claudeDir  = "$env:USERPROFILE\.claude"
  $claudeCfg  = "$claudeDir\claude.json"
  $commandDir = "$claudeDir\commands"
  New-Item -ItemType Directory -Path $commandDir -Force | Out-Null

  if (Test-Path $claudeCfg) {
    $json = Get-Content $claudeCfg -Raw | ConvertFrom-Json
    if (-not $json.mcpServers) { $json | Add-Member -NotePropertyName mcpServers -NotePropertyValue @{} }
    $json.mcpServers.teamx = @{ type = "url"; url = $MCP_URL }
    $json | ConvertTo-Json -Depth 10 | Set-Content $claudeCfg -Encoding UTF8
    Ok "Claude Code — MCP merged en claude.json existente"
  } else {
    Fetch "$DEVKIT_BASE/configs/claude/claude.json" $claudeCfg
    Ok "Claude Code — claude.json creado"
  }

  Fetch "$DEVKIT_BASE/skills/teamx-dev/SKILL.md"     "$commandDir\teamx-dev.md"
  Fetch "$DEVKIT_BASE/skills/teamx-status/SKILL.md"  "$commandDir\teamx-status.md"
  Fetch "$DEVKIT_BASE/skills/teamx-review/SKILL.md"  "$commandDir\teamx-review.md"
  Fetch "$DEVKIT_BASE/skills/teamx-handoff/SKILL.md" "$commandDir\teamx-handoff.md"
  Fetch "$DEVKIT_BASE/skills/teamx-health/SKILL.md"  "$commandDir\teamx-health.md"
  # Remove v2 legacy command if present
  $legacyV2 = "$commandDir\teamx-dev-v2.md"
  if (Test-Path $legacyV2) { Remove-Item $legacyV2 -Force }
  Ok "Claude Code — comandos /teamx-dev, /teamx-status, /teamx-review, /teamx-handoff, /teamx-health instalados"
} else {
  Skip "Claude Code"
}

Write-Host ""

# ── Google Antigravity ────────────────────────────────────────────────────────
Log "Google Antigravity → instalando..."
$antigravityDir = "$env:USERPROFILE\.gemini\antigravity"
New-Item -ItemType Directory -Path $antigravityDir -Force | Out-Null
Fetch "$DEVKIT_BASE/configs/antigravity/mcp_config.json" "$antigravityDir\mcp_config.json"
Ok "Antigravity — mcp_config.json instalado en ~\.gemini\antigravity\"
Fetch "$DEVKIT_BASE/configs/antigravity/AGENTS.md" "$env:USERPROFILE\AGENTS.md"
Ok "Antigravity — AGENTS.md global instalado en ~\"

Write-Host ""

# ── OpenCode ──────────────────────────────────────────────────────────────────
if (HasCommand "opencode") {
  Log "OpenCode → instalando..."
  $opencodeDir = "$env:APPDATA\opencode"
  $opencodeCfg = "$opencodeDir\opencode.json"
  New-Item -ItemType Directory -Path $opencodeDir -Force | Out-Null

  if (Test-Path $opencodeCfg) {
    $json = Get-Content $opencodeCfg -Raw | ConvertFrom-Json
    if (-not $json.mcp) { $json | Add-Member -NotePropertyName mcp -NotePropertyValue @{} }
    $json.mcp.teamx = @{ type = "remote"; url = $MCP_URL; enabled = $true }
    $json | ConvertTo-Json -Depth 10 | Set-Content $opencodeCfg -Encoding UTF8
    Ok "OpenCode — MCP merged en opencode.json existente"
  } else {
    Fetch "$DEVKIT_BASE/configs/opencode/opencode.json" $opencodeCfg
    Ok "OpenCode — opencode.json creado"
  }
} else {
  Skip "OpenCode"
}

Write-Host ""

# ── Codex CLI ─────────────────────────────────────────────────────────────────
if (HasCommand "codex") {
  Log "Codex CLI → instalando..."
  $codexDir = "$env:USERPROFILE\.codex"
  $codexCfg = "$codexDir\config.toml"
  New-Item -ItemType Directory -Path $codexDir -Force | Out-Null

  if (Test-Path $codexCfg) {
    $content = Get-Content $codexCfg -Raw
    if ($content -notmatch "\[mcp_servers\.teamx\]") {
      Add-Content $codexCfg "`n[mcp_servers.teamx]`nurl = `"$MCP_URL`""
      Ok "Codex CLI — MCP appended a config.toml existente"
    } else {
      Ok "Codex CLI — MCP ya configurado, sin cambios"
    }
  } else {
    Fetch "$DEVKIT_BASE/configs/codex/config.toml" $codexCfg
    Ok "Codex CLI — config.toml creado"
  }
} else {
  Skip "Codex CLI"
}

Write-Host ""

# ── Crush ─────────────────────────────────────────────────────────────────────
if (HasCommand "crush") {
  Log "Crush → instalando..."
  $crushDir = "$env:APPDATA\crush"
  $crushCfg = "$crushDir\config.toml"
  New-Item -ItemType Directory -Path $crushDir -Force | Out-Null

  if (Test-Path $crushCfg) {
    $content = Get-Content $crushCfg -Raw
    if ($content -notmatch "\[mcp\.servers\.teamx\]") {
      Add-Content $crushCfg "`n[mcp.servers.teamx]`nurl     = `"$MCP_URL`"`ntype    = `"http`"`nenabled = true"
      Ok "Crush — MCP appended a config.toml existente"
    } else {
      Ok "Crush — MCP ya configurado, sin cambios"
    }
  } else {
    Fetch "$DEVKIT_BASE/configs/crush/config.toml" $crushCfg
    Ok "Crush — config.toml creado"
  }
} else {
  Skip "Crush"
}

Write-Host ""

# ── Variables de entorno (sesión actual + perfil de usuario) ──────────────────
Log "Configurando variables de entorno..."
[System.Environment]::SetEnvironmentVariable("TEAMX_MCP_URL", $MCP_URL, "User")
$env:TEAMX_MCP_URL = $MCP_URL
Ok "Variable TEAMX_MCP_URL configurada para el usuario"

# ── Resumen final ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         ✅ Instalación completa         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  MCP TeamX activo en todas las tools detectadas."
Write-Host ""
Write-Host "  Comandos disponibles:" -ForegroundColor Green
Write-Host "  → " -NoNewline; Write-Host "/teamx-dev PROJECT-ID" -ForegroundColor Cyan -NoNewline; Write-Host "      — Ciclo autonomo (state machine)"
Write-Host "  → " -NoNewline; Write-Host "/teamx-status" -ForegroundColor Cyan -NoNewline; Write-Host "              — Dashboard de proyectos"
Write-Host "  → " -NoNewline; Write-Host "/teamx-review MR-IID" -ForegroundColor Cyan -NoNewline; Write-Host "       — Code review estructurado"
Write-Host "  → " -NoNewline; Write-Host "/teamx-handoff" -ForegroundColor Cyan -NoNewline; Write-Host "             — Handoff de contexto"
Write-Host "  → " -NoNewline; Write-Host "/teamx-health PROJECT-ID" -ForegroundColor Cyan -NoNewline; Write-Host "   — Auditoria de salud"
Write-Host ""
