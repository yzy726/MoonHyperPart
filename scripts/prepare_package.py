"""Prepare the Mooncakes-only README after a GitHub checkout."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def prepare_readme(root=ROOT):
    target = root / "README.mbt.md"
    if target.exists():
        return target
    source = root / "README.md"
    content = source.read_bytes()
    try:
        with target.open("xb") as output:
            output.write(content)
    except FileExistsError:
        pass
    return target


if __name__ == "__main__":
    print("Mooncakes README ready: " + prepare_readme().name)
