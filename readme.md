# Guts Battery Tuning

A small KernelSU module (`guts_module`, v1.0) that applies a set of battery and responsiveness tweaks on the **Samsung Galaxy A35 5G (SM-A356E)**. It changes the ZRAM algorithm, CPU/GPU frequency decisions and a few related kernel parameters, then reports what was actually applied in the module description.

> ⚠️ **Device-specific.** The module writes to Exynos / Samsung EMS / Mali sysfs nodes. It was built and tested only on the SM-A356E. On other devices the nodes may not exist, or may behave differently. If a node is missing, the module logs a failure and skips that tweak instead of crashing.

## Features

| Tweak | Config flag | What it does |
|---|---|---|
| **ZSTD** | `zram2zstd` | Switches the ZRAM compression algorithm to ZSTD (applied early, in `post-fs-data`). |
| **SWAP** | `change_zram_swappiness` | Sets `vm.swappiness` (default `100`). |
| **RL** | `ego_rate_limit` | Increases the EGO rate limit, so the CPU frequency is decided less often. |
| **HTB** | `heavy_tb` | Sets EGO heavy task boost, so tasks are overestimated less and high frequencies trigger less often. |
| **GPU** | `gpu_hsdelay` | Increases the Mali `highspeed_delay`, so the GPU takes more cycles to decide a frequency change. |
| **MINFQ** | `min_freq_limit` | Caps `scaling_min_freq_limit` to stop apps from pinning the minimum frequency too high. |
| **NET** | `net_scheduler` | Sets the Wi-Fi (`wlan0`) qdisc to `fq_codel` to reduce bufferbloat. **Disabled by default.** |

## Requirements

- Samsung Galaxy A35 5G (SM-A356E), or a device with the same kernel nodes
- Rooted with **KernelSU** (tested). It should also work on Magisk versions that support `action.sh`, but this is untested.
- A kernel exposing the following nodes:
  - `/sys/devices/platform/ems/emstune/aio_tuner` and `cur_set`
  - `/sys/devices/platform/10300000.mali/highspeed_delay`
  - `/sys/devices/system/cpu/cpufreq/policy{0,4}/scaling_min_freq_limit`
  - `/sys/block/zram0/comp_algorithm` (with `zstd` supported)

## Installation

> [!CAUTION]
> **These tweaks modify kernel parameters at runtime. Use at your own risk. I am not responsible for any damage, instability or data loss. Changes are not persistent: they are reapplied at every boot, and removing the module and rebooting restores the stock behavior.**

1. Download the latest zip from the [Releases](../../releases) page.
2. Open KernelSU, go to **Modules**, then **Install** and select the zip.
3. Reboot.

When replacing an older version, uninstall it and **reboot first**, then install the new one.

## How it works

| Script | Stage | Job |
|---|---|---|
| `post-fs-data.sh` | Early boot | Changes ZRAM to ZSTD and sets a temporary module description. |
| `service.sh` | After boot + delay | Waits for `sys.boot_completed` plus `time_after_boot` seconds (default 180), then applies the remaining tweaks, verifies each one and updates the module description. |
| `action.sh` | Manual (Action button) | Prints the current system values and refreshes the module description. |
| `config.sh` | N/A | User configuration (flags and values). |

Most tweaks are applied about 3 minutes after boot, to avoid being overwritten by the system while it is still starting up.

## Status in the module description

After the tweaks are applied, the module description shows one status per enabled tweak:

```
ZSTD ✅ RL ✅ HTB ✅ GPU ✅ MINFQ ✅ SWAP ✅
```

- ✅ the value was read back and matches the configured value
- ❌ the write failed, the node is missing, or the value didn't match

Until `service.sh` finishes, the description reads `... Some tweaks apply 3min after boot`.

## Action button

Tapping **Action** on the module prints:

- EGO rate limit and heavy task boost (little and big clusters)
- CPU minimum frequency limits
- GPU highspeed delay
- ZRAM algorithm and swappiness
- Available RAM

It also refreshes the status line in the module description. If the tweaks haven't been applied yet (boot delay not over), it shows `Some tweaks not applied yet.` and leaves the description untouched.

## Configuration

Edit `config.sh` in the module folder (`/data/adb/modules/guts_module/config.sh`) and reboot.

**Flags** (`"true"` / `"false"`):

```sh
zram2zstd="true"
change_zram_swappiness="true"
ego_rate_limit="true"
heavy_tb="true"
gpu_hsdelay="true"
min_freq_limit="true"
net_scheduler="false"
```

**Values** (don't change them unless you know what they do):

| Variable | Default | Description |
|---|---|---|
| `zram_swappiness` | `130` | `vm.swappiness` value |
| `time_after_boot` | `180` | Seconds to wait after boot before applying tweaks |
| `ego_rate_limit_big` | `6` | Rate limit for the big cluster |
| `ego_rate_limit_little` | `16` | Rate limit for the little cluster |
| `heavy_tb_big` | `100` | Heavy task boost for the big cluster |
| `heavy_tb_little` | `100` | Heavy task boost for the little cluster |
| `gpu_hsdelay_value` | `2` | Mali `highspeed_delay` |
| `min_freq_limit_big` | `754000` | Minimum frequency cap, big cluster (kHz) |
| `min_freq_limit_little` | `672000` | Minimum frequency cap, little cluster (kHz) |
| `net_sched` | `fq_codel` | qdisc applied to `wlan0` |

## Logs

Everything is logged to `GutsModule.log` in the module folder:

```
/data/adb/modules/guts_module/GutsModule.log
```

Each line is tagged `[OK]`, `[FAIL]` or `[INFO]`. If a tweak shows ❌, check this file first.

## Troubleshooting

- **A tweak shows ❌ but the Action output shows the right value:** run the Action again. The status is checked right after writing, and some nodes can take a moment to reflect the new value.
- **Everything shows ❌ / node does not exist:** your kernel doesn't expose that node. This module targets the SM-A356E kernel.
- **Action says "Some tweaks not applied yet":** wait for the boot delay (default 3 minutes) after a reboot.
- **ZSTD ❌:** your kernel may not list `zstd` in `/sys/block/zram0/comp_algorithm`.
## Credits

Made by **@Zaahen7**.
