#!/usr/bin/env python3
"""
scripts/tui.py — easy-synthseg TUI
Brain MRI Segmentation Pipeline interactive menu (Rich-based)
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from typing import Optional

from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.text import Text
from rich.prompt import Prompt

# ── Project root (parent of this script) ────────────────────────────────────
PROJECT_ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = PROJECT_ROOT / ".env"

console = Console()

# ── .env helpers ─────────────────────────────────────────────────────────────

def load_env() -> dict[str, str]:
    """Read .env and return key→value dict (no shell expansion)."""
    env: dict[str, str] = {}
    if not ENV_FILE.exists():
        return env
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            k, _, v = line.partition("=")
            env[k.strip()] = v.strip()
    return env


def save_env_key(key: str, value: str) -> None:
    """Update (or append) a single key in .env."""
    if not ENV_FILE.exists():
        ENV_FILE.write_text(f"{key}={value}\n")
        return
    lines = ENV_FILE.read_text().splitlines()
    updated = False
    new_lines = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith(f"{key}=") or stripped.startswith(f"{key} ="):
            new_lines.append(f"{key}={value}")
            updated = True
        else:
            new_lines.append(line)
    if not updated:
        new_lines.append(f"{key}={value}")
    ENV_FILE.write_text("\n".join(new_lines) + "\n")


# ── Pipeline status ──────────────────────────────────────────────────────────

def get_status(env: dict[str, str]) -> dict[str, bool]:
    """Check which pipeline steps have been completed."""
    data_root = Path(env.get("DATA_ROOT", ""))
    sid = env.get("SID", "")
    deriv = data_root / "derivatives" / sid

    statuses: dict[str, bool] = {}

    # DICOM: directory exists and contains ≥1 file
    dicom_dir = data_root / "dicom" / sid
    statuses["DICOM"] = dicom_dir.is_dir() and any(dicom_dir.iterdir())

    # NIfTI: *.nii.gz exists
    nifti_dir = data_root / "nifti" / sid
    statuses["NIfTI"] = nifti_dir.is_dir() and bool(list(nifti_dir.glob("*.nii.gz")))

    # SynthSR
    synthsr_file = deriv / "synthsr" / f"{sid}_synthsr.nii.gz"
    statuses["SynthSR"] = synthsr_file.is_file()

    # SynthSeg
    synthseg_file = deriv / "synthseg" / f"{sid}_synthseg.nii.gz"
    statuses["SynthSeg"] = synthseg_file.is_file()

    # FastSurfer: directory exists
    fastsurfer_dir = deriv / "fastsurfer" / sid
    statuses["FastSurfer"] = fastsurfer_dir.is_dir()

    return statuses


def status_icon(done: bool) -> str:
    return "✓" if done else "✗"


# ── Rendering ─────────────────────────────────────────────────────────────────

def render_header(env: dict[str, str], statuses: dict[str, bool]) -> Panel:
    sid = env.get("SID", "(not set)")
    pipeline_line = Text()
    for step, label in [
        ("DICOM", "DICOM"),
        ("NIfTI", "NIfTI"),
        ("SynthSR", "SynthSR"),
        ("SynthSeg", "SynthSeg"),
        ("FastSurfer", "FastSurfer"),
    ]:
        icon = status_icon(statuses.get(step, False))
        color = "green" if statuses.get(step, False) else "red"
        pipeline_line.append(f"  {icon} {label}", style=color)

    content = Text()
    content.append(f"  Subject : {sid}\n", style="cyan")
    content.append("  Pipeline:")
    content.append_text(pipeline_line)

    return Panel(content, title="[bold blue]easy-synthseg[/bold blue]  Brain MRI Segmentation Pipeline", border_style="blue")


def render_menu() -> Panel:
    lines = (
        "  [bold cyan][1][/bold cyan] Run Full Pipeline\n"
        "  [bold cyan][2][/bold cyan] Run Individual Step\n"
        "  [bold cyan][3][/bold cyan] View Output Status\n"
        "  [bold cyan][4][/bold cyan] Change Subject\n"
        "  [bold cyan][5][/bold cyan] Setup Environment\n"
        "  [bold cyan][q][/bold cyan] Quit"
    )
    return Panel(lines, title="[bold]Menu[/bold]", border_style="blue")


def print_main_screen(env: dict[str, str], statuses: dict[str, bool]) -> None:
    console.clear()
    console.print(render_header(env, statuses))
    console.print(render_menu())


# ── Script runner ────────────────────────────────────────────────────────────

def run_script(script_path: Path, extra_env: Optional[dict[str, str]] = None) -> int:
    """Run a bash script, streaming output live. Returns exit code."""
    run_env = os.environ.copy()
    if extra_env:
        run_env.update(extra_env)

    console.print(f"\n[dim]Running: bash {script_path.relative_to(PROJECT_ROOT)}[/dim]\n")
    try:
        result = subprocess.run(
            ["bash", str(script_path)],
            cwd=str(PROJECT_ROOT),
            env=run_env,
        )
        return result.returncode
    except FileNotFoundError:
        console.print(f"[red][ERR] Script not found: {script_path}[/red]")
        return 1


def handle_run_result(rc: int) -> None:
    if rc == 0:
        console.print(Panel("[green]Completed successfully.[/green]", border_style="green"))
    else:
        console.print(Panel(f"[red]Script exited with code {rc}.[/red]", border_style="red"))
    Prompt.ask("\nPress Enter to return to menu", default="")


# ── Menu actions ─────────────────────────────────────────────────────────────

def action_full_pipeline() -> None:
    console.print(Panel("[bold]Run Full Pipeline[/bold]\nThis will run [cyan]scripts/90_pipeline.sh[/cyan].", border_style="cyan"))
    confirm = Prompt.ask("Proceed? [y/N]", default="n")
    if confirm.lower() != "y":
        return
    rc = run_script(PROJECT_ROOT / "scripts" / "90_pipeline.sh")
    handle_run_result(rc)


INDIVIDUAL_STEPS: list[tuple[str, str, str]] = [
    ("10", "DICOM → NIfTI", "10_dicom2nifti.sh"),
    ("20", "Select NIfTI", "20_select_nifti.sh"),
    ("30", "SynthSR", "30_synthsr.sh"),
    ("40", "SynthSeg (Mac native)", "40_synthseg_native.sh"),
    ("40d", "SynthSeg (Docker/Linux)", "40_synthseg.sh"),
    ("50", "FastSurfer", "50_fastsurfer.sh"),
]


def action_individual_step() -> None:
    while True:
        console.clear()
        console.print(Panel("[bold]Run Individual Step[/bold]", border_style="cyan"))
        table = Table(show_header=False, box=None, padding=(0, 2))
        table.add_column("Key", style="cyan")
        table.add_column("Description")
        table.add_column("Script", style="dim")
        for key, label, script in INDIVIDUAL_STEPS:
            table.add_row(f"[{key}]", label, script)
        table.add_row("[b]", "Back", "")
        console.print(table)
        console.print()

        choice = Prompt.ask("Select step").strip().lower()
        if choice == "b":
            return

        matched = [s for s in INDIVIDUAL_STEPS if s[0] == choice]
        if not matched:
            console.print("[yellow]Unknown option.[/yellow]")
            continue

        _, label, script_name = matched[0]
        script_path = PROJECT_ROOT / "scripts" / script_name
        console.print(Panel(f"[bold]{label}[/bold]\n[cyan]scripts/{script_name}[/cyan]", border_style="cyan"))

        force_opt = Prompt.ask("Run with FORCE=1 (re-run even if output exists)? [y/N]", default="n")
        extra = {"FORCE": "1"} if force_opt.lower() == "y" else {}

        rc = run_script(script_path, extra_env=extra)
        handle_run_result(rc)
        return


def action_view_status(env: dict[str, str]) -> None:
    console.clear()
    sid = env.get("SID", "(not set)")
    data_root = Path(env.get("DATA_ROOT", ""))
    deriv = data_root / "derivatives" / sid

    statuses = get_status(env)

    table = Table(title=f"Output Status — Subject: {sid}", show_header=True, header_style="bold magenta")
    table.add_column("Step", style="bold")
    table.add_column("Status", justify="center")
    table.add_column("Path")

    path_map = {
        "DICOM": str(data_root / "dicom" / sid),
        "NIfTI": str(data_root / "nifti" / sid / "*.nii.gz"),
        "SynthSR": str(deriv / "synthsr" / f"{sid}_synthsr.nii.gz"),
        "SynthSeg": str(deriv / "synthseg" / f"{sid}_synthseg.nii.gz"),
        "FastSurfer": str(deriv / "fastsurfer" / sid),
    }

    for step in ["DICOM", "NIfTI", "SynthSR", "SynthSeg", "FastSurfer"]:
        done = statuses.get(step, False)
        icon = "[green]✓ Done[/green]" if done else "[red]✗ Missing[/red]"
        table.add_row(step, icon, path_map[step])

    console.print(table)
    Prompt.ask("\nPress Enter to return to menu", default="")


def action_change_subject(env: dict[str, str]) -> dict[str, str]:
    current = env.get("SID", "")
    console.print(Panel(f"Current subject: [cyan]{current}[/cyan]", border_style="cyan"))
    new_sid = Prompt.ask("Enter new Subject ID (or press Enter to cancel)").strip()
    if not new_sid:
        return env
    save_env_key("SID", new_sid)
    console.print(f"[green]SID updated to '{new_sid}'[/green]")
    env["SID"] = new_sid
    return env


def action_setup_env() -> None:
    script = PROJECT_ROOT / "scripts" / "setup_tf_metal_env.sh"
    console.print(Panel(
        "[bold]Setup Environment[/bold]\nThis will run [cyan]scripts/setup_tf_metal_env.sh[/cyan] "
        "to configure the [cyan]synthseg-metal[/cyan] conda environment (Mac only).",
        border_style="cyan",
    ))
    confirm = Prompt.ask("Proceed? [y/N]", default="n")
    if confirm.lower() != "y":
        return
    rc = run_script(script)
    handle_run_result(rc)


# ── Main loop ─────────────────────────────────────────────────────────────────

def main() -> None:
    env = load_env()

    while True:
        statuses = get_status(env)
        print_main_screen(env, statuses)
        console.print()

        try:
            choice = Prompt.ask("Select option").strip().lower()
        except (KeyboardInterrupt, EOFError):
            console.print("\n[dim]Bye.[/dim]")
            sys.exit(0)

        if choice == "q":
            console.print("[dim]Bye.[/dim]")
            sys.exit(0)
        elif choice == "1":
            action_full_pipeline()
        elif choice == "2":
            action_individual_step()
        elif choice == "3":
            action_view_status(env)
        elif choice == "4":
            env = action_change_subject(env)
        elif choice == "5":
            action_setup_env()
        else:
            console.print("[yellow]Unknown option. Please enter 1–5 or q.[/yellow]")
            Prompt.ask("Press Enter to continue", default="")


if __name__ == "__main__":
    main()
