#!/bin/bash
# =============================================================================
# TeamX — Branding helpers (ANSI palette + glyph-prefixed loggers)
# =============================================================================
# Source this file from any .teamx/lib/*.sh script that emits user-facing
# output. Provides a consistent TeamX visual identity across every script.
#
# Honors the NO_COLOR convention (https://no-color.org/) — disables ANSI
# when NO_COLOR is set or when stdout is not a TTY.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/branding.sh"
#   tx_header "INIT — parsing CI profile"
#   tx_ok    "Stack detected: php, node"
#   tx_warn  "ci-profile.json is empty"
#   tx_fail  "PHPStan failed on OrderService:142"
#   tx_next  "Fix the mapper, re-run VERIFY"
#   tx_brand "AgenteX cargado"
#   tx_dim   "estado leído de .teamx/state.json"
#   tx_rule
# =============================================================================

# ── Color detection ──────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    TX_CYAN="\033[0;36m"
    TX_GREEN="\033[0;32m"
    TX_YELLOW="\033[1;33m"
    TX_RED="\033[0;31m"
    TX_BOLD="\033[1m"
    TX_DIM="\033[2m"
    TX_NC="\033[0m"
else
    TX_CYAN=""
    TX_GREEN=""
    TX_YELLOW=""
    TX_RED=""
    TX_BOLD=""
    TX_DIM=""
    TX_NC=""
fi

# ── Glyphs ───────────────────────────────────────────────────────────────────
# Mismo set que visual_identity.glyphs en persona.yaml. Set cerrado.
TX_GLYPH_PASS="✓"
TX_GLYPH_FAIL="✗"
TX_GLYPH_WARN="⚠"
TX_GLYPH_NEXT="▸"
TX_GLYPH_BRAND="▰"

# ── Loggers ──────────────────────────────────────────────────────────────────

# tx_header "<text>" — gate or section header with TeamX signature
tx_header() {
    printf "%b%b▰▰▰ AgenteX · TeamX%b %b—%b %b%s%b\n" \
        "$TX_CYAN" "$TX_BOLD" "$TX_NC" "$TX_DIM" "$TX_NC" "$TX_BOLD" "$1" "$TX_NC"
}

# tx_ok "<text>" — success line, green ✓
tx_ok() {
    printf "%b%s%b %s\n" "$TX_GREEN" "$TX_GLYPH_PASS" "$TX_NC" "$1"
}

# tx_fail "<text>" — failure line, red ✗
tx_fail() {
    printf "%b%s%b %s\n" "$TX_RED" "$TX_GLYPH_FAIL" "$TX_NC" "$1"
}

# tx_warn "<text>" — warning line, yellow ⚠
tx_warn() {
    printf "%b%s%b %s\n" "$TX_YELLOW" "$TX_GLYPH_WARN" "$TX_NC" "$1"
}

# tx_next "<text>" — next-action line, cyan ▸
tx_next() {
    printf "%b%s%b %s\n" "$TX_CYAN" "$TX_GLYPH_NEXT" "$TX_NC" "$1"
}

# tx_brand "<text>" — branded prefix without header weight
tx_brand() {
    printf "%b%s%b %s\n" "$TX_BOLD" "$TX_GLYPH_BRAND" "$TX_NC" "$1"
}

# tx_dim "<text>" — secondary metadata (timestamps, paths, hints)
tx_dim() {
    printf "%b%s%b\n" "$TX_DIM" "$1" "$TX_NC"
}

# tx_rule — horizontal divider (60 chars)
tx_rule() {
    printf "%b%s%b\n" "$TX_DIM" "─────────────────────────────────────────────────────────" "$TX_NC"
}

# tx_kv "<label>" "<value>" — aligned key/value, label dim, value bold
tx_kv() {
    printf "  %b%-18s%b %b%s%b\n" "$TX_DIM" "$1" "$TX_NC" "$TX_BOLD" "$2" "$TX_NC"
}
