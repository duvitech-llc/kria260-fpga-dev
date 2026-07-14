# ============================================================
# Vitis 2025.2+ (Unified IDE) workspace creation script
#
# Creates:
#   - Platform component "kv260_pfm" (standalone, A53 core 0)
#     from the XSA exported by tcl/build.tcl
#   - Application component "pmod_gpio" using sw/src/main.c
#
# Run from the sw/ directory:
#   vitis -s create_vitis.py
#
# NOTE (Windows): the workspace defaults to C:\kv260_ws, NOT a
# folder inside this repo. The standalone BSP build creates paths
# ~180 chars deep and fails against the Windows 260-char MAX_PATH
# limit when the workspace sits under a long repo path. Override
# with the VITIS_WORKSPACE environment variable if needed.
#
# Outputs (after build):
#   <workspace>/pmod_gpio/build/pmod_gpio.elf
#   FSBL: <workspace>/kv260_pfm/export/kv260_pfm/sw/boot/fsbl.elf
# ============================================================

import os
import shutil
import vitis

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if os.name == "nt":
    WORKSPACE = os.environ.get("VITIS_WORKSPACE", r"C:\kv260_ws")
else:
    WORKSPACE = os.environ.get("VITIS_WORKSPACE",
                               os.path.join(SCRIPT_DIR, "workspace"))
XSA = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "vivado", "kv260_base.xsa"))

PFM_NAME = "kv260_pfm"
APP_NAME = "pmod_gpio"

if not os.path.exists(XSA):
    raise FileNotFoundError(
        f"XSA not found: {XSA}\n"
        "Build the hardware first:  vivado -mode tcl -source tcl/build.tcl"
    )

# Start from a clean workspace so the script is re-runnable
shutil.rmtree(WORKSPACE, ignore_errors=True)
os.makedirs(WORKSPACE, exist_ok=True)

client = vitis.create_client()
client.set_workspace(path=WORKSPACE)

# ---- Platform component (standalone BSP on A53 core 0) ----
platform = client.create_platform_component(
    name=PFM_NAME,
    hw_design=XSA,
    os="standalone",
    cpu="psu_cortexa53_0",
    generate_dtb=False,
)
platform.build()

xpfm = os.path.join(WORKSPACE, PFM_NAME, "export", PFM_NAME, PFM_NAME + ".xpfm")
if not os.path.exists(xpfm):
    raise FileNotFoundError(
        f"Platform build did not produce {xpfm} - check the build log above"
    )

# ---- Application component ----
app = client.create_app_component(
    name=APP_NAME,
    platform=xpfm,
    domain="standalone_psu_cortexa53_0",
)
app.import_files(from_loc=os.path.join(SCRIPT_DIR, "src"),
                 files=["main.c"],
                 dest_dir_in_cmp="src")
app.build()

elf = os.path.join(WORKSPACE, APP_NAME, "build", APP_NAME + ".elf")
print(f"Done. ELF: {elf}")
