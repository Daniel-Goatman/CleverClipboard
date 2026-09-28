#!/usr/bin/python3
"""Restart this checkout's menu-bar app and verify a fresh launch report."""

import argparse
import json
import os
import plistlib
import signal
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "CleverClipboard.app"
EXECUTABLE = APP / "Contents/MacOS/CleverClipboard"
STATUS = ROOT / "results/jev-app/launch-status.json"
PROCESS_SUFFIXES = ("/CleverClipboard.app/Contents/MacOS/CleverClipboard",
                    "/Cuekit.app/Contents/MacOS/LayaClipboard",
                    "/Jev Clipboard.app/Contents/MacOS/LayaClipboard",
                    "/Laya Clipboard.app/Contents/MacOS/LayaClipboard")


def belongs_to_checkout(executable):
    return executable.parents[3] == ROOT


def clipboard_processes():
    """Return CleverClipboard and legacy app processes by PID and exact executable path."""
    output = subprocess.check_output(["/bin/ps", "-axww", "-o", "pid=,command="], text=True)
    processes = {}
    for line in output.splitlines():
        fields = line.strip().split(maxsplit=1)
        if len(fields) != 2 or not fields[1].endswith(PROCESS_SUFFIXES):
            continue
        executable = Path(fields[1])
        app = executable.parents[2]
        try:
            with (app / "Contents/Info.plist").open("rb") as file:
                info = plistlib.load(file)
        except (OSError, ValueError, plistlib.InvalidFileException):
            continue
        if (info.get("CFBundleName") in ("CleverClipboard", "Cuekit", "Jev Clipboard", "Laya Clipboard")
                and info.get("CFBundleIdentifier") == "local.daniel.LayaClipboard"):
            processes[int(fields[0])] = executable
    return processes


def stop_processes(targets):
    for pid, executable in targets.items():
        # Recheck immediately before signaling, including the full path.
        if clipboard_processes().get(pid) == executable:
            os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        live = clipboard_processes()
        if not any(live.get(pid) == path for pid, path in targets.items()):
            return
        time.sleep(0.2)
    raise RuntimeError(f"Clipboard process did not stop: {list(targets)}. Quit it from its menu, then retry.")


def fresh_report(pids, started):
    try:
        report = json.loads(STATUS.read_text())
    except (OSError, ValueError):
        return None
    if (
        report.get("pid") in pids
        and report.get("timestamp", 0) >= started - 1
        and report.get("bundle") == str(APP)
    ):
        return report
    return None


def launch(replace_other):
    if not EXECUTABLE.is_file():
        raise RuntimeError("App bundle is missing. Run ./build.sh first.")

    processes = clipboard_processes()
    others = {pid: path for pid, path in processes.items() if not belongs_to_checkout(path)}
    if others and not replace_other:
        paths = "\n".join(f"  PID {pid}: {path}" for pid, path in others.items())
        raise RuntimeError(
            "Another CleverClipboard/legacy app can own the Smart Paste shortcut:\n"
            f"{paths}\n"
            "Quit that instance or rerun with --replace-other-instances."
        )
    if processes:
        targets = processes if replace_other else {
            pid: path for pid, path in processes.items() if belongs_to_checkout(path)
        }
        stop_processes(targets)
        print(f"Stopped previous CleverClipboard/legacy process(es): {list(targets)}")

    started = time.time()
    subprocess.run(["/usr/bin/open", "-n", "-a", str(APP)], check=True)
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        pids = {pid for pid, path in clipboard_processes().items() if path == EXECUTABLE}
        report = fresh_report(pids, started)
        if report and (
            report.get("worker_ready")
            or report.get("worker_status") not in ("Starting TypeSafe…", "Checking TypeSafe connection…")
        ):
            print(f"Launched CleverClipboard (PID {report['pid']}).")
            print(f"TypeSafe: {report.get('worker_status', 'status unavailable')}")
            if not report.get("screen_capture", False):
                print("Screen Recording: off; visible-context OCR is unavailable.")
            issues = []
            if not report.get("worker_ready", False):
                issues.append("TypeSafe connection is unavailable")
            if not report.get("shortcut_registered", False):
                issues.append("⌘⇧V is held by another app")
            if not report.get("accessibility", False):
                issues.append("Accessibility permission is off")
            if issues:
                print("Smart Paste needs attention: " + "; ".join(issues), file=sys.stderr)
                return 2
            print("Smart Paste prerequisites: ready.")
            return 0
        time.sleep(0.2)
    raise RuntimeError("App launch did not produce a fresh running-process report.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replace-other-instances", action="store_true")
    parser.add_argument("--app", type=Path, help="Launch the exact installed app bundle instead of this checkout.")
    args = parser.parse_args()
    if args.app:
        APP = args.app.resolve()
        EXECUTABLE = APP / "Contents/MacOS/CleverClipboard"
        ROOT = APP.parent
        STATUS = (APP.parent / "results/jev-app/launch-status.json" if (APP.parent / "build.sh").is_file()
                  else Path.home() / "Library/Application Support/Jev Clipboard/results/jev-app/launch-status.json")
    try:
        sys.exit(launch(args.replace_other_instances))
    except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
        print(f"Launch failed: {error}", file=sys.stderr)
        sys.exit(1)
