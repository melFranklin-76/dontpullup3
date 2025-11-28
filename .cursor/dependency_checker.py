#!/usr/bin/env python3
import json
import os
import subprocess
import sys


def load_dependencies():
    config_dir = os.path.dirname(os.path.abspath(__file__))
    deps_path = os.path.join(config_dir, "dependencies.json")

    try:
        with open(deps_path, "r", encoding="utf-8") as deps_file:
            return json.load(deps_file)
    except FileNotFoundError:
        print(f"❌ Dependency config file not found at {deps_path}")
        sys.exit(1)


def gather_files(deps):
    changed = os.getenv("CURSOR_CHANGED_FILES", "").split(",")
    changed = [f for f in changed if f]  # remove empty strings
    to_check = set(changed)

    for path in changed:
        base = os.path.basename(path)
        if base in deps:
            to_check.update(deps[base])

    # Remove empty entries and ensure files exist
    return [f for f in to_check if f and os.path.exists(f)]


def lint_files(files):
    errors = []
    for path in files:
        result = subprocess.run(
            ["swiftlint", "lint", "--config", ".cursor/swiftlint_async.yml", "--path", path],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            errors.append(result.stdout.strip())
    return errors


def main():
    dependencies = load_dependencies()
    files_to_check = gather_files(dependencies)

    if not files_to_check:
        print("✅ No relevant files to check")
        return

    errors = lint_files(files_to_check)
    if errors:
        print("Dependency checks failed:")
        print("\n".join(errors))
        sys.exit(1)
    else:
        print("✅ All dependencies verified successfully")


if __name__ == "__main__":
    main()

