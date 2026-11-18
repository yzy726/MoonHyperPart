"""Run the five documented examples from a fresh checkout."""
from pathlib import Path
import argparse
import json
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NAMES = ("tiny_optimum", "weighted_balance", "hmetis_roundtrip", "bad_input_and_budget", "cli_consumer")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("example", choices=(*NAMES, "all"))
    parser.add_argument("--exe", type=Path)
    args = parser.parse_args()
    selected = NAMES if args.example == "all" else (args.example,)
    executable = args.exe.resolve() if args.exe else None
    if any(name in selected for name in NAMES[2:]) and executable is None:
        subprocess.run(["moon", "run", "cmd/main", "--target", "native", "--target-dir",
                        "_build/examples", "--build-only", "--deny-warn"], cwd=ROOT, check=True, timeout=120)
        executable = ROOT / "_build/examples/native/debug/build/cmd/main/main.exe"

    def cli(arguments, expected=0):
        process = subprocess.run([str(executable), *map(str, arguments)], cwd=ROOT,
                                 capture_output=True, text=True, timeout=30)
        assert process.returncode == expected, (process.stdout, process.stderr)
        return json.loads(process.stdout)

    for name in selected:
        if name in NAMES[:2]:
            subprocess.run(["moon", "run", "examples/" + name, "--target", "native",
                            "--target-dir", "_build/examples", "--deny-warn"], cwd=ROOT, check=True, timeout=120)
        elif name == "cli_consumer":
            subprocess.run([sys.executable, str(ROOT / "scripts/consumer.py"), "--exe", str(executable)],
                           cwd=ROOT, check=True, timeout=180)
        else:
            with tempfile.TemporaryDirectory(prefix="moonhyperpart-example-") as directory:
                temporary = Path(directory)
                part = temporary / "result.part"
                if name == "hmetis_roundtrip":
                    graph = ROOT / "testdata/tiny_optimum.hgr"
                    solved = cli(["partition", graph, "--output", part, "--capacities", "3,3"])
                    checked = cli(["verify", graph, part, "--capacities", "3,3"])
                    assert checked["cut_net"] == solved["cut_net"] == "1"
                    print(json.dumps(checked))
                else:
                    graph = temporary / "duplicate.hgr"
                    graph.write_text("1 2\n1 1\n", encoding="utf-8")
                    invalid = cli(["partition", graph, "--output", part], expected=2)
                    exhausted = cli(["partition", ROOT / "testdata/repair_budget.hgr", "--output", part,
                                     "--capacities", "15,15", "--starts", "1", "--search-nodes", "0"], expected=3)
                    assert invalid["code"] == "duplicate_pin" and exhausted["code"] == "search_exhausted"
                    assert not part.exists()
                    print(json.dumps([invalid, exhausted]))
        print(name + " passed", flush=True)


if __name__ == "__main__":
    main()
