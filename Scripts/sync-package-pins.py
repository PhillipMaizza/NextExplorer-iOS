#!/usr/bin/env python3
"""Keep every Package.resolved on the app's dependency versions.

Each local package (and the CI only PackageTests.xcworkspace) keeps its own Package.resolved, so
running a package's tests could resolve different versions of TCA and friends than the app ships.
The app's Package.resolved is the source of truth: its graph includes every package's manifest,
so its pins satisfy all of them. This rewrites each other file's pins to the app's. The
PackageTests workspace also builds the app, and CI resolves it strictly from its file, so that file
gets the app's whole pin list (a dependency added to the app is added there too).

  python3 Scripts/sync-package-pins.py           rewrite drifted pins
  python3 Scripts/sync-package-pins.py --check   list drift and exit 1 if any (CI)

Run it after changing dependencies in Xcode (which updates the app's file).
"""
import argparse, json, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "NextExplorer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
WORKSPACE = ROOT / "PackageTests.xcworkspace/xcshareddata/swiftpm/Package.resolved"
TARGETS = sorted(ROOT.glob("Packages/*/Package.resolved")) + [WORKSPACE]


def load(path):
    return json.loads(path.read_text())


def dump(data):
    # Xcode's own layout: two space indent, " : " separators, trailing newline.
    return json.dumps(data, indent=2, separators=(",", " : ")) + "\n"


def sync(data, app_pins, complete=False):
    """(drifted identities, synced data) for one Package.resolved's data. `complete` makes its pin
    list exactly the app's: missing pins are added and pins the app no longer has are dropped."""
    drifted = []
    for pin in data["pins"]:
        source = app_pins.get(pin["identity"])
        if source and (pin["state"] != source["state"] or pin["location"] != source["location"]):
            drifted.append(pin["identity"])
            pin["state"] = source["state"]
            pin["location"] = source["location"]
    if complete:
        present = {pin["identity"] for pin in data["pins"]}
        drifted += sorted(set(app_pins) - present) + sorted(present - set(app_pins))
        data["pins"] = [json.loads(json.dumps(pin)) for pin in app_pins.values()]
    return drifted, data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="report drift and exit 1 instead of rewriting")
    args = parser.parse_args()

    app_pins = {pin["identity"]: pin for pin in load(APP)["pins"]}
    drift = 0
    for path in TARGETS:
        if not path.exists():
            continue
        drifted, data = sync(load(path), app_pins, complete=path == WORKSPACE)
        if not drifted:
            continue
        drift += 1
        print(f"{path.relative_to(ROOT)}: {', '.join(drifted)}")
        if not args.check:
            path.write_text(dump(data))
    if args.check and drift:
        print("Pins differ from the app's; run python3 Scripts/sync-package-pins.py", file=sys.stderr)
        return 1
    if not drift:
        print("All Package.resolved files match the app's pins")
    return 0


if __name__ == "__main__":
    sys.exit(main())
