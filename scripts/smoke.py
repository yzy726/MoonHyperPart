"""Exercise the native CLI through files. All inputs are original fixtures."""
from pathlib import Path
import argparse
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--exe", type=Path, required=True)
    args = parser.parse_args()
    executable = args.exe.resolve()

    def run(arguments, expected=0):
        process = subprocess.run([str(executable), *map(str, arguments)], cwd=ROOT,
                                 text=True, capture_output=True, timeout=30)
        assert process.returncode == expected, (arguments, process.returncode,
                                                process.stdout, process.stderr)
        return json.loads(process.stdout)

    with tempfile.TemporaryDirectory(prefix="moonhyperpart-smoke-") as directory:
        temporary = Path(directory)
        tiny = ROOT / "testdata/tiny_optimum.hgr"
        part = temporary / "tiny.part"
        report = temporary / "tiny.json"
        info = run(["inspect", tiny])
        assert (info["vertices"], info["edges"], info["pins"]) == (6, 3, 8)
        result = run(["partition", tiny, "--output", part, "--report", report,
                      "--capacities", "3,3", "--starts", "1", "--seed", "726"])
        assert result["cut_net"] == "1" and result["run"]["initial_cut"] == "21"
        assert result["part_weights"] == ["3", "3"]
        assert json.loads(report.read_text()) == result
        checked = run(["verify", tiny, part, "--capacities", "3,3"])
        assert checked["cut_net"] == result["cut_net"]
        again = temporary / "again.part"
        repeated = run(["partition", tiny, "--output", again,
                        "--capacities", "3,3", "--starts", "1", "--seed", "726"])
        assert again.read_bytes() == part.read_bytes() and repeated == result
        weighted = run(["partition", ROOT / "testdata/weighted_balance.hgr",
                        "--output", temporary / "weighted.part", "--capacities", "3,3"])
        assert weighted["part_weights"] == ["3", "3"] and weighted["cut_net"] == "0"
        invalid = temporary / "duplicate.hgr"
        invalid.write_text("1 2\n1 1\n", encoding="utf-8")
        rejected = temporary / "rejected.part"
        error = run(["partition", invalid, "--output", rejected], expected=2)
        assert error["code"] == "duplicate_pin" and error["line"] == 2
        assert not rejected.exists()
        exhausted = temporary / "exhausted.part"
        error = run(["partition", ROOT / "testdata/repair_budget.hgr", "--output", exhausted,
                     "--capacities", "15,15", "--starts", "1", "--search-nodes", "0"], expected=3)
        assert error["code"] == "search_exhausted" and not exhausted.exists()
        bad_part = temporary / "bad.part"
        bad_part.write_text("0\n0\n0\n0\n0\n0\n", encoding="utf-8")
        assert run(["verify", tiny, bad_part, "--capacities", "6,6"], expected=4)["code"] == "empty_partition"
        saved = part.read_bytes()
        run(["partition", tiny, "--output", part], expected=5)
        assert part.read_bytes() == saved
        blocked = temporary / "blocked.part"
        run(["partition", tiny, "--output", blocked, "--report", report], expected=5)
        assert not blocked.exists() and json.loads(report.read_text()) == result
        uncommitted = temporary / "uncommitted.json"
        run(["partition", tiny, "--report", uncommitted,
             "--output", temporary / "missing" / "fail.part"], expected=5)
        assert not uncommitted.exists() and not list(temporary.glob("*.moonhyperpart.tmp"))
        malformed = temporary / "malformed.hgr"
        malformed.write_bytes(b"1 2\n\xff\n")
        assert run(["inspect", malformed], expected=2)["code"] == "utf8"
        assert run(["inspect", tiny, "--max-input-bytes", "1"], expected=2)["code"] == "limit"
        assert run(["partition", tiny, "--output", rejected,
                    "--capacities", "2,2"], expected=3)["code"] == "impossible"
        assert not rejected.exists()
    print("Native CLI smoke passed: inspect, roundtrip, determinism, weighted balance, invalid input, budget, external verification, existing output")


if __name__ == "__main__":
    main()
