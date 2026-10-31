
#!/system/bin/sh

MOD_DIR="${0%/*}"
[ "$MOD_DIR" = "$0" ] && MOD_DIR="."

LOG="$MOD_DIR/GutsModule.log"

# ===== Logging =====
log() {
    printf '%s\n' "$1" >> "$LOG"
}

# ===== Wait for Android Boot =====
boot_wait=0

while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
    if [ "$boot_wait" -ge 180 ]; then
        log "[FAIL] Android boot completion timeout."
        exit 1
    fi

    sleep 1
    boot_wait=$((boot_wait + 1))
done

# ===== Load Configuration =====
if [ -f "$MOD_DIR/config.sh" ]; then
    . "$MOD_DIR/config.sh"
    log "[OK] Config file found."
else
    log "[FAIL] Config file missing."
    exit 1
fi

log ""
log "=== Guts Battery Tuning - $(date '+%Y-%m-%d %H:%M:%S') ==="

# ===== Generic Apply Function =====
apply() {
    desc="$1"
    value="$2"
    target="$3"

    if [ ! -e "$target" ]; then
        log "[FAIL] $desc -> $target (node missing)"
        return 1
    fi

    if printf '%s\n' "$value" > "$target" 2>>"$LOG"; then
        log "[OK] $desc -> $value"
        return 0
    else
        log "[FAIL] $desc -> $value (write failed)"
        return 1
    fi
}

# ===== EGO Rate-Limit =====
RL_PART=""
HTB_PART=""

if [ "$ego_rate_limit" = "true" ]; then
    apply "EGO rate-limit big" \
        "9,0,1,4 ${ego_rate_limit_big}" \
        /sys/devices/platform/ems/emstune/aio_tuner
fi

# ===== Heavy Task Boost =====
if [ "$heavy_tb" = "true" ]; then
    apply "EGO htask_boost big" \
        "5,0,1,4 ${heavy_tb_big}" \
        /sys/devices/platform/ems/emstune/aio_tuner
fi

if [ "$ego_rate_limit" = "true" ]; then
    apply "EGO rate-limit little" \
        "9,0,1,0 ${ego_rate_limit_little}" \
        /sys/devices/platform/ems/emstune/aio_tuner
fi

if [ "$heavy_tb" = "true" ]; then
    apply "EGO htask_boost little" \
        "5,0,1,0 ${heavy_tb_little}" \
        /sys/devices/platform/ems/emstune/aio_tuner
fi

# ===== Read cur_set =====
if [ "$ego_rate_limit" = "true" ] || [ "$heavy_tb" = "true" ]; then
    CUR_SET=$(cat /sys/devices/platform/ems/emstune/cur_set 2>>"$LOG")

    line0=$(printf '%s\n' "$CUR_SET" | grep -A10 "cpufreq gov" | sed -n '4p')
    line4=$(printf '%s\n' "$CUR_SET" | grep -A10 "cpufreq gov" | sed -n '8p')

    rate0=$(printf '%s\n' "$line0" | awk '{print $7}')
    rate4=$(printf '%s\n' "$line4" | awk '{print $7}')

    htb0=$(printf '%s\n' "$line0" | awk '{print $3}')
    htb4=$(printf '%s\n' "$line4" | awk '{print $3}')
fi

if [ "$ego_rate_limit" = "true" ]; then
    rl_state="❌"

    if [ "$rate4" = "$ego_rate_limit_big" ] &&
       [ "$rate0" = "$ego_rate_limit_little" ]; then
        rl_state="✅"
    fi

    RL_PART="RL ${rl_state}"
    log "[INFO] EGO Rate-Limit: $rl_state"
fi

if [ "$heavy_tb" = "true" ]; then
    htb_state="❌"

    if [ "$htb4" = "$heavy_tb_big" ] &&
       [ "$htb0" = "$heavy_tb_little" ]; then
        htb_state="✅"
    fi

    HTB_PART="HTB ${htb_state}"
    log "[INFO] Heavy Task Boost: $htb_state"
