#!/system/bin/sh
MOD_DIR=${0%/*}
LOG=$MOD_DIR/GutsModule.log

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
done

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

sleep "$time_after_boot"

apply() {
    local desc="$1"
    local value="$2"
    local target="$3"
    if [ ! -e "$target" ]; then
        log "[FAIL] $desc -> $target (node does not exist, kernel missing this patch)"
        return
    fi
    if echo "$value" > "$target" 2>>"$LOG"; then
        log "[OK]   $desc -> $target = $value"
    else
        log "[FAIL] $desc -> $target = $value (write failed)"
    fi
}

log ""
log "=== Guts Battery Tuning - $(date '+%Y-%m-%d %H:%M:%S') ==="

if [ "$ego_rate_limit" = "true" ]; then
    rl_state="❌"
    apply "EGO rate-limit big"     "9,0,1,4 ${ego_rate_limit_big}"   /sys/devices/platform/ems/emstune/aio_tuner
    apply "EGO rate-limit little"  "9,0,1,0 ${ego_rate_limit_little}"  /sys/devices/platform/ems/emstune/aio_tuner
    rate0=$(cat /sys/devices/platform/ems/emstune/cur_set 2>>"$LOG" | grep -A10 "cpufreq gov" | sed -n '4p' | awk '{print $7}')
    rate4=$(cat /sys/devices/platform/ems/emstune/cur_set 2>>"$LOG" | grep -A10 "cpufreq gov" | sed -n '8p' | awk '{print $7}')
    if [ "$rate4" = "$ego_rate_limit_big" ] && [ "$rate0" = "$ego_rate_limit_little" ]; then
        rl_state="✅"
    fi
    RL_PART="RL ${rl_state}"
else
    RL_PART=""
fi

if [ "$heavy_tb" = "true" ]; then
    htb_state="❌"
    apply "EGO htask_boost big"    "5,0,1,4 ${heavy_tb_big}" /sys/devices/platform/ems/emstune/aio_tuner
    apply "EGO htask_boost little" "5,0,1,0 ${heavy_tb_little}" /sys/devices/platform/ems/emstune/aio_tuner
    htb0=$(cat /sys/devices/platform/ems/emstune/cur_set 2>>"$LOG" | grep -A10 "cpufreq gov" | sed -n '4p' | awk '{print $3}')
    htb4=$(cat /sys/devices/platform/ems/emstune/cur_set 2>>"$LOG" | grep -A10 "cpufreq gov" | sed -n '8p' | awk '{print $3}')
    if [ "$htb4" = "$heavy_tb_big" ] && [ "$htb0" = "$heavy_tb_little" ]; then
        htb_state="✅"
    fi
    HTB_PART="HTB ${htb_state}"
else
    HTB_PART=""
fi

if [ "$gpu_hsdelay" = "true" ]; then
    gpu_hs_state="❌"
    apply "GPU highspeed_delay" "${gpu_hsdelay_value}" /sys/devices/platform/10300000.mali/highspeed_delay
    gpuhsdelay=$(cat /sys/devices/platform/10300000.mali/highspeed_delay 2>>"$LOG")
    if [ "$gpuhsdelay" = "$gpu_hsdelay_value" ]; then
        gpu_hs_state="✅"
    fi
    GPU_PART="GPU ${gpu_hs_state}"
else
    GPU_PART=""
fi

if [ "$min_freq_limit" = "true" ]; then
    minfq_state="❌"
    apply "CPU min_freq_limit big"    "${min_freq_limit_big}" /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq_limit
    apply "CPU min_freq_limit little" "${min_freq_limit_little}" /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq_limit
    minfq0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq_limit)
    minfq4=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq_limit)
    if [ "$minfq0" = "$min_freq_limit_little" ] && [ "$minfq4" = "$min_freq_limit_big" ]; then
        minfq_state="✅"
    fi
    MINFQ_PART="MINFQ ${minfq_state}"
else
    MINFQ_PART=""
fi

if [ "$change_zram_swappiness" = "true" ]; then
    swappiness_state="❌"
    log "[INFO] Current swappiness: $(cat /proc/sys/vm/swappiness)"
    if echo "$zram_swappiness" > "/proc/sys/vm/swappiness" 2>>"$LOG"; then
        log "[OK] ZRAM swappiness changed to $zram_swappiness"
        swappiness_state="✅"
    else
        log "[FAIL] Error changing ZRAM swappiness. (write failed)"
    fi
    log "[INFO] Current swappiness: $(cat /proc/sys/vm/swappiness)"
    SWAP_PART="SWAP ${swappiness_state}"
else
    SWAP_PART=""
fi

if [ "$net_scheduler" = "true" ]; then
    net_sch_state="❌"
    if ip link show wlan0 >/dev/null 2>&1; then
        if tc qdisc replace dev wlan0 root "$net_sched" 2>>"$LOG"; then
            log "[OK] Net scheduler for wlan0 changed to $net_sched."
            net_sch_state="✅"
        else
            log "[FAIL] tc qdisc replace failed."
        fi
    else
        log "[INFO] wlan0 interface not found."
    fi
    NETSCH_PART="NET ${net_sch_state}"
else
    NETSCH_PART=""
fi

ZSTD_PART=""
if [ -f "$MOD_DIR/.zstd_status" ]; then
    ZSTD_PART=$(cat "$MOD_DIR/.zstd_status")
    rm -f "$MOD_DIR/.zstd_status"
fi

STATUS=""
for part in "$ZSTD_PART" "$RL_PART" "$HTB_PART" "$GPU_PART" "$MINFQ_PART" "$SWAP_PART" "$NETSCH_PART"; do
    if [ -n "$part" ]; then
        if [ -z "$STATUS" ]; then
            STATUS="$part"
        else
            STATUS="$STATUS $part"
        fi
    fi
done

[ -z "$STATUS" ] && STATUS="No tweaks enabled"

sed -i "s|^description=.*|description=$STATUS|" "$MOD_DIR/module.prop"
touch "$MOD_DIR/.applied"
