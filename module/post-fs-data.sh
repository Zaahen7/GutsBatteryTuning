#!/system/bin/sh

MOD_DIR=${0%/*}
LOG="$MOD_DIR/GutsModule.log"
CONFIG="$MOD_DIR/config.sh"
MODULE_PROP="$MOD_DIR/module.prop"

# Initialize log
printf 'post-fs-data: %s\n' "$(date)" > "$LOG"
rm -f "$MOD_DIR/.applied"

log() {
    printf '%s\n' "$1" >> "$LOG"
}

# Load configuration
if [ ! -f "$CONFIG" ]; then
    log "[FAIL] Config file missing."
    exit 1
fi

. "$CONFIG"
log "[OK] Config file loaded."

# ZRAM ZSTD configuration
ZSTD_PART=""

if [ "$zram2zstd" = "true" ]; then
    zstd_state="❌"
    ZRAM_ALGO="/sys/block/zram0/comp_algorithm"

    if [ -e "$ZRAM_ALGO" ]; then
        log "[OK] ZRAM exists."
        log "$( < "$ZRAM_ALGO" )"
        log "$( < /proc/swaps )"

        if grep -qw "zstd" "$ZRAM_ALGO"; then
            log "[OK] ZSTD is supported."

            if printf '%s\n' "zstd" > "$ZRAM_ALGO" 2>> "$LOG"; then
                log "[OK] Changed ZRAM to ZSTD."
                zstd_state="✅"
            else
                log "[FAIL] Error changing ZRAM."
            fi

            log "$( < "$ZRAM_ALGO" )"
            log "$( < /proc/swaps )"
        else
            log "[FAIL] ZSTD isn't supported."
        fi
    else
        log "[FAIL] ZRAM doesn't exist."
    fi

    ZSTD_PART="ZSTD $zstd_state"
fi

# Save ZSTD status
printf '%s\n' "$ZSTD_PART" > "$MOD_DIR/.zstd_status"

log "[OK] post-fs-data completed."
