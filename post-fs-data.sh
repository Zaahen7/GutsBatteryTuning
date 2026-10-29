#!/system/bin/sh
MOD_DIR=${0%/*}
LOG=$MOD_DIR/GutsModule.log

echo "post-fs-data: $(date)" > "$LOG"
rm -f "$MOD_DIR/.applied"

log() {
    echo "$1" >> "$LOG"
}

if [ -f "$MOD_DIR/config.sh" ]; then
    source "$MOD_DIR/config.sh"
    log "[OK] Config file found."
else
    log "[FAIL] Config file missing."
    exit 1
fi

if [ "$zram2zstd" = "true" ]; then
    zstd_state="❌"
    if [ -e /sys/block/zram0/comp_algorithm ]; then
        log "[OK] ZRAM exists"
        log "$(cat /sys/block/zram0/comp_algorithm)"
        log "$(cat /proc/swaps)"
        if grep -q "zstd" /sys/block/zram0/comp_algorithm; then
            log "[OK] ZSTD is supported"
            if echo "zstd" > "/sys/block/zram0/comp_algorithm" 2>>"$LOG"; then
                log "[OK] Changed ZRAM to ZSTD."
                zstd_state="✅"
            else
                log "[FAIL] Error changing ZRAM."
            fi
            log "$(cat /sys/block/zram0/comp_algorithm)"
            log "$(cat /proc/swaps)"
        else
            log "[FAIL] ZSTD isnt supported"
        fi
    else
        log "[FAIL] ZRAM doesnt exist"
    fi
    ZSTD_PART="ZSTD ${zstd_state}"
else
    ZSTD_PART=""
fi

time_in_min=$((time_after_boot / 60))

STATUS="${ZSTD_PART:+$ZSTD_PART - }Some tweaks apply ${time_in_min}min after boot"
sed -i "s|^description=.*|description=$STATUS|" "$MOD_DIR/module.prop"
echo "$ZSTD_PART" > "$MOD_DIR/.zstd_status"
