#!/usr/bin/env bash
# conky-pixel-theme installer
# Detects hardware, generates conky.conf and bars.lua, installs to ~/.config/conky/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.config/conky"
BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

info()    { echo -e "  ${GREEN}✓${NC} $*"; }
warn()    { echo -e "  ${YELLOW}!${NC} $*"; }
section() { echo -e "\n${BOLD}$*${NC}"; }

echo -e "${BOLD}conky-pixel-theme installer${NC}"
echo "================================"

# ─── Detection helpers ──────────────────────────────────────────────────────

hwmon_index() {
    for d in /sys/class/hwmon/hwmon*/; do
        [[ "$(cat "${d}name" 2>/dev/null)" == "$1" ]] && basename "$d" | grep -o '[0-9]*' && return
    done
    echo ""
}

# ─── CPU ────────────────────────────────────────────────────────────────────
section "Detecting CPU..."

CPU_HWMON=$(hwmon_index "k10temp")
[ -z "$CPU_HWMON" ] && CPU_HWMON=$(hwmon_index "coretemp")
[ -z "$CPU_HWMON" ] && warn "CPU temp sensor not found — temp graph will be blank" \
                     || info "CPU temp:    hwmon${CPU_HWMON}"

CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | sed 's/.*: //;s/ @.*//' || echo "Unknown CPU")
CPU_BOOST_KHZ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || echo "4000000")
CPU_BOOST_GHZ=$(awk "BEGIN {printf \"%.3f\", ${CPU_BOOST_KHZ}/1000000}")
CPU_BOOST_GHZ_DISPLAY=$(awk "BEGIN {printf \"%.1f\", ${CPU_BOOST_KHZ}/1000000}")
info "CPU:         ${CPU_MODEL} (boost ${CPU_BOOST_GHZ} GHz)"

# Fan controller — try common driver names
FAN_HWMON=""
for name in asus thinkpad dell_smm nct6775 nct6776 it8 f71882fg; do
    FAN_HWMON=$(hwmon_index "$name")
    [ -n "$FAN_HWMON" ] && { info "Fan ctrl:    hwmon${FAN_HWMON} ($name)"; break; }
done
[ -z "$FAN_HWMON" ] && warn "Fan controller not found — fan RPM will not display"

CPU_FAN_INPUT=1
GPU_FAN_INPUT=2

# ─── GPU(s) ─────────────────────────────────────────────────────────────────
section "Detecting GPU(s)..."

AMD_CARD=""
AMD_GPU_MODEL=""
AMD_GPU_HWMON=""
for c in /sys/class/drm/card[0-9]*/; do
    if [[ -f "${c}device/gpu_busy_percent" ]]; then
        AMD_CARD=$(basename "$c")
        AMD_GPU_HWMON=$(hwmon_index "amdgpu")
        AMD_GPU_MODEL=$(cat "${c}device/product_name" 2>/dev/null \
            || grep -r "." "${c}device/../product_name" 2>/dev/null \
            || echo "AMD GPU")
        info "AMD GPU:     ${AMD_CARD} — ${AMD_GPU_MODEL}"
        break
    fi
done

NVIDIA_PRESENT=false; NVIDIA_MODEL=""; NVIDIA_VRAM_MIB=4096
if command -v nvidia-smi &>/dev/null; then
    NV=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || true)
    if [[ -n "$NV" ]]; then
        NVIDIA_PRESENT=true
        NVIDIA_MODEL=$(cut -d',' -f1 <<< "$NV" | sed 's/NVIDIA GeForce //' | xargs)
        NVIDIA_VRAM_MIB=$(cut -d',' -f2 <<< "$NV" | xargs)
        info "NVIDIA GPU:  ${NVIDIA_MODEL} (${NVIDIA_VRAM_MIB} MiB)"
    fi
fi

if   [[ -n "$AMD_CARD" && "$NVIDIA_PRESENT" == true ]]; then GPU_TYPE="hybrid"
elif [[ -n "$AMD_CARD" ]];                               then GPU_TYPE="amd"
elif [[ "$NVIDIA_PRESENT" == true ]];                    then GPU_TYPE="nvidia"
else GPU_TYPE="none"; warn "No GPU detected — GPU section omitted"; fi

