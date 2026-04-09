#!/usr/bin/env python3
"""Top 3 processes by GPU VRAM usage.
Tries NVIDIA (nvidia-smi) first, falls back to AMD (drm fdinfo).
Writes name|pct lines to /tmp/.conky_gpu_display."""
import os
import subprocess

DISPLAY = '/tmp/.conky_gpu_display'


def nvidia_top():
    try:
        import xml.etree.ElementTree as ET
        out = subprocess.check_output(['nvidia-smi', '-x', '-q'], stderr=subprocess.DEVNULL)
        root = ET.fromstring(out)
        gpu   = root.find('gpu')
        total = int(gpu.find('fb_memory_usage/total').text.split()[0])
        entries = []
        for proc in gpu.find('processes').findall('process_info'):
            try:
                mem  = int(proc.find('used_memory').text.split()[0])
                name = proc.find('process_name').text.strip().split('/')[-1][:12]
                entries.append((name, mem))
            except Exception:
                pass
        entries.sort(key=lambda x: x[1], reverse=True)
        return [(n, int(m * 100 / total)) for n, m in entries[:3]], True
    except Exception:
        return [], False


def amd_top():
    try:
        # Detect total VRAM from sysfs
        total_kib = 0
        for card in sorted(os.listdir('/sys/class/drm/')):
            vram_file = f'/sys/class/drm/{card}/device/mem_info_vram_total'
            if os.path.exists(vram_file):
                with open(vram_file) as f:
                    total_kib = int(f.read().strip()) // 1024
                break
        if not total_kib:
            return [], False

        vram, names = {}, {}
        for pid in os.listdir('/proc'):
            if not pid.isdigit():
                continue
            fdinfo_dir = f'/proc/{pid}/fdinfo'
            try:
                kib, has_drm = 0, False
                for fd in os.listdir(fdinfo_dir):
                    try:
                        with open(f'{fdinfo_dir}/{fd}') as f:
                            for line in f:
                                if line.startswith('drm-memory-vram:'):
                                    kib += int(line.split()[1])
                                    has_drm = True
                    except Exception:
                        pass
                if has_drm and kib > 0:
                    with open(f'/proc/{pid}/comm') as f:
                        names[pid] = f.read().strip()
                    vram[pid] = kib
            except Exception:
                pass

        rows = sorted(vram.items(), key=lambda x: x[1], reverse=True)[:3]
        return [(names[pid][:12], int(kib * 100 / total_kib)) for pid, kib in rows], True
    except Exception:
        return [], False


rows, ok = nvidia_top()
if not ok:
    rows, ok = amd_top()

try:
    with open(DISPLAY, 'w') as f:
        for name, pct in rows:
            f.write(f'{name}|{pct}\n')
        for _ in range(3 - len(rows)):
            f.write('|\n')
except Exception:
    pass
