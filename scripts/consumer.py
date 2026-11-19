"""Install the packaged source into a clean local workspace and consume its API."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import tempfile
import zipfile
from prepare_package import prepare_readme

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--exe", type=Path)
    parser.add_argument("--registry", action="store_true", help="resolve the published 0.1.0 from Mooncakes")
    args = parser.parse_args()
    if not args.registry:
        prepare_readme()
        subprocess.run(["moon", "package"], cwd=ROOT, check=True, timeout=120)
    archive = ROOT / "_build/publish/Ag108-MoonHyperPart-0.1.0.zip"
    workspace_parent = ROOT / ".agent-workplace"
    workspace_parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="consumer-", dir=workspace_parent) as name:
        workspace = Path(name).resolve()
        assert workspace.is_relative_to(workspace_parent.resolve())
        if not args.registry:
            package = workspace / "package"
            package.mkdir()
            with zipfile.ZipFile(archive) as zipped:
                names = {member.filename.replace("\\", "/") for member in zipped.infolist()}
                assert "README.mbt.md" in names and "README.md" not in names
                assert "项目申报书.md" not in names
                for member in zipped.infolist():
                    path = (package / member.filename.replace("\\", "/")).resolve()
                    assert path.is_relative_to(package.resolve()), member.filename
                zipped.extractall(package)
        consumer = workspace / "consumer"
        shutil.copytree(ROOT / "examples/cli_consumer", consumer,
                        ignore=shutil.ignore_patterns("_build", ".mooncakes"))
        if args.registry:
            subprocess.run(["moon", "update"], cwd=consumer, check=True, timeout=120)
        else:
            (workspace / "moon.work").write_text('members = ["package", "consumer"]\n', encoding="utf-8")
        results = []
        assignments = []
        for target in ("native", "js", "wasm-gc"):
            process = subprocess.run(["moon", "run", ".", "--target", target,
                                      "--target-dir", str(workspace / "build"), "--deny-warn"],
                                     cwd=consumer, text=True, capture_output=True, timeout=120)
            assert process.returncode == 0, (target, process.stdout, process.stderr)
            lines = [line for line in process.stdout.splitlines() if line.strip()]
            report_line = next(i for i, line in enumerate(lines) if line.startswith("{"))
            results.append(json.loads(lines[report_line]))
            assignments.append([int(line) for line in lines[report_line + 1:]])
        assert results[0] == results[1] == results[2]
        assert assignments[0] == assignments[1] == assignments[2]
        assert results[0]["cut_net"] == "1" and len(assignments[0]) == 6
        if args.exe:
            part = workspace / "cli.part"
            process = subprocess.run([str(args.exe.resolve()), "partition", str(ROOT / "testdata/tiny_optimum.hgr"),
                                      "--output", str(part), "--capacities", "3,3", "--starts", "1"],
                                     text=True, capture_output=True, timeout=30)
            assert process.returncode == 0, (process.stdout, process.stderr)
            assert json.loads(process.stdout) == results[0]
            assert [int(line) for line in part.read_text().splitlines()] == assignments[0]
    source = "registry" if args.registry else "packaged"
    print(f"Clean {source} consumer passed on native, JS and wasm-gc; CLI and library agree")


if __name__ == "__main__":
    main()
