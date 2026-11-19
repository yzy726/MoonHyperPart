"""Measure a fixed corpus against the same deterministic balanced initial solver."""
from pathlib import Path
import argparse
import ctypes
import datetime
import hashlib
import json
import os
import platform
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def peak_working_set(process):
    if os.name != "nt":
        return None
    from ctypes import wintypes

    class MemoryCounters(ctypes.Structure):
        _fields_ = [("cb", wintypes.DWORD), ("faults", wintypes.DWORD)] + [
            (name, ctypes.c_size_t) for name in ("peak", "working", "peak_paged", "paged",
                                                "peak_nonpaged", "nonpaged", "pagefile", "peak_pagefile")]

    function = ctypes.windll.psapi.GetProcessMemoryInfo
    function.argtypes = [wintypes.HANDLE, ctypes.POINTER(MemoryCounters), wintypes.DWORD]
    function.restype = wintypes.BOOL
    counters = MemoryCounters()
    counters.cb = ctypes.sizeof(counters)
    if function(int(process._handle), ctypes.byref(counters), counters.cb):
        return counters.peak
    return None


def measured(arguments):
    started = time.perf_counter()
    process = subprocess.Popen(list(map(str, arguments)), cwd=ROOT, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    peak = peak_working_set(process)
    while process.poll() is None:
        reading = peak_working_set(process)
        if reading is not None:
            peak = max(peak or 0, reading)
        if time.perf_counter() - started > 30:
            process.kill()
            process.communicate()
            raise TimeoutError(arguments)
        time.sleep(0.001)
    stdout, stderr = process.communicate()
    seconds = time.perf_counter() - started
    assert process.returncode == 0, (arguments, process.returncode, stdout, stderr)
    return json.loads(stdout), {"seconds": seconds, "observed_peak_working_set_bytes": peak}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--exe", type=Path, required=True)
    parser.add_argument("--profile", choices=("debug", "release"), default="debug")
    parser.add_argument("--output", type=Path, default=ROOT / ".agent-workplace/benchmark.json")
    args = parser.parse_args()
    executable = args.exe.resolve()
    manifest_path = ROOT / "benchmarks/manifest.json"
    manifest = json.loads(manifest_path.read_text())
    rows = []
    strict_nontrivial = False
    with tempfile.TemporaryDirectory(prefix="moonhyperpart-benchmark-") as directory:
        temporary = Path(directory)
        for instance in manifest["instances"]:
            path = ROOT / instance["path"]
            data = path.read_bytes()
            assert b"\r\n" not in data, f"benchmark fixtures must use LF as specified by .gitattributes: {path}"
            assert hashlib.sha256(data).hexdigest() == instance["sha256"], path
            for seed in manifest["seeds"]:
                common = ["--capacities", ",".join(instance["capacities"]), "--seed", str(seed),
                          "--starts", str(manifest["starts"]), "--search-nodes", str(manifest["search_nodes"]),
                          "--moves", str(manifest["moves"]), "--swap-trials", str(manifest["swap_trials"]),
                          "--candidates", str(manifest["candidates"])]
                row = {"instance": instance["path"], "seed": seed, "sha256": instance["sha256"]}
                for phase, passes in (("baseline", 0), ("refined", manifest["passes"])):
                    part = temporary / f"{path.stem}-{seed}-{phase}.part"
                    report, timing = measured([executable, "partition", path, "--output", part,
                                               *common, "--passes", str(passes)])
                    verified, _ = measured([executable, "verify", path, part,
                                            "--capacities", ",".join(instance["capacities"])])
                    assert report["cut_net"] == verified["cut_net"]
                    assert report["part_weights"] == verified["part_weights"]
                    row[phase] = {"report": report, "measurement": timing}
                before = int(row["baseline"]["report"]["cut_net"])
                after = int(row["refined"]["report"]["cut_net"])
                assert after <= before, row
                if row["refined"]["report"]["vertices"] >= 12 and after < before:
                    strict_nontrivial = True
                row["strict_improvement"] = after < before
                rows.append(row)
    assert strict_nontrivial, "no fixed nontrivial instance improved"
    result = {"schema_version": 1, "measured_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "algorithm_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "platform": platform.platform(), "processor": platform.processor(), "logical_cpus": os.cpu_count(),
              "toolchain": subprocess.check_output(["moon", "version", "--all"], cwd=ROOT, text=True).strip(),
              "memory_method": "sampled GetProcessMemoryInfo.PeakWorkingSetSize" if os.name == "nt" else "unmeasured",
              "manifest_sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(), "runs": rows}
    result["build_profile"] = args.profile
    result["executable_sha256"] = hashlib.sha256(executable.read_bytes()).hexdigest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print(f"Benchmark passed: {len(rows)} runs, {sum(row['strict_improvement'] for row in rows)} strict improvements")
    for row in rows:
        print(row["instance"], row["seed"], row["baseline"]["report"]["cut_net"], "->", row["refined"]["report"]["cut_net"])


if __name__ == "__main__":
    main()
