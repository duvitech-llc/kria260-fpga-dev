# ============================================================
# Vitis Unified (2026.1) workspace creation script
#
# Creates:
#   - Platform component "kv260_pfm" (standalone, A53 core 0)
#     from the XSA exported by tcl/build.tcl
#   - Application component "board_test" from sw/board_test/
#
# Run from the sw/ directory:
#   vitis -s create_vitis.py        platform + application
#   vitis -s create_vitis.py app    application only (same hardware)
#
# NOTE (Windows): the workspace defaults to C:\kv260_ws, NOT a
# folder inside this repo. The standalone BSP build creates paths
# ~180 chars deep and fails against the Windows 260-char MAX_PATH
# limit when the workspace sits under a long repo path. Override
# with the VITIS_WORKSPACE environment variable if needed.
#
# Outputs (after build):
#   <workspace>/board_test/build/board_test.elf
#   FSBL: <workspace>/kv260_pfm/export/kv260_pfm/sw/boot/fsbl.elf
# ============================================================

import os
import shutil
import stat
import sys
import vitis

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if os.name == "nt":
    WORKSPACE = os.environ.get("VITIS_WORKSPACE", r"C:\kv260_ws")
else:
    WORKSPACE = os.environ.get("VITIS_WORKSPACE",
                               os.path.join(SCRIPT_DIR, "workspace"))
XSA = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "output", "kv260_base.xsa"))
SRC_DIR = os.path.join(SCRIPT_DIR, "board_test")

PFM_NAME = "kv260_pfm"
APP_NAME = "board_test"
OLD_COMPONENTS = ("pmod_gpio",)   # earlier name of the app

SRC_FILES = sorted(f for f in os.listdir(SRC_DIR) if f.endswith((".c", ".h")))

# "vitis -s create_vitis.py app": only re-import the sources and rebuild the
# application, on the platform already in the workspace (same hardware).
if "app" in sys.argv[1:]:
    client = vitis.create_client()
    client.set_workspace(path=WORKSPACE)
    app = client.get_component(name=APP_NAME)
    app.import_files(from_loc=SRC_DIR, files=SRC_FILES, dest_dir_in_cmp="src")
    app.build()
    elf = os.path.join(WORKSPACE, APP_NAME, "build", APP_NAME + ".elf")
    print(f"Done. ELF: {elf}")
    vitis.dispose()
    sys.exit(0)

if not os.path.exists(XSA):
    raise FileNotFoundError(
        f"XSA not found: {XSA}\n"
        "Build the hardware first:  vivado -mode batch -source tcl/build.tcl"
    )

# Clean workspace handling. Do NOT rmtree an openable workspace: the
# Vitis server (started by `vitis -s` before this script runs) may hold
# a .lock inside it, so file-level deletion races the server. Instead,
# open it and remove stale components through the client API. Fall back
# to rmtree only when the workspace metadata is unopenable/corrupt -
# with a handler for the read-only files (SDT .dtsi etc.) the platform
# export leaves behind, which plain rmtree cannot delete on Windows.
def _clear_readonly_and_retry(func, path, _exc):
    os.chmod(path, stat.S_IWRITE)
    func(path)


def _force_rmtree(path):
    if sys.version_info >= (3, 12):
        shutil.rmtree(path, onexc=_clear_readonly_and_retry)
    else:
        shutil.rmtree(path, onerror=_clear_readonly_and_retry)
    if os.path.isdir(path) and os.listdir(path):
        raise RuntimeError(
            f"Could not fully delete {path} - close any running Vitis/xsdb "
            "instances holding files there and re-run."
        )


client = vitis.create_client()

opened = False
if os.path.isdir(WORKSPACE):
    try:
        client.set_workspace(path=WORKSPACE)
        opened = True
        for comp in (APP_NAME, *OLD_COMPONENTS, PFM_NAME):
            try:
                client.delete_component(name=comp)
                print(f"Deleted stale component: {comp}")
            except Exception:
                pass
    except Exception as exc:
        if "already in use" in str(exc):
            raise SystemExit(
                f"The workspace {WORKSPACE} is in use by another Vitis server: close the "
                "Vitis IDE, or stop the leftover 'vitis-server' java.exe process that an "
                "earlier run of this script left behind, then run it again.")
        # Unopenable (e.g. wiped metadata) - remove and start fresh
        _force_rmtree(WORKSPACE)

if not opened:
    os.makedirs(WORKSPACE, exist_ok=True)
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
app.import_files(from_loc=SRC_DIR,
                 files=SRC_FILES,
                 dest_dir_in_cmp="src")
app.build()

elf = os.path.join(WORKSPACE, APP_NAME, "build", APP_NAME + ".elf")
if not os.path.exists(elf):
    raise RuntimeError(f"App build failed - {elf} was not produced")
print(f"Done. ELF: {elf}")

# Stop the Vitis server this script started, so the workspace lock is
# released (a server left running makes the next run fail with "workspace
# already in use").
try:
    client.close()
except Exception:
    pass
vitis.dispose()
