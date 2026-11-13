#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Origins AI Watcher — external diagnostic assistant for BO22 / Plutonium T6.

This program observes the game window and user-selected logs, audits local GSC
source files, records evidence, and (optionally) asks a local Ollama model to
interpret the collected evidence. It does not inject input, modify game memory,
or control bots.

Core features use only the Python standard library. Screen capture requires
mss; OCR is optional and requires pytesseract + a local Tesseract installation.
"""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import hashlib
import json
import os
import queue
import re
import sys
import threading
import time
import traceback
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable, Iterable, Optional

APP_NAME = "Origins AI Watcher"
VERSION = "1.1.0"

# ---------------------------------------------------------------------------
# Shared utilities
# ---------------------------------------------------------------------------

def now_iso() -> str:
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")


def safe_read(path: Path, limit: int = 3_000_000) -> str:
    try:
        with path.open("r", encoding="utf-8", errors="replace") as f:
            return f.read(limit)
    except OSError:
        return ""


def emit_jsonl(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value or "").strip()


def sha1_text(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8", errors="replace")).hexdigest()


@dataclass
class Finding:
    severity: str
    area: str
    title: str
    detail: str
    evidence: list[str] = field(default_factory=list)
    confidence: str = "medium"
    kind: str = "static"


@dataclass
class AuditReport:
    created_at: str
    project: str
    files_scanned: int
    function_count: int
    findings: list[Finding]
    area_evidence: dict[str, list[str]]
    syntax_checks: list[str]
    source_hash: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "created_at": self.created_at,
            "project": self.project,
            "files_scanned": self.files_scanned,
            "function_count": self.function_count,
            "findings": [asdict(x) for x in self.findings],
            "area_evidence": self.area_evidence,
            "syntax_checks": self.syntax_checks,
            "source_hash": self.source_hash,
        }


# ---------------------------------------------------------------------------
# GSC source auditor — evidence discovery, not a compiler
# ---------------------------------------------------------------------------

GSC_FUNCTION_RE = re.compile(
    r"(?m)^\s*(?:[A-Za-z_][A-Za-z0-9_]*\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*"
    r"\(([^;{}\n]*(?:\n[^;{}]*)?)\)\s*\{"
)

AREAS: dict[str, tuple[str, ...]] = {
    "Origins quest coordinator": ("quest_origins", "origins_quest", "little_lost_girl"),
    "Generators": ("generator", "capture_zone", "capture_start"),
    "Shovel and dig sites": ("shovel", "dig_site", "digspot", "dig_spot", "excavat"),
    "Staff parts and assembly": ("staff_part", "elemental_staff", "craft_staff", "staff_pickup", "staff_build"),
    "Wind Staff puzzle": (
        "wind_staff", "wind_ring", "smoke_detector", "wind_turbine",
        "staff_air_zm", "air_puzzle_1_complete", "air_puzzle_2_complete",
        "a_ceiling_rings", "puzzle_smoke_origin", "puzzle_smoke_dest",
    ),
    "Ice Staff puzzle": ("ice_staff", "ice_gem", "tombstone", "ice_stone"),
    "Lightning Staff puzzle": ("lightning_staff", "piano", "relay_switch", "lightning_relay"),
    "Fire Staff puzzle": ("fire_staff", "torch", "soul_chest", "sacrifice"),
    "Giant robots": ("robot", "hatch_foot", "trig_stomp", "robot_head"),
    "Tank and tank jumps": (
        "trig_use_tank", "trig_tank_station_call", "b_already_on_tank",
        "entity_on_tank", "vol_on_tank_watch", "tank_board", "tank_ride",
        "tank_station", "tank_exit", "tank_jump_down_spots",
    ),
    "Crazy Place and portals": ("crazy_place", "crazyplace", "portal", "gramophone"),
    "Crypt orb and discs": ("crypt", "orb", "disc_rotation", "disc"),
    "Maxis Drone and main quest": ("maxis_drone", "maxisdrone", "drone", "little_lost_girl"),
    "Shield and buildables": ("shield", "buildable", "craftable", "tomb_shield"),
    "Bot movement and navigation": ("setgoal", "hasgoal", "atgoal", "cancelgoal", "wander", "bot_move"),
    "Combat, aim and firing": ("bot_combat", "best_enemy", "lookat", "allowattack", "pressattack", "aim"),
    "Survival and revives": ("bot_should_flee", "bot_flee", "revive", "laststand", "last_stand", "health_fraction"),
    "Quest mode / last zombie": ("quest", "living_zombie", "zombie_count", "allowattack", "attack"),
}


def strip_gsc_comments_and_strings(source: str, preserve_strings: bool = False) -> str:
    """Strip comments, optionally retaining quoted strings for GSC evidence search.

    The default form blanks strings so structural parsing ignores braces inside
    quotes. The evidence form preserves strings because GSC target names,
    weapon names and quest flags are often stored as string literals.
    """
    out: list[str] = []
    i = 0
    state = "code"
    quote = ""
    while i < len(source):
        ch = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""
        if state == "code":
            if ch == "/" and nxt == "/":
                state = "line_comment"; out.extend("  "); i += 2; continue
            if ch == "/" and nxt == "*":
                state = "block_comment"; out.extend("  "); i += 2; continue
            if ch in ("\"", "'"):
                state = "string"; quote = ch
                out.append(ch if preserve_strings else " ")
                i += 1
                continue
            out.append(ch); i += 1
        elif state == "line_comment":
            if ch == "\n":
                out.append("\n"); state = "code"
            else: out.append(" ")
            i += 1
        elif state == "block_comment":
            if ch == "*" and nxt == "/":
                out.extend("  "); i += 2; state = "code"
            else:
                out.append("\n" if ch == "\n" else " "); i += 1
        else:  # string
            if ch == "\\" and i + 1 < len(source):
                if preserve_strings:
                    out.extend((ch, source[i + 1]))
                else:
                    out.extend("  ")
                i += 2
            elif ch == quote:
                out.append(ch if preserve_strings else " ")
                i += 1
                state = "code"
            else:
                out.append(ch if preserve_strings else ("\n" if ch == "\n" else " "))
                i += 1
    return "".join(out)

def extract_functions(path: Path, source: str) -> list[tuple[str, str, int]]:
    clean = strip_gsc_comments_and_strings(source)
    funcs: list[tuple[str, str, int]] = []
    for match in GSC_FUNCTION_RE.finditer(clean):
        name = match.group(1)
        if name.lower() in {"if", "else", "for", "foreach", "while", "switch", "do", "wait", "return"}:
            continue
        brace = clean.find("{", match.start(), match.end())
        depth = 0
        end = None
        for pos in range(brace, len(clean)):
            if clean[pos] == "{": depth += 1
            elif clean[pos] == "}":
                depth -= 1
                if depth == 0:
                    end = pos + 1
                    break
        if end is not None:
            line = clean.count("\n", 0, match.start()) + 1
            # Preserve string literals in the extracted body for evidence
            # matching while continuing to use the string-blanked copy above
            # for accurate brace matching.
            raw_body = strip_gsc_comments_and_strings(
                source[match.start():end], preserve_strings=True
            )
            funcs.append((name, raw_body, line))
    return funcs


def audit_project(project: Path) -> AuditReport:
    findings: list[Finding] = []
    evidence: dict[str, list[str]] = {}
    syntax: list[str] = []
    if not project.exists() or not project.is_dir():
        return AuditReport(now_iso(), str(project), 0, 0,
            [Finding("error", "project", "Project folder not found", f"The selected folder does not exist: {project}", confidence="high")],
            {}, ["No source checks performed."], "")

    gsc_files = [p for p in project.rglob("*.gsc") if not any(x in p.parts for x in (".git", "node_modules", "build", "dist"))]
    if not gsc_files:
        detail = (
            "The selected folder contains no .gsc files. You selected the watcher deployment folder, "
            "not the BO22 source checkout. Select the repository root containing "
            "'zm_bo2_bots.gsc' and 'zm_bo2_bots_map_origins.gsc'. "
            "In the app, click Browse beside BO22 project folder."
        )
        return AuditReport(
            now_iso(), str(project), 0, 0,
            [Finding("error", "source", "No GSC files found", detail,
                     ["Expected: zm_bo2_bots.gsc", "Expected: zm_bo2_bots_map_origins.gsc"],
                     "high")],
            {}, ["No source checks performed because no GSC files were found."], ""
        )

    all_functions: list[tuple[str, str, str, int]] = []
    combined_hash_parts: list[str] = []
    for path in gsc_files:
        src = safe_read(path, 8_000_000)
        rel = str(path.relative_to(project))
        combined_hash_parts.append(rel + "\n" + src)
        clean = strip_gsc_comments_and_strings(src)
        # Delimiter sanity check only; this does not parse GSC grammar.
        counts = {c: clean.count(c) for c in "{}()[]"}
        if counts["{"] != counts["}"]:
            syntax.append(f"{rel}: brace count mismatch ({{={counts['{']}, }}={counts['}']})")
        if counts["("] != counts[")"]:
            syntax.append(f"{rel}: parenthesis count mismatch ((={counts['(']}, )={counts[')']})")
        if counts["["] != counts["]"]:
            syntax.append(f"{rel}: bracket count mismatch ([={counts['[']}, ]={counts[']']})")
        for name, body, line in extract_functions(path, src):
            all_functions.append((name, body, rel, line))

    if not syntax:
        syntax.append("No simple delimiter-count mismatch found. This is not a GSC compile check.")
    else:
        findings.append(Finding("warning", "syntax", "Possible delimiter mismatch", "A simple brace/parenthesis/bracket count differs. Inspect the indicated file; comments and strings are excluded, but this is not a compiler diagnostic.", syntax[:12], "medium"))

    # GSC functions are namespaced by script file. A common entrypoint such
    # as init() in zm_bo2_bots.gsc and zm_modmenu.gsc is not a duplicate
    # definition in the same script. Warn only when one file repeats a name.
    by_name_and_file: dict[tuple[str, str], list[int]] = collections.defaultdict(list)
    for name, _, rel, line in all_functions:
        by_name_and_file[(name, rel)].append(line)
    duplicates = {
        (name, rel): locations
        for (name, rel), locations in by_name_and_file.items()
        if len(locations) > 1
    }
    if duplicates:
        sample = [
            f"{name} in {rel}: lines {', '.join(str(x) for x in locations[:8])}"
            for (name, rel), locations in list(duplicates.items())[:12]
        ]
        findings.append(Finding(
            "warning", "functions", "Repeated function definition in the same GSC file",
            "The same function name appears more than once in a single script file. Check whether it is an intentional conditional/generated layout or an accidental duplicate.",
            sample, "medium"
        ))

    for area, needles in AREAS.items():
        hits: list[str] = []
        for name, body, rel, line in all_functions:
            hay = (name + " " + body).lower()
            matched = [n for n in needles if n.lower() in hay]
            if matched:
                hits.append(f"{name} ({rel}:{line}) [matched: {', '.join(matched[:3])}]")
        evidence[area] = hits[:14]
        if not hits:
            findings.append(Finding("warning", area, f"No clear source evidence found: {area}", "The auditor did not find a function name/body containing the expected terms. The behavior may exist under different names, in another included script, or be absent. Check manually.", list(needles), "low"))

    # Targeted cross-checks for common failure classes.
    origins_files = [p for p in gsc_files if "origins" in p.name.lower() or "tomb" in p.name.lower()]
    origins_text = "\n".join(
        strip_gsc_comments_and_strings(safe_read(p, 8_000_000), preserve_strings=True)
        for p in origins_files
    ).lower()
    all_text = "\n".join(
        strip_gsc_comments_and_strings(safe_read(p, 8_000_000), preserve_strings=True)
        for p in gsc_files
    ).lower()

    # Player-side stock tank signals, not just menu labels or zombie AI
    # animation identifiers such as tank_jump_up / tank_jump_down.
    tank_player_signals = {
        "tank use trigger": "trig_use_tank",
        "tank call-station trigger": "trig_tank_station_call",
        "player-on-tank state": "b_already_on_tank",
        "stock roof contact check": "entity_on_tank",
        "stock moving-roof entity": "vol_on_tank_watch",
    }
    tank_route_evidence = [
        label for label, token in tank_player_signals.items()
        if token in origins_text or token in all_text
    ]
    has_player_tank_route = (
        ("trig_use_tank" in origins_text or "trig_use_tank" in all_text) and
        (
            "entity_on_tank" in origins_text or "entity_on_tank" in all_text or
            "b_already_on_tank" in origins_text or "b_already_on_tank" in all_text
        )
    )
    if origins_files and not has_player_tank_route:
        missing = [label for label in tank_player_signals if label not in tank_route_evidence]
        findings.append(Finding(
            "critical", "tank", "No player-side Origins tank boarding / riding controller found",
            "The Origins bot sources contain tank menu/status references, but no visible player boarding and ride-state implementation. The stock tank path uses the moving roof (vol_on_tank_watch), the trig_use_tank trigger, and player state such as b_already_on_tank / entity_on_tank(). Zombie tank_jump_up/down animations are not a substitute for a player bot controller. Generic navigation alone cannot reliably board, ride, and leave the moving tank for the Lightning Staff part route.",
            [
                "Detected stock-player signals: " + (", ".join(tank_route_evidence) if tank_route_evidence else "none"),
                "Missing evidence: " + ", ".join(missing),
                "Origins source files: " + ", ".join(str(p.relative_to(project)) for p in origins_files),
            ],
            "high"
        ))

    # Does quest mode have any observable last-zombie preservation logic?
    quest_hits = [x for x in all_functions if "quest" in x[0].lower() or "quest" in x[1].lower()]
    quest_text = "\n".join(x[1] for x in quest_hits).lower()
    has_last_zombie = any(token in quest_text for token in ("living_zombie", "zombie_count", "alive_zombies", "getaispeciesarray")) and any(token in quest_text for token in ("allowattack", "pressattack", "attack"))
    if not has_last_zombie:
        findings.append(Finding("warning", "quest mode", "Last-zombie protection not clearly coupled to quest mode", "The source scan did not find both a living-zombie count signal and an attack-control signal in quest-related function bodies. The behavior may be implemented in a shared helper; verify in a live round that one zombie is preserved and that bots resume attacking after leaving Quest mode.", [f"Quest-related functions found: {len(quest_hits)}"], "low"))

    # Interactions should verify state, not only issue button presses.
    objective_funcs = [x for x in all_functions if any(t in x[0].lower() for t in ("quest", "robot", "staff", "tank", "generator", "dig", "drone", "portal"))]
    weak: list[str] = []
    for name, body, rel, line in objective_funcs:
        if len(body) < 120:
            continue
        verify_tokens = ("waittill", "isdefined", "hasgoal", "atgoal", "==", "!=", "getent", "getweapon", "notify")
        if not any(t in body for t in verify_tokens):
            weak.append(f"{name} ({rel}:{line})")
    if weak:
        findings.append(Finding("info", "objective verification", "Review objective functions with few visible state checks", "These functions contain task-related names but no obvious verification token in the extracted body. This heuristic can produce false positives; inspect whether each interaction waits for the stock state to change.", weak[:15], "low"))

    if "com_error" in all_text or "script runtime error" in all_text:
        findings.append(Finding("info", "source", "Runtime-error text exists in source tree", "The string may be documentation or logging. It is not proof of an active error; compare it with the session logs."))

    if len(all_functions) == 0 and gsc_files:
        findings.append(Finding("warning", "parser", "No function definitions recognized", "GSC formatting may differ from the auditor's simple parser. The source scan is incomplete."))

    if not findings:
        findings.append(Finding("info", "audit", "No heuristic source warnings", "The lightweight source scan did not identify a known pattern. This does not establish that gameplay behavior works."))

    return AuditReport(now_iso(), str(project), len(gsc_files), len(all_functions), findings, evidence, syntax, sha1_text("\n".join(combined_hash_parts)))


# ---------------------------------------------------------------------------
# Log monitoring and event classification
# ---------------------------------------------------------------------------

LOG_RULES: list[tuple[str, str, str, re.Pattern[str]]] = [
    ("critical", "GSC runtime", "GSC script runtime error", re.compile(r"script runtime error|runtime error in script|unknown function|unresolved external", re.I)),
    ("critical", "Game crash", "Plutonium / game crash signature", re.compile(r"COM_ERROR|fatal error|unhandled exception|EXCEPTION_ACCESS_VIOLATION|game has stopped", re.I)),
    ("error", "GSC compile", "GSC compile or load failure", re.compile(r"script compile error|could not load script|failed to load script|syntax error|bad syntax", re.I)),
    ("warning", "Entity / trigger", "Missing entity or trigger reference", re.compile(r"undefined is not an entity|entity .* not found|could not find.*trigger|invalid entity", re.I)),
    ("warning", "Bot lifecycle", "Bot may have entered downed / disconnect state", re.compile(r"laststand|downed|disconnect|client dropped|bot.*died|player.*died", re.I)),
    ("warning", "Navigation", "Navigation or goal failure signature", re.compile(r"no path|path blocked|goal failed|navigation failed|could not reach", re.I)),
    ("info", "Quest", "Quest / objective event", re.compile(r"robot|tank|staff|generator|crazy place|portal|drone|dig site|torch|piano|relay", re.I)),
]


class LogTailer:
    def __init__(self, folder: Path, callback: Callable[[dict[str, Any]], None]):
        self.folder = folder
        self.callback = callback
        self.positions: dict[str, tuple[int, int]] = {}
        self.seen_alerts: collections.deque[str] = collections.deque(maxlen=250)
        self.telemetry_state: dict[tuple[str, str], Any] = {}

    def poll(self) -> None:
        if not self.folder.exists():
            return
        candidates = []
        try:
            for p in self.folder.rglob("*"):
                if p.is_file() and p.suffix.lower() in {".log", ".txt", ".err", ".out"}:
                    try:
                        if p.stat().st_size <= 80_000_000:
                            candidates.append(p)
                    except OSError:
                        pass
        except OSError:
            return
        candidates.sort(key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
        for path in candidates[:30]:
            key = str(path.resolve())
            try:
                stat = path.stat()
                first_seen = key not in self.positions
                old_size, old_mtime_ns = self.positions.get(key, (0, 0))
                if first_seen:
                    # Inspect only the latest slice on startup; do not replay huge old logs.
                    old_size = max(0, stat.st_size - 100_000)
                if stat.st_size < old_size or stat.st_mtime_ns < old_mtime_ns:
                    old_size = 0  # log rotation/truncation
                if stat.st_size == old_size:
                    self.positions[key] = (old_size, stat.st_mtime_ns)
                    continue
                with path.open("rb") as f:
                    f.seek(old_size)
                    chunk = f.read(min(stat.st_size - old_size, 1_500_000))
                self.positions[key] = (old_size + len(chunk), stat.st_mtime_ns)
                decoded = chunk.decode("utf-8", errors="replace")
                for line in decoded.splitlines():
                    self._process_line(path, line)
            except OSError:
                continue

    def _process_line(self, path: Path, line: str) -> None:
        clean = normalize_text(line)
        if not clean:
            return
        payload: Optional[dict[str, Any]] = None
        has_telemetry = "ORIGINS_AI_EVENT=" in clean or "ORIGINS_AI_EVENT|" in clean
        if "ORIGINS_AI_EVENT=" in clean:
            raw_event = clean.split("ORIGINS_AI_EVENT=", 1)[1].strip()
            try:
                parsed = json.loads(raw_event)
                if isinstance(parsed, dict): payload = parsed
            except (json.JSONDecodeError, TypeError):
                payload = None
        elif "ORIGINS_AI_EVENT|" in clean:
            raw_event = clean.split("ORIGINS_AI_EVENT|", 1)[1]
            parsed_fields: dict[str, Any] = {}
            for field_text in raw_event.split("|"):
                if "=" not in field_text: continue
                key, value = field_text.split("=", 1)
                key, value = key.strip(), value.strip()
                if value.lower() in {"true", "false"}: parsed_fields[key] = value.lower() == "true"
                else:
                    try: parsed_fields[key] = int(value)
                    except ValueError:
                        try: parsed_fields[key] = float(value)
                        except ValueError: parsed_fields[key] = value
            if parsed_fields: payload = parsed_fields
        if has_telemetry:
            if payload is None:
                self.callback({"timestamp": now_iso(), "source": "log", "severity": "warning",
                    "area": "telemetry", "title": "Malformed structured telemetry record",
                    "detail": clean[:1200], "file": str(path)})
                return
            payload.setdefault("timestamp", now_iso())
            payload.setdefault("source", "gsc_telemetry")
            event_name = str(payload.get("event", "telemetry")).lower()
            payload.setdefault("area", "bot telemetry")
            if event_name == "objective_step":
                payload.setdefault("area", "Origins objective")
                payload.setdefault("title", f"Bot {payload.get('bot_id', '?')} working on {payload.get('objective', 'unknown objective')}")
            elif event_name == "bot_state":
                payload.setdefault("title", f"Bot {payload.get('bot_id', '?')} state snapshot")
            else:
                payload.setdefault("title", str(payload.get("event", "Structured GSC telemetry")))
            def as_number(value: Any) -> Optional[float]:
                try: return float(value)
                except (TypeError, ValueError): return None
            hp = as_number(payload.get("health"))
            danger = as_number(payload.get("danger"))
            if event_name in {"bot_down", "bot_died", "bot_death"} or (hp is not None and hp <= 0):
                payload["severity"] = "critical"
                payload["title"] = "Bot down/death telemetry"
            elif hp is not None and hp <= 25 and danger is not None and danger >= 5:
                payload["severity"] = "warning"
                payload["title"] = "Bot is critically low on health under pressure"
            ammo_clip = as_number(payload.get("ammo_clip"))
            ammo_stock = as_number(payload.get("ammo_stock"))
            if ammo_clip is not None and ammo_stock is not None and ammo_clip + ammo_stock <= 0:
                payload["severity"] = "warning"
                payload["title"] = "Bot reports no ammunition"
            last_zombies = as_number(payload.get("last_zombie_count"))
            fire_value = payload.get("is_firing", payload.get("fire_active"))
            firing = fire_value is True or fire_value == 1 or fire_value == "1"
            if str(payload.get("mode", "")).lower() == "quest" and last_zombies == 1 and firing:
                payload["severity"] = "warning"
                payload["title"] = "Quest-mode bot may be attacking the preserved last zombie"
            if str(payload.get("result", "")).lower() in {"failed", "failure", "timeout", "blocked"}:
                payload["severity"] = "warning"
                payload["title"] = f"Objective step failed: {payload.get('objective', 'unknown objective')}"
            idle_ms = as_number(payload.get("movement_idle_ms"))
            stationary_tasks = {"idle", "none", "combat", "generator_capture", "crazy_place_souls", "objective_interaction", "reviving", "building", "crafting"}
            if idle_ms is not None and idle_ms >= 15000 and str(payload.get("task", "")) not in stationary_tasks:
                payload["severity"] = "warning"
                payload["title"] = "Bot may be stuck while assigned to a task"
            payload.setdefault("severity", "info")
            payload.setdefault("detail", json.dumps(payload, ensure_ascii=False)[:1800])
            self.callback(payload)
            # Turn changes in global quest flags / bot inventory into explicit timeline events.
            if event_name == "bot_state":
                bot_id = str(payload.get("bot_id", "unknown"))
                map_name = str(payload.get("map", "unknown"))
                for field_name, field_value in payload.items():
                    if field_name.startswith("ee_") and field_value not in (-1, "-1", None):
                        state_key = (map_name, field_name)
                        previous = self.telemetry_state.get(state_key, None)
                        if previous is not None and previous != field_value:
                            self.callback({"timestamp": now_iso(), "source": "gsc_telemetry", "severity": "info",
                                "area": "Origins quest progression", "title": "Quest flag changed",
                                "detail": f"{field_name}: {previous} → {field_value}", "flag": field_name,
                                "old_value": previous, "new_value": field_value, "map": map_name})
                        self.telemetry_state[state_key] = field_value
                    if field_name.startswith("has_staff_"):
                        state_key = (f"bot:{bot_id}", field_name)
                        previous = self.telemetry_state.get(state_key, None)
                        if previous is not None and previous != field_value:
                            state_label = "picked up" if field_value in (1, True, "1") else "no longer holds"
                            self.callback({"timestamp": now_iso(), "source": "gsc_telemetry", "severity": "info",
                                "area": "Staff inventory", "title": f"Bot {bot_id} {state_label} {field_name.replace('has_staff_', '').title()} Staff",
                                "detail": f"{field_name}: {previous} → {field_value}"})
                        self.telemetry_state[state_key] = field_value

                    if field_name == "bot_on_tank":
                        state_key = (f"bot:{bot_id}", field_name)
                        previous = self.telemetry_state.get(state_key, None)
                        if previous is not None and previous != field_value:
                            state_label = "boarded" if field_value in (1, True, "1") else "left"
                            self.callback({"timestamp": now_iso(), "source": "gsc_telemetry", "severity": "info",
                                "area": "Origins tank", "title": f"Bot {bot_id} {state_label} the tank",
                                "detail": f"Stock b_already_on_tank state: {previous} → {field_value}"})
                        self.telemetry_state[state_key] = field_value

                    if field_name in {"tank_moving", "tank_cooldown", "tank_location"}:
                        state_key = (map_name, field_name)
                        previous = self.telemetry_state.get(state_key, None)
                        if previous is not None and previous != field_value:
                            self.callback({"timestamp": now_iso(), "source": "gsc_telemetry", "severity": "info",
                                "area": "Origins tank", "title": f"Tank {field_name.replace('_', ' ')} changed",
                                "detail": f"{field_name}: {previous} → {field_value}", "map": map_name})
                        self.telemetry_state[state_key] = field_value
            return
        matches = []
        for severity, area, title, pattern in LOG_RULES:
            if pattern.search(clean):
                matches.append((severity, area, title))
        for severity, area, title in matches:
            signature = sha1_text(area + clean[-400:])
            if signature in self.seen_alerts:
                continue
            self.seen_alerts.append(signature)
            self.callback({"timestamp": now_iso(), "source": "log", "severity": severity,
                           "area": area, "title": title, "detail": clean[:1200],
                           "file": str(path)})


# ---------------------------------------------------------------------------
# Window capture, lightweight visual activity check, and optional OCR
# ---------------------------------------------------------------------------

def list_windows() -> list[tuple[int, str, tuple[int, int, int, int]]]:
    if os.name != "nt":
        return []
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.windll.user32
    results: list[tuple[int, str, tuple[int, int, int, int]]] = []
    # WNDENUMPROC is not exported by ctypes.wintypes on all supported
    # Python/Windows versions (including standard CPython 3.11 builds).
    # Define the Win32 callback signature explicitly instead.
    WNDENUMPROC = ctypes.WINFUNCTYPE(
        wintypes.BOOL, wintypes.HWND, wintypes.LPARAM
    )

    EnumWindows = user32.EnumWindows
    EnumWindows.argtypes = [WNDENUMPROC, wintypes.LPARAM]
    EnumWindows.restype = wintypes.BOOL
    GetWindowTextLengthW = user32.GetWindowTextLengthW
    GetWindowTextW = user32.GetWindowTextW
    IsWindowVisible = user32.IsWindowVisible
    GetWindowRect = user32.GetWindowRect

    @WNDENUMPROC
    def callback(hwnd: int, lparam: int) -> bool:
        if IsWindowVisible(hwnd):
            n = GetWindowTextLengthW(hwnd)
            if n > 0:
                buf = ctypes.create_unicode_buffer(n + 1)
                GetWindowTextW(hwnd, buf, n + 1)
                title = buf.value.strip()
                rect = wintypes.RECT()
                if title and GetWindowRect(hwnd, ctypes.byref(rect)):
                    if rect.right - rect.left > 160 and rect.bottom - rect.top > 120:
                        results.append((int(hwnd), title, (rect.left, rect.top, rect.right, rect.bottom)))
        return True
    EnumWindows(callback, 0)
    return results


class ScreenObserver:
    def __init__(self, window_title: str, evidence_dir: Path,
                 event_callback: Callable[[dict[str, Any]], None],
                 status_callback: Callable[[str], None],
                 sample_seconds: float = 2.0, ocr_seconds: float = 8.0):
        self.window_title = window_title
        self.evidence_dir = evidence_dir
        self.event_callback = event_callback
        self.status_callback = status_callback
        self.sample_seconds = sample_seconds
        self.ocr_seconds = ocr_seconds
        self.stop_event = threading.Event()
        self.last_thumb: Optional[bytes] = None
        self.last_change = time.monotonic()
        self.last_ocr = 0.0
        self.last_round: Optional[int] = None
        self.last_text_hash = ""
        self.idle_alerted = False
        self.game_over_alerted = False
        self.capture_error_reported = False

    def stop(self) -> None:
        self.stop_event.set()

    def _choose_rect(self) -> Optional[tuple[int, int, int, int]]:
        if os.name != "nt":
            return None
        windows = list_windows()
        needle = self.window_title.lower().strip()
        candidates = [w for w in windows if needle and needle in w[1].lower()]
        if not candidates and not needle:
            candidates = [w for w in windows if any(x in w[1].lower() for x in ("plutonium", "black ops", "t6"))]
        if not candidates:
            return None
        # Prefer a title most closely matching the configured text.
        candidates.sort(key=lambda w: (needle not in w[1].lower(), -((w[2][2]-w[2][0])*(w[2][3]-w[2][1]))))
        return candidates[0][2]

    @staticmethod
    def _thumbnail_rgb(raw: bytes, width: int, height: int, target_w: int = 48, target_h: int = 27) -> bytes:
        # Sample one RGB pixel per grid cell. Avoids requiring OpenCV.
        out = bytearray()
        for gy in range(target_h):
            y = min(height - 1, int((gy + 0.5) * height / target_h))
            for gx in range(target_w):
                x = min(width - 1, int((gx + 0.5) * width / target_w))
                i = (y * width + x) * 3
                out.extend(raw[i:i+3])
        return bytes(out)

    def _ocr(self, raw: bytes, width: int, height: int) -> str:
        try:
            from PIL import Image, ImageEnhance, ImageOps
            import pytesseract
            image = Image.frombytes("RGB", (width, height), raw)
            image = ImageOps.grayscale(image)
            image = ImageEnhance.Contrast(image).enhance(1.8)
            return pytesseract.image_to_string(image, config="--psm 6")
        except ImportError:
            return ""
        except Exception as exc:
            self.status_callback(f"OCR unavailable: {exc}")
            return ""

    def _save_frame(self, raw: bytes, width: int, height: int, label: str) -> str:
        try:
            from PIL import Image
            self.evidence_dir.mkdir(parents=True, exist_ok=True)
            stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
            path = self.evidence_dir / f"{stamp}_{label}.png"
            Image.frombytes("RGB", (width, height), raw).save(path)
            return str(path)
        except Exception:
            return ""

    def _parse_ocr(self, text: str, frame_info: dict[str, Any]) -> None:
        clean = normalize_text(text)
        if not clean:
            return
        h = sha1_text(clean.lower())
        if h == self.last_text_hash:
            return
        self.last_text_hash = h
        # Round numbers appear in different HUD layouts; only accept explicit ROUND label.
        m = re.search(r"\bROUND\s*[:#-]?\s*(\d{1,2})\b", clean, re.I)
        if m:
            rnd = int(m.group(1))
            if self.last_round is not None and rnd != self.last_round:
                self.event_callback({"timestamp": now_iso(), "source": "screen", "severity": "info",
                    "area": "round", "title": "Round changed", "detail": f"Round {self.last_round} → {rnd}"})
            self.last_round = rnd
        lower = clean.lower()
        if "game over" in lower or "match ended" in lower:
            if not self.game_over_alerted:
                evidence = self._save_frame(frame_info["raw"], frame_info["width"], frame_info["height"], "game_over")
                self.event_callback({"timestamp": now_iso(), "source": "screen", "severity": "critical",
                    "area": "match", "title": "Game Over detected in HUD", "detail": clean[:500], "evidence": evidence})
                self.game_over_alerted = True
        else:
            self.game_over_alerted = False
        powerups = [x for x in ("zombie blood", "insta-kill", "max ammo", "double points", "fire sale", "carpenter", "nuke") if x in lower]
        if powerups:
            self.event_callback({"timestamp": now_iso(), "source": "screen", "severity": "info",
                "area": "HUD", "title": "Power-up text detected", "detail": ", ".join(powerups)})
        quest_terms = [x for x in ("staff", "generator", "robot", "tank", "crazy place", "maxis", "portal", "dig site", "torch", "piano") if x in lower]
        if quest_terms:
            self.event_callback({"timestamp": now_iso(), "source": "screen", "severity": "info",
                "area": "HUD / objective", "title": "Possible objective text visible", "detail": f"Terms: {', '.join(quest_terms)} | OCR: {clean[:500]}"})

    def run(self) -> None:
        try:
            import mss
        except ImportError:
            self.status_callback("Screen capture disabled: install requirements.txt (mss). Log/source auditing still works.")
            return
        self.status_callback("Screen observer running. Keep the game window visible and unobstructed.")
        with mss.mss() as sct:
            while not self.stop_event.is_set():
                rect = self._choose_rect()
                if not rect:
                    self.status_callback("Game window not found. Check the title filter and make sure Plutonium is open.")
                    self.stop_event.wait(3.0)
                    continue
                left, top, right, bottom = rect
                if right <= left or bottom <= top:
                    self.stop_event.wait(self.sample_seconds); continue
                try:
                    shot = sct.grab({"left": left, "top": top, "width": right-left, "height": bottom-top})
                    raw = shot.rgb
                    w, h = shot.width, shot.height
                    thumb = self._thumbnail_rgb(raw, w, h)
                    current = time.monotonic()
                    if self.last_thumb is not None:
                        # Fraction of sampled colour channels that changed meaningfully.
                        changed = sum(1 for a, b in zip(thumb, self.last_thumb) if abs(a-b) > 16)
                        ratio = changed / max(1, len(thumb))
                        if ratio > 0.018:
                            self.last_change = current
                            self.idle_alerted = False
                        elif current - self.last_change > 35 and not self.idle_alerted:
                            evidence = self._save_frame(raw, w, h, "possible_stall")
                            self.event_callback({"timestamp": now_iso(), "source": "screen", "severity": "warning",
                                "area": "movement", "title": "Screen appears visually unchanged for 35+ seconds",
                                "detail": "Possible bot/game stall, paused match, menu, or static view. This is only a visual heuristic; inspect the saved evidence and round state.",
                                "visual_change_ratio": round(ratio, 4), "evidence": evidence})
                            self.idle_alerted = True
                    self.last_thumb = thumb
                    if current - self.last_ocr >= self.ocr_seconds:
                        self.last_ocr = current
                        text = self._ocr(raw, w, h)
                        self._parse_ocr(text, {"raw": raw, "width": w, "height": h})
                    self.status_callback(f"Watching {right-left}×{bottom-top} game window | last visual change {int(current-self.last_change)}s ago")
                except Exception as exc:
                    if not self.capture_error_reported:
                        self.event_callback({"timestamp": now_iso(), "source": "screen", "severity": "warning",
                            "area": "capture", "title": "Could not capture game window", "detail": str(exc)})
                        self.capture_error_reported = True
                self.stop_event.wait(self.sample_seconds)


# ---------------------------------------------------------------------------
# Optional private local-model analysis through Ollama
# ---------------------------------------------------------------------------

class OllamaAnalyst:
    def __init__(self, endpoint: str = "http://127.0.0.1:11434", model: str = "qwen2.5:3b"):
        self.endpoint = endpoint.rstrip("/")
        self.model = model

    def analyze(self, audit: Optional[AuditReport], events: list[dict[str, Any]],
                latest_bot_states: Optional[dict[str, dict[str, Any]]] = None) -> str:
        prompt_data = {
            "source_audit": audit.to_dict() if audit else None,
            "recent_runtime_events": [e for e in events if e.get("event") != "bot_state"][-60:],
            "latest_bot_states": latest_bot_states or {},
        }
        system = (
            "You are a cautious BO2 Plutonium Origins GSC debugging analyst. Analyze only the evidence provided. "
            "Do not claim you saw hidden game state. Separate confirmed facts, hypotheses, and tests needed. "
            "Use file/function names when supplied. Prioritize crash-causing issues, bot death, aim/fire failures, "
            "stuck navigation, staff-part collection, tank jump route, robot entry, staff puzzles, quest mode, "
            "last-zombie preservation, generators, Crazy Place, Maxis Drone, and shield. Give a ranked action plan. "
            "Never suggest setting quest completion flags to fake progress."
        )
        body = json.dumps(prompt_data, ensure_ascii=False)[:70_000]
        payload = json.dumps({"model": self.model, "stream": False, "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": "Diagnose this BO22 Origins session and source audit:\n" + body},
        ]}).encode("utf-8")
        req = urllib.request.Request(self.endpoint + "/api/chat", data=payload,
            headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                data = json.loads(response.read().decode("utf-8", errors="replace"))
            return data.get("message", {}).get("content", "No analysis text returned.")
        except urllib.error.URLError as exc:
            raise RuntimeError(f"Cannot reach Ollama at {self.endpoint}: {exc}") from exc


# ---------------------------------------------------------------------------
# Session manager / reports
# ---------------------------------------------------------------------------

class Watcher:
    def __init__(self, output_dir: Path, ui_event: Callable[[dict[str, Any]], None], status: Callable[[str], None]):
        self.output_dir = output_dir
        self.ui_event = ui_event
        self.status = status
        self.events: list[dict[str, Any]] = []
        self.latest_bot_states: dict[str, dict[str, Any]] = {}
        self.audit: Optional[AuditReport] = None
        self.session_dir: Optional[Path] = None
        self.log_tailer: Optional[LogTailer] = None
        self.screen: Optional[ScreenObserver] = None
        self.stop_event = threading.Event()
        self.thread: Optional[threading.Thread] = None
        self.lock = threading.Lock()

    def new_session(self) -> Path:
        stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
        self.session_dir = self.output_dir / f"session_{stamp}"
        self.session_dir.mkdir(parents=True, exist_ok=True)
        emit_jsonl(self.session_dir / "events.jsonl", {"timestamp": now_iso(), "source": "watcher", "title": "Session started"})
        return self.session_dir

    def add_event(self, event: dict[str, Any]) -> None:
        event.setdefault("timestamp", now_iso())
        is_state_snapshot = event.get("source") == "gsc_telemetry" and event.get("event") == "bot_state"
        with self.lock:
            self.events.append(event)
            self.events = self.events[-8000:]
            if is_state_snapshot:
                self.latest_bot_states[str(event.get("bot_id", "unknown"))] = dict(event)
        if self.session_dir:
            emit_jsonl(self.session_dir / "events.jsonl", event)
        # Keep 2-second bot snapshots in the evidence file/state cache, not in the visible alert feed.
        if not is_state_snapshot:
            self.ui_event(event)

    def run(self, log_dir: Optional[Path], window_title: str, sample_seconds: float) -> None:
        if self.thread and self.thread.is_alive():
            return
        session = self.new_session()
        self.stop_event.clear()
        if log_dir:
            self.log_tailer = LogTailer(log_dir, self.add_event)
        self.screen = ScreenObserver(window_title, session / "evidence", self.add_event, self.status,
                                     sample_seconds=sample_seconds)
        screen_thread = threading.Thread(target=self.screen.run, daemon=True)
        screen_thread.start()
        def loop() -> None:
            while not self.stop_event.wait(1.0):
                if self.log_tailer:
                    self.log_tailer.poll()
        self.thread = threading.Thread(target=loop, daemon=True)
        self.thread.start()
        self.add_event({"source": "watcher", "severity": "info", "area": "session", "title": "Monitoring started",
                        "detail": f"Session folder: {session}"})

    def stop(self) -> None:
        self.stop_event.set()
        if self.screen:
            self.screen.stop()
        self.write_report()
        self.status("Monitoring stopped. Report saved.")

    def run_audit(self, project: Path) -> AuditReport:
        self.status("Auditing GSC files…")
        self.audit = audit_project(project)
        if self.session_dir is None:
            self.new_session()
        if self.session_dir:
            (self.session_dir / "source_audit.json").write_text(json.dumps(self.audit.to_dict(), indent=2, ensure_ascii=False), encoding="utf-8")
        for f in self.audit.findings:
            self.add_event({"timestamp": now_iso(), "source": "source_audit", "severity": f.severity,
                            "area": f.area, "title": f.title, "detail": f.detail, "evidence": f.evidence,
                            "confidence": f.confidence})
        self.status(f"Source audit complete: {self.audit.files_scanned} GSC files, {self.audit.function_count} functions, {len(self.audit.findings)} findings")
        return self.audit

    def write_report(self) -> Optional[Path]:
        if not self.session_dir:
            return None
        with self.lock:
            events = [e for e in self.events if e.get("event") != "bot_state"]
            latest_bot_states = dict(self.latest_bot_states)
        lines = [f"# {APP_NAME} — session report", "", f"Generated: {now_iso()}", f"Session: `{self.session_dir}`", ""]
        if self.audit:
            lines += ["## Source audit", f"- Project: `{self.audit.project}`", f"- GSC files: {self.audit.files_scanned}",
                      f"- Functions recognized: {self.audit.function_count}", f"- Source hash: `{self.audit.source_hash}`", ""]
            for f in self.audit.findings:
                lines += [f"### [{f.severity.upper()}] {f.title}", f"Area: {f.area} | Confidence: {f.confidence}", f.detail]
                if f.evidence:
                    lines += ["Evidence:"] + [f"- {x}" for x in f.evidence]
                lines.append("")
            lines += ["### Detected source areas", ""]
            for area, hits in self.audit.area_evidence.items():
                lines.append(f"- **{area}:** " + ("; ".join(hits[:5]) if hits else "No matching functions detected"))
            lines.append("")
        lines += ["## Latest bot telemetry snapshot", ""]
        if latest_bot_states:
            for bot_id, state in sorted(latest_bot_states.items()):
                lines.append(f"- **Bot {bot_id}:** mode={state.get('mode')} task={state.get('task')} health={state.get('health')}/{state.get('max_health')} weapon={state.get('weapon')} ammo={state.get('ammo_clip')}+{state.get('ammo_stock')} danger={state.get('danger')} nearest={state.get('nearest_dist')} last_zombies={state.get('last_zombie_count')} movement_idle_ms={state.get('movement_idle_ms')}")
                flags = {k: v for k, v in state.items() if k.startswith("ee_")}
                if flags: lines.append("  - Quest flags: " + ", ".join(f"{k}={v}" for k, v in flags.items()))
        else:
            lines.append("No structured GSC bot-state records received. Check that the telemetry branch is installed and the correct game log folder is selected.")
        lines += ["", "## Runtime and screen events", ""]
        if not events:
            lines.append("No runtime events recorded.")
        else:
            for e in events[-500:]:
                lines.append(f"- `{e.get('timestamp','')}` **{str(e.get('severity','info')).upper()} / {e.get('area','')}** — {e.get('title','')}: {e.get('detail','')}")
                if e.get("evidence"):
                    lines.append(f"  - Evidence: `{e['evidence']}`")
        lines += ["", "## Important limitations", "", "This report is diagnostic evidence, not proof of successful gameplay. OCR can misread HUD text; a static screen can mean pause/menu rather than a stuck bot; source heuristics do not compile GSC or inspect hidden game variables. Confirm important findings in a controlled Plutonium match.", ""]
        path = self.session_dir / "report.md"
        path.write_text("\n".join(lines), encoding="utf-8")
        return path


# ---------------------------------------------------------------------------
# Tkinter desktop UI
# ---------------------------------------------------------------------------

class App:
    def __init__(self, root: Any, project: Optional[str] = None, logs: Optional[str] = None):
        import tkinter as tk
        from tkinter import ttk
        self.tk = tk
        self.ttk = ttk
        self.root = root
        self.root.title(f"{APP_NAME} v{VERSION} — BO22 / Origins")
        self.root.geometry("1120x780")
        self.root.minsize(900, 620)
        self.events_queue: queue.Queue[tuple[str, Any]] = queue.Queue()
        self.output_dir = Path(__file__).resolve().parent / "origins_ai_sessions"
        self.watcher = Watcher(self.output_dir, lambda e: self.events_queue.put(("event", e)),
                               lambda s: self.events_queue.put(("status", s)))
        self.project_var = tk.StringVar(value=project or str(Path.cwd()))
        self.logs_var = tk.StringVar(value=logs or "")
        self.window_var = tk.StringVar(value="Plutonium")
        self.interval_var = tk.StringVar(value="2.0")
        self.ollama_url_var = tk.StringVar(value="http://127.0.0.1:11434")
        self.ollama_model_var = tk.StringVar(value="qwen2.5:3b")
        self.status_var = tk.StringVar(value="Ready. Audit your repository first, then start a match watch.")
        self._build()
        self._refresh_windows()
        self.root.after(250, self._drain_queue)
        self.root.protocol("WM_DELETE_WINDOW", self._close)

    def _build(self) -> None:
        tk, ttk = self.tk, self.ttk
        outer = ttk.Frame(self.root, padding=12); outer.pack(fill="both", expand=True)
        ttk.Label(outer, text="ORIGINS AI WATCHER", font=("Segoe UI", 17, "bold")).pack(anchor="w")
        ttk.Label(outer, text="Source auditor • live screen observer • log monitor • local AI analyst", foreground="#555").pack(anchor="w", pady=(0, 10))

        config = ttk.LabelFrame(outer, text="Observation settings", padding=10); config.pack(fill="x", pady=(0, 8))
        config.columnconfigure(1, weight=1)
        ttk.Label(config, text="BO22 project folder").grid(row=0, column=0, sticky="w", padx=(0, 8), pady=4)
        ttk.Entry(config, textvariable=self.project_var).grid(row=0, column=1, sticky="ew", pady=4)
        ttk.Button(config, text="Browse…", command=self._browse_project).grid(row=0, column=2, padx=(6, 0))
        ttk.Label(config, text="Plutonium / game log folder").grid(row=1, column=0, sticky="w", padx=(0, 8), pady=4)
        ttk.Entry(config, textvariable=self.logs_var).grid(row=1, column=1, sticky="ew", pady=4)
        ttk.Button(config, text="Browse…", command=self._browse_logs).grid(row=1, column=2, padx=(6, 0))
        ttk.Label(config, text="Game window title contains").grid(row=2, column=0, sticky="w", padx=(0, 8), pady=4)
        self.window_combo = ttk.Combobox(config, textvariable=self.window_var, values=["Plutonium", "Black Ops", "T6"], width=30)
        self.window_combo.grid(row=2, column=1, sticky="w", pady=4)
        ttk.Button(config, text="Find windows", command=self._refresh_windows).grid(row=2, column=2, padx=(6, 0))
        ttk.Label(config, text="Capture interval (seconds)").grid(row=3, column=0, sticky="w", padx=(0, 8), pady=4)
        ttk.Entry(config, textvariable=self.interval_var, width=8).grid(row=3, column=1, sticky="w", pady=4)

        buttons = ttk.Frame(outer); buttons.pack(fill="x", pady=(0, 8))
        ttk.Button(buttons, text="1. Audit GSC project", command=self._audit).pack(side="left", padx=(0, 6))
        ttk.Button(buttons, text="2. Start live watch", command=self._start).pack(side="left", padx=6)
        ttk.Button(buttons, text="Stop + save report", command=self._stop).pack(side="left", padx=6)
        ttk.Button(buttons, text="Ask local AI (Ollama)", command=self._ask_ai).pack(side="left", padx=6)
        ttk.Button(buttons, text="Open session folder", command=self._open_session).pack(side="right")

        ai = ttk.LabelFrame(outer, text="Optional private local AI (no cloud API)", padding=8); ai.pack(fill="x", pady=(0, 8))
        ttk.Label(ai, text="Ollama URL").pack(side="left")
        ttk.Entry(ai, textvariable=self.ollama_url_var, width=30).pack(side="left", padx=(5, 16))
        ttk.Label(ai, text="Model").pack(side="left")
        ttk.Entry(ai, textvariable=self.ollama_model_var, width=22).pack(side="left", padx=5)
        ttk.Label(ai, text="Optional: install Ollama and pull a small model; rule-based monitoring works without it.", foreground="#555").pack(side="left", padx=8)

        panes = ttk.Panedwindow(outer, orient="horizontal"); panes.pack(fill="both", expand=True)
        left = ttk.LabelFrame(panes, text="Live alerts / event timeline", padding=6)
        right = ttk.LabelFrame(panes, text="Current analysis", padding=6)
        panes.add(left, weight=3); panes.add(right, weight=2)
        self.events_text = tk.Text(left, wrap="word", height=20, font=("Consolas", 9), state="disabled")
        self.events_text.pack(fill="both", expand=True)
        self.analysis_text = tk.Text(right, wrap="word", height=20, font=("Segoe UI", 9), state="disabled")
        self.analysis_text.pack(fill="both", expand=True)
        self.status_label = ttk.Label(outer, textvariable=self.status_var, relief="sunken", anchor="w", padding=5)
        self.status_label.pack(fill="x", pady=(8, 0))

    def _append(self, widget: Any, text: str) -> None:
        widget.configure(state="normal")
        widget.insert("end", text + "\n")
        widget.see("end")
        widget.configure(state="disabled")

    def _browse_project(self) -> None:
        from tkinter import filedialog
        p = filedialog.askdirectory(title="Select BO22 repository folder")
        if p: self.project_var.set(p)

    def _browse_logs(self) -> None:
        from tkinter import filedialog
        p = filedialog.askdirectory(title="Select Plutonium / game log folder")
        if p: self.logs_var.set(p)

    def _refresh_windows(self) -> None:
        if os.name != "nt":
            self.status_var.set("Window selection is supported on Windows. Source audit and manual log analysis remain available.")
            return
        windows = list_windows()
        options = [f"{title}  [{hwnd}]" for hwnd, title, _ in windows if any(x in title.lower() for x in ("plutonium", "black ops", "t6"))]
        if options:
            self.window_combo.configure(values=options)
            self.window_var.set(options[0].split("  [")[0])
            self.status_var.set(f"Found {len(options)} likely game window(s).")
        else:
            self.status_var.set("No likely Plutonium window found. Open the game, then click Find windows.")

    def _audit(self) -> None:
        from tkinter import filedialog, messagebox
        project = Path(self.project_var.get()).expanduser()
        has_gsc = project.exists() and project.is_dir() and any(
            p.is_file() and p.suffix.lower() == ".gsc"
            for p in project.rglob("*.gsc")
            if not any(x in p.parts for x in (".git", "node_modules", "build", "dist"))
        )
        if not has_gsc:
            messagebox.showinfo(
                "Select the BO22 source folder",
                "The selected folder does not contain GSC source files.\\n\\n"
                "Choose the actual Tenslaster/bo22 repository root — the folder containing "
                "zm_bo2_bots.gsc and zm_bo2_bots_map_origins.gsc."
            )
            selected = filedialog.askdirectory(title="Select BO22 repository root (contains zm_bo2_bots.gsc)")
            if not selected:
                self.status_var.set("Source audit cancelled: select the BO22 repository folder first.")
                return
            project = Path(selected).expanduser()
            self.project_var.set(str(project))
        def work() -> None:
            report = self.watcher.run_audit(project)
            self.events_queue.put(("audit", report))
        threading.Thread(target=work, daemon=True).start()

    def _start(self) -> None:
        logs = Path(self.logs_var.get()).expanduser() if self.logs_var.get().strip() else None
        try: interval = max(0.5, min(10.0, float(self.interval_var.get())))
        except ValueError: interval = 2.0
        title = self.window_var.get().split("  [")[0].strip()
        self.watcher.run(logs, title, interval)

    def _stop(self) -> None:
        self.watcher.stop()
        path = self.watcher.write_report()
        if path:
            self._append(self.analysis_text, f"Report saved: {path}")

    def _ask_ai(self) -> None:
        endpoint = self.ollama_url_var.get().strip()
        model_name = self.ollama_model_var.get().strip()
        def work() -> None:
            try:
                model = OllamaAnalyst(endpoint, model_name)
                result = model.analyze(self.watcher.audit, self.watcher.events, self.watcher.latest_bot_states)
                self.events_queue.put(("ai", result))
            except Exception as exc:
                self.events_queue.put(("ai_error", str(exc)))
        self.status_var.set("Asking the configured local Ollama model…")
        threading.Thread(target=work, daemon=True).start()

    def _open_session(self) -> None:
        path = self.watcher.session_dir or self.output_dir
        path.mkdir(parents=True, exist_ok=True)
        try:
            if os.name == "nt": os.startfile(str(path))
            elif sys.platform == "darwin": os.system(f'open "{path}"')
            else: os.system(f'xdg-open "{path}"')
        except Exception as exc:
            self.status_var.set(str(exc))

    def _drain_queue(self) -> None:
        try:
            while True:
                kind, value = self.events_queue.get_nowait()
                if kind == "status": self.status_var.set(str(value))
                elif kind == "event":
                    severity = str(value.get("severity", "info")).upper()
                    self._append(self.events_text, f"[{value.get('timestamp','')}] [{severity}] {value.get('area','')} — {value.get('title','')}\n{value.get('detail','')}")
                elif kind == "audit":
                    self.analysis_text.configure(state="normal"); self.analysis_text.delete("1.0", "end")
                    report: AuditReport = value
                    self.analysis_text.insert("end", f"SOURCE AUDIT — {report.files_scanned} files / {report.function_count} functions\n\n")
                    for f in report.findings:
                        self.analysis_text.insert("end", f"[{f.severity.upper()}] {f.title}\n{f.detail}\n")
                        if f.evidence: self.analysis_text.insert("end", "Evidence: " + "; ".join(f.evidence[:5]) + "\n")
                        self.analysis_text.insert("end", "\n")
                    self.analysis_text.insert("end", "AREA COVERAGE (source matches only; not proof of functionality)\n")
                    for area, hits in report.area_evidence.items():
                        self.analysis_text.insert("end", f"\n{area}: " + (", ".join(x.split(" (")[0] for x in hits[:5]) if hits else "NOT FOUND"))
                    self.analysis_text.configure(state="disabled")
                elif kind == "ai":
                    self.analysis_text.configure(state="normal"); self.analysis_text.insert("end", "\n\nLOCAL AI ANALYSIS\n" + str(value) + "\n"); self.analysis_text.configure(state="disabled")
                    self.status_var.set("Local AI analysis complete.")
                elif kind == "ai_error": self.status_var.set("Local AI unavailable: " + str(value))
        except queue.Empty:
            pass
        self.root.after(250, self._drain_queue)

    def _close(self) -> None:
        self.watcher.stop()
        self.root.destroy()


def main() -> int:
    parser = argparse.ArgumentParser(description=APP_NAME)
    parser.add_argument("--project", help="BO22 repository folder")
    parser.add_argument("--logs", help="Plutonium / game log folder")
    parser.add_argument("--audit-only", action="store_true", help="Run a console source audit and exit")
    args = parser.parse_args()
    if args.audit_only:
        if not args.project:
            parser.error("--audit-only requires --project")
        report = audit_project(Path(args.project).expanduser())
        print(json.dumps(report.to_dict(), indent=2, ensure_ascii=False))
        return 0
    try:
        import tkinter as tk
        root = tk.Tk()
        App(root, args.project, args.logs)
        root.mainloop()
        return 0
    except Exception:
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())