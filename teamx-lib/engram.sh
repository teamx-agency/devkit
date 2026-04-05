#!/bin/bash
# =============================================================================
# TeamX Dev — Engram Memory Layer
# =============================================================================
# Wrapper bash para Engram (https://github.com/Gentleman-programming/engram)
# Engram aporta: memoria SQLite persistente, recuperacion por layers, sync git.
#
# Uso (desde el agente via Bash tool):
#   source .teamx/lib/engram.sh
#   engram_check_available   # detectar y cachear disponibilidad
#   engram_sync_import       # INIT — traer memoria del equipo desde git
#   engram_sync_export       # RETROSPECTIVE — exportar observaciones al equipo
#   engram_is_available      # verificar cache (sin llamar al binario)
#
# Instalacion de Engram:
#   brew install Gentleman-programming/tap/engram
#
# Graceful degradation: todas las funciones son no-fatales.
# Si Engram no esta instalado, el devkit continua sin cambios.
# =============================================================================

# Resolver ruta al directorio .teamx
if [ -n "${TEAMX_DIR:-}" ]; then
    _ENGRAM_TEAMX_DIR="$TEAMX_DIR"
elif [ -f "$(pwd)/.teamx/state.json" ]; then
    _ENGRAM_TEAMX_DIR="$(pwd)/.teamx"
else
    _ENGRAM_TEAMX_DIR="$(pwd)/.teamx"
fi

ENGRAM_STATUS_FILE="${_ENGRAM_TEAMX_DIR}/engram-status.json"

# =============================================================================
# engram_check_available — detecta disponibilidad y escribe cache
# Retorna 0 si disponible, 1 si no.
# =============================================================================
engram_check_available() {
    local available="false"

    if command -v engram &>/dev/null; then
        # Verificar que el binario responde
        if engram --version &>/dev/null 2>&1; then
            available="true"
        fi
    fi

    local checked_at
    checked_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

    # Escribir cache (best-effort)
    mkdir -p "$(dirname "$ENGRAM_STATUS_FILE")" 2>/dev/null
    printf '{"available":%s,"checked_at":"%s"}\n' "$available" "$checked_at" \
        > "$ENGRAM_STATUS_FILE" 2>/dev/null || true

    if [ "$available" = "true" ]; then
        echo "[Engram] Disponible — memoria persistente activa."
        return 0
    else
        echo "[Engram] No disponible — instala con: brew install Gentleman-programming/tap/engram"
        return 1
    fi
}

# =============================================================================
# engram_is_available — lee cache sin llamar al binario
# Retorna 0 si disponible segun cache, 1 si no o si el cache no existe.
# =============================================================================
engram_is_available() {
    [ -f "$ENGRAM_STATUS_FILE" ] || return 1
    local available
    available=$(jq -r '.available // false' "$ENGRAM_STATUS_FILE" 2>/dev/null)
    [ "$available" = "true" ]
}

# =============================================================================
# engram_sync_import — trae memoria del equipo desde git al DB local
# Llamar en INIT, despues de teamx_get_shared_lessons.
# =============================================================================
engram_sync_import() {
    if ! engram_is_available; then
        return 0  # skip silencioso
    fi

    echo "──────────────────────────────────────────────────────"
    echo "  [Engram] Importando memoria del equipo..."
    echo "──────────────────────────────────────────────────────"

    if engram sync import 2>&1; then
        echo "  [Engram] Import completo — DB local actualizada con observaciones del equipo."
    else
        echo "  [Engram] sync import: sin cambios o sin remote configurado. Continuando."
    fi

    return 0  # siempre no-fatal
}

# =============================================================================
# engram_sync_export — exporta observaciones locales al repo git
# Llamar al final de RETROSPECTIVE, despues de todos los save_observation.
# =============================================================================
engram_sync_export() {
    if ! engram_is_available; then
        return 0  # skip silencioso
    fi

    echo "──────────────────────────────────────────────────────"
    echo "  [Engram] Exportando memoria al equipo..."
    echo "──────────────────────────────────────────────────────"

    if engram sync export 2>&1; then
        echo "  [Engram] Export completo — observaciones disponibles para el equipo via git."
    else
        echo "  [Engram] sync export: sin cambios o export fallido. Continuando."
    fi

    return 0  # siempre no-fatal
}

# =============================================================================
# Punto de entrada para uso directo: bash .teamx/lib/engram.sh <comando>
# =============================================================================
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    # Se ejecuta directamente, no via source
    case "${1:-}" in
        check)   engram_check_available ;;
        import)  engram_sync_import ;;
        export)  engram_sync_export ;;
        status)
            if engram_is_available; then
                echo "[Engram] Status: DISPONIBLE"
                jq '.' "$ENGRAM_STATUS_FILE" 2>/dev/null
            else
                echo "[Engram] Status: NO DISPONIBLE"
            fi
            ;;
        *)
            echo "Uso: bash .teamx/lib/engram.sh <check|import|export|status>"
            echo "  check   — detecta disponibilidad y actualiza cache"
            echo "  import  — sync desde git al DB local (INIT)"
            echo "  export  — sync desde DB local al git (RETROSPECTIVE)"
            echo "  status  — muestra estado del cache"
            ;;
    esac
fi
