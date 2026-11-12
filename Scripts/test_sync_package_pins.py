#!/usr/bin/env python3
"""Self check for sync-package-pins.py: python3 Scripts/test_sync_package_pins.py"""
import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "sync-package-pins.py"
spec = importlib.util.spec_from_file_location("sync_package_pins", SCRIPT)
pins = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pins)


def pin(identity, version):
    return {
        "identity": identity,
        "kind": "remoteSourceControl",
        "location": f"https://github.com/example/{identity}",
        "state": {"revision": f"{identity}-{version}", "version": version},
    }


APP = {p["identity"]: p for p in [pin("swift-collections", "1.7.5"), pin("swift-syntax", "604.0.0")]}


class SyncTests(unittest.TestCase):
    def test_a_drifted_pin_takes_the_app_version(self):
        drifted, data = pins.sync({"pins": [pin("swift-collections", "1.7.6")]}, APP)
        self.assertEqual(drifted, ["swift-collections"])
        self.assertEqual(data["pins"][0]["state"]["version"], "1.7.5")

    def test_a_package_file_keeps_only_its_own_pins(self):
        drifted, data = pins.sync({"pins": [pin("swift-collections", "1.7.5")]}, APP)
        self.assertEqual(drifted, [])
        self.assertEqual([p["identity"] for p in data["pins"]], ["swift-collections"])

    def test_the_workspace_gets_the_app_pins_added_and_extras_dropped(self):
        drifted, data = pins.sync({"pins": [pin("swift-collections", "1.7.5"), pin("gone", "1.0.0")]}, APP, complete=True)
        self.assertEqual(drifted, ["swift-syntax", "gone"])
        self.assertEqual(data["pins"], list(APP.values()))

    def test_an_up_to_date_workspace_has_no_drift(self):
        drifted, _ = pins.sync({"pins": list(APP.values())}, APP, complete=True)
        self.assertEqual(drifted, [])

    def test_the_app_pins_are_not_shared_with_the_result(self):
        _, data = pins.sync({"pins": []}, APP, complete=True)
        data["pins"][0]["state"]["version"] = "changed"
        self.assertEqual(APP["swift-collections"]["state"]["version"], "1.7.5")


if __name__ == "__main__":
    unittest.main()