# ─── Network ────────────────────────────────────────────────────────────────
section "Detecting network interfaces..."

WIFI_IFACE=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | head -1 \
    || ls /sys/class/net/ | grep "^wl" | head -1 || echo "")
[ -n "$WIFI_IFACE" ] && info "WiFi:        ${WIFI_IFACE}" || warn "WiFi interface not found"

ETH0=""; ETH1=""
while IFS= read -r iface; do
    [[ "$iface" =~ ^(lo|wl|virbr|docker|veth|br-|tun|tap) ]] && continue
    [[ -z "$ETH0" ]] && ETH0="$iface" || { ETH1="$iface"; break; }
done < <(ls /sys/class/net/ 2>/dev/null)
[[ -n "$ETH0" ]] && info "Ethernet:    ${ETH0}${ETH1:+, $ETH1}"

# ─── OS name ────────────────────────────────────────────────────────────────
OS_NAME=$(lsb_release -ds 2>/dev/null \
    || grep "^PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' \
    || echo "Linux")

# ─── External drive (interactive) ───────────────────────────────────────────
section "External drive"
echo -e "  Mount path to monitor (e.g. /media/${USER}/MyDrive), or Enter to skip:"
read -r -p "  > " EXT_DRIVE || EXT_DRIVE=""

# ─── Install ────────────────────────────────────────────────────────────────
section "Generating config files..."
mkdir -p "$INSTALL_DIR"

cp "${SCRIPT_DIR}/top_gpu.py" "${INSTALL_DIR}/top_gpu.py"
info "Copied top_gpu.py"

# Hand off to Python for template rendering (avoids bash quoting issues with ${} conky syntax)
python3 - <<PYEOF
import os, re

INSTALL_DIR  = "${INSTALL_DIR}"
SCRIPT_DIR   = "${SCRIPT_DIR}"
CPU_MODEL    = "${CPU_MODEL}"
CPU_HWMON    = "${CPU_HWMON:-0}"
CPU_BOOST_KHZ         = "${CPU_BOOST_KHZ}"
CPU_BOOST_GHZ         = "${CPU_BOOST_GHZ}"
CPU_BOOST_GHZ_DISPLAY = "${CPU_BOOST_GHZ_DISPLAY}"
FAN_HWMON    = "${FAN_HWMON:-0}"
CPU_FAN_INPUT = "${CPU_FAN_INPUT}"
GPU_FAN_INPUT = "${GPU_FAN_INPUT}"
GPU_TYPE     = "${GPU_TYPE}"
AMD_CARD     = "${AMD_CARD}"
AMD_GPU_MODEL= "${AMD_GPU_MODEL}"
AMD_GPU_HWMON= "${AMD_GPU_HWMON:-0}"
NVIDIA_MODEL = "${NVIDIA_MODEL}"
NVIDIA_VRAM_MIB = "${NVIDIA_VRAM_MIB}"
WIFI_IFACE   = "${WIFI_IFACE:-wlan0}"
ETH0         = "${ETH0}"
ETH1         = "${ETH1}"
OS_NAME      = "${OS_NAME}"
EXT_DRIVE    = "${EXT_DRIVE}"

def render(path, subs):
    with open(path) as f:
        content = f.read()
    for k, v in subs.items():
        content = content.replace(f'<<<{k}>>>', v)
    return content

# ── GPU section for conky.conf ─────────────────────────────────────────────

def amd_conf():
    return f"""
  \${color3}·· GPU  {AMD_GPU_MODEL} ──────────────────────\${color}
  \${execgraph "cat /sys/class/drm/{AMD_CARD}/device/gpu_busy_percent" 35,285 228B22 FF4F00}\${goto 30}\${voffset 15}\${color1}Usage\${color}  \${color4}\${lua gpu_load}%\${color}
\${voffset -20}  \${execgraph "awk '{{v=int(\$1/1000-50)*2; print (v<0?0:v)}}' /sys/class/hwmon/hwmon{AMD_GPU_HWMON}/temp1_input" 35,285 228B22 FF4F00 100}
\${voffset -20}  \${goto 30}\${voffset -15}\${color1}Temp\${color}  \${color4}\${hwmon {AMD_GPU_HWMON} temp 1}°C\${color}  \${color3}Fan · \${hwmon {FAN_HWMON} fan {GPU_FAN_INPUT}} rpm\${color}"""

def nvidia_conf():
    return f"""
  \${color3}·· GPU  {NVIDIA_MODEL} ────────────────────────\${color}
  \${execgraph "nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | awk '{{print int(\$1*100/\$2)}}'" 35,285 228B22 FF4F00}\${goto 30}\${voffset 15}\${color1}VRAM\${color}  \${color4}\${lua nvidia_vram_mib} MiB · \${lua nvidia_vram_pct}%\${color}
\${voffset -20}  \${execgraph "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | awk '{{v=(\$1-50)*2; print (v<0?0:v)}}'" 35,285 228B22 FF4F00 100}
\${voffset -20}  \${goto 30}\${voffset -15}\${color1}Temp\${color}  \${color4}\${lua nvidia_temp}°C\${color}  \${color3}Pwr · \${exec nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | awk '{{print int(\$1)}}'} W\${color}"""

gpu_section = {"hybrid": amd_conf() + nvidia_conf(),
               "amd":    amd_conf(),
               "nvidia": nvidia_conf(),
               "none":   ""}.get(GPU_TYPE, "")

# ── Top VRAM section ───────────────────────────────────────────────────────
top_vram = """  \${color3}·· Top VRAM ──────────────────────────────\${color}
  \${color4}\${lua gpu_top_name 1}\${color0}\${alignr}\${lua gpu_top_pct 1}\${color}
  \${color4}\${lua gpu_top_name 2}\${color0}\${alignr}\${lua gpu_top_pct 2}\${color}
  \${color4}\${lua gpu_top_name 3}\${color0}\${alignr}\${lua gpu_top_pct 3}\${color}""" if GPU_TYPE != "none" else ""

# ── Ethernet lines ─────────────────────────────────────────────────────────
def eth_line(label, iface):
    return (f"  \${color1}{label}   ·\${color}  "
            f"\${if_up {iface}}\${color3}↑\${color} \${color4}\${upspeed {iface}}\${color}  "
            f"\${color3}↓\${color} \${color4}\${downspeed {iface}}\${else}\${color3}Down\${endif}\${color}")

eth_lines = "\n".join(filter(None, [
    eth_line("ETH 0", ETH0) if ETH0 else "",
    eth_line("ETH 1", ETH1) if ETH1 else "",
]))

# ── External drive line ────────────────────────────────────────────────────
if EXT_DRIVE:
    ext_line = (f"  \${color1}Ext   ·\${color}  "
                f"\${if_mounted {EXT_DRIVE}}[\${color1}\${lua ext_bar}\${color}]  "
                f"\${color4}\${fs_used_perc {EXT_DRIVE}}%  "
                f"\${color3}\${fs_used {EXT_DRIVE}} / \${fs_size {EXT_DRIVE}}"
                f"\${else}\${color3}not mounted\${endif}\${color}")
    ext_drive_path = EXT_DRIVE
else:
    ext_line = "  \${color3}Ext   · not configured\${color}"
    ext_drive_path = "/"

# ── AMD Lua functions ──────────────────────────────────────────────────────
amd_lua = f"""function conky_gpu_bar()
    local f = io.open("/sys/class/drm/{AMD_CARD}/device/gpu_busy_percent")
    local pct = f and tonumber(f:read("*l")) or 0
    if f then f:close() end
    return make_bar(pct)
end

function conky_gpu_load()
    local f = io.open("/sys/class/drm/{AMD_CARD}/device/gpu_busy_percent")
    local v = f and f:read("*l") or "0"
    if f then f:close() end
    return v
end""" if GPU_TYPE in ("amd", "hybrid") else ""

# ── NVIDIA Lua functions ───────────────────────────────────────────────────
nvidia_lua = """local _nv = {vram_pct="0", vram_mib="0", temp="0"}
local _nv_ts = 0

local function _update_nvidia()
    local now = os.time()
    if now - _nv_ts < 2 then return end
    _nv_ts = now
    local f = io.popen("nvidia-smi --query-gpu=memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null")
    if not f then return end
    local line = f:read("*l")
    f:close()
    if not line then return end
    local used, total, temp = line:match("^%s*(%d+),%s*(%d+),%s*(%d+)")
    if used then
        _nv.vram_pct = tostring(math.floor(tonumber(used) * 100 / tonumber(total)))
        _nv.vram_mib = used
        _nv.temp     = temp
    end
end

function conky_nvidia_vram_pct() _update_nvidia(); return _nv.vram_pct end
function conky_nvidia_vram_mib() _update_nvidia(); return _nv.vram_mib end
function conky_nvidia_temp()     _update_nvidia(); return _nv.temp     end""" if GPU_TYPE in ("nvidia", "hybrid") else ""

# ── GPU top Lua functions ──────────────────────────────────────────────────
gpu_top_lua = f"""local _gpu_top     = {{{{"", ""}}, {{"", ""}}, {{"", ""}}}}
local _gpu_top_ts  = 0

local function _update_gpu_top()
    local now = os.time()
    if now - _gpu_top_ts < 5 then return end
    _gpu_top_ts = now
    os.execute("python3 {INSTALL_DIR}/top_gpu.py > /dev/null 2>&1 &")
    local f = io.open("/tmp/.conky_gpu_display")
    if not f then return end
    local fresh = {{}}
    for i = 1, 3 do
        local line = f:read("*l") or "|"
        local name, pct = line:match("^(.*)|(.*)$")
        fresh[i] = {{name or "", pct or ""}}
    end
    f:close()
    _gpu_top = fresh
end

function conky_gpu_top_name(n)
    _update_gpu_top()
    return _gpu_top[tonumber(n) or 1][1]
end

function conky_gpu_top_pct(n)
    _update_gpu_top()
    local p = _gpu_top[tonumber(n) or 1][2]
    return p ~= "" and p .. "%" or ""
end""" if GPU_TYPE != "none" else ""

# ── Render & write ─────────────────────────────────────────────────────────
conf_subs = {
    "INSTALL_DIR":           INSTALL_DIR,
    "OS_NAME":               OS_NAME,
    "CPU_MODEL":             CPU_MODEL,
    "CPU_HWMON":             CPU_HWMON,
    "CPU_BOOST_KHZ":         CPU_BOOST_KHZ,
    "CPU_BOOST_GHZ_DISPLAY": CPU_BOOST_GHZ_DISPLAY,
    "FAN_HWMON":             FAN_HWMON,
    "CPU_FAN_INPUT":         CPU_FAN_INPUT,
    "GPU_SECTION":           gpu_section,
    "EXT_DRIVE_LINE":        ext_line,
    "TOP_VRAM_SECTION":      top_vram,
    "WIFI_IFACE":            WIFI_IFACE,
    "ETH_LINES":             eth_lines,
}

lua_subs = {
    "CPU_BOOST_GHZ":    CPU_BOOST_GHZ,
    "WIFI_IFACE":       WIFI_IFACE,
    "EXT_DRIVE_PATH":   ext_drive_path,
    "AMD_FUNCTIONS":    amd_lua,
    "NVIDIA_FUNCTIONS": nvidia_lua,
    "GPU_TOP_FUNCTIONS":gpu_top_lua,
}

conf_out = os.path.join(INSTALL_DIR, "conky.conf")
with open(conf_out, "w") as f:
    f.write(render(os.path.join(SCRIPT_DIR, "templates", "conky.conf.template"), conf_subs))
print(f"  \033[0;32m✓\033[0m Written {conf_out}")

lua_out = os.path.join(INSTALL_DIR, "bars.lua")
with open(lua_out, "w") as f:
    f.write(render(os.path.join(SCRIPT_DIR, "templates", "bars.lua.template"), lua_subs))
print(f"  \033[0;32m✓\033[0m Written {lua_out}")
PYEOF

# ── Autostart ───────────────────────────────────────────────────────────────
section "Setting up autostart..."
AUTOSTART="${HOME}/.config/autostart/conky.desktop"
cat > "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=Conky
Comment=System monitor
Exec=conky --daemonize --pause=5
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
info "Autostart entry written to ${AUTOSTART}"

echo -e "\n${BOLD}Done!${NC} Run: pkill conky; conky &"