fi

# ===== GPU Highspeed Delay =====
GPU_PART=""

if [ "$gpu_hsdelay" = "true" ]; then
    gpu_hs_state="❌"

    if apply "GPU highspeed_delay" \
        "$gpu_hsdelay_value" \
        /sys/devices/platform/10300000.mali/highspeed_delay; then

        gpuhsdelay=$(cat /sys/devices/platform/10300000.mali/highspeed_delay 2>>"$LOG")

        [ "$gpuhsdelay" = "$gpu_hsdelay_value" ] && gpu_hs_state="✅"
    fi

    GPU_PART="GPU ${gpu_hs_state}"
fi

# ===== CPU Min Frequency =====
MINFQ_PART=""

if [ "$min_freq_limit" = "true" ]; then
    minfq_state="❌"

    apply "CPU min_freq_limit big" \
        "$min_freq_limit_big" \
        /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq_limit

    apply "CPU min_freq_limit little" \
        "$min_freq_limit_little" \
        /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq_limit

    minfq0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq_limit 2>>"$LOG")
    minfq4=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq_limit 2>>"$LOG")

    if [ "$minfq0" = "$min_freq_limit_little" ] &&
       [ "$minfq4" = "$min_freq_limit_big" ]; then
        minfq_state="✅"
    fi

    MINFQ_PART="MINFQ ${minfq_state}"
fi

# ===== ZRAM Swappiness =====
SWAP_PART=""

if [ "$change_zram_swappiness" = "true" ]; then
    swappiness_state="❌"

    current_swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null)
    log "[INFO] Current swappiness: ${current_swappiness:-N/A}"

    if apply "ZRAM swappiness" \
        "$zram_swappiness" \
        /proc/sys/vm/swappiness; then

        current_swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null)

        if [ "$current_swappiness" = "$zram_swappiness" ]; then
            swappiness_state="✅"
        fi
    fi

    log "[INFO] New swappiness: ${current_swappiness:-N/A}"

    SWAP_PART="SWAP ${swappiness_state}"
fi

# ===== Network Scheduler =====
NETSCH_PART=""

if [ "$net_scheduler" = "true" ]; then
    net_sch_state="❌"

    if ip link show wlan0 >/dev/null 2>&1; then
        if tc qdisc replace dev wlan0 root "$net_sched" 2>>"$LOG"; then
            log "[OK] Network scheduler changed to $net_sched."
            net_sch_state="✅"
        else
            log "[FAIL] tc qdisc replace failed."
        fi
    else
        log "[INFO] wlan0 interface not found."
    fi

    NETSCH_PART="NET ${net_sch_state}"
fi

# ===== ZSTD Status =====
ZSTD_PART=""

if [ -f "$MOD_DIR/.zstd_status" ]; then
    ZSTD_PART=$(cat "$MOD_DIR/.zstd_status")
fi

# ===== Build Module Status =====
STATUS=""

for part in \
    "$ZSTD_PART" \
    "$RL_PART" \
    "$HTB_PART" \
    "$GPU_PART" \
    "$MINFQ_PART" \
    "$SWAP_PART" \
    "$NETSCH_PART"
do
    if [ -n "$part" ]; then
        STATUS="${STATUS:+$STATUS }$part"
    fi
done

[ -z "$STATUS" ] && STATUS="No tweaks enabled"

# ===== Update Module Description =====
if [ -f "$MOD_DIR/module.prop" ]; then
    if sed -i "s|^description=.*|description=$STATUS|" "$MOD_DIR/module.prop"; then
        log "[OK] Module description updated: $STATUS"
    else
        log "[FAIL] Failed to update module.prop"
    fi
else
    log "[FAIL] module.prop missing"
fi

# ===== Applied Flag =====
touch "$MOD_DIR/.applied"

log "[OK] All tweaks processing completed."
log "[INFO] Module status: $STATUS"
log "========================================"

exit 0
