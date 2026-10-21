import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from email.message import Message
from unittest.mock import MagicMock, patch


spec = importlib.util.spec_from_file_location("wooting_update", sys.argv.pop(1))
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class WootingUpdateTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.release_file = Path(directory.name) / "release.json"
        self.original = '{"version": "0.5.0", "hash": "old pin"}\n'
        self.release_file.write_text(self.original)
        self.headers = Message()
        self.headers["Content-Disposition"] = (
            "attachment; filename=Wooting.Background.Service_0.5.1_amd64.AppImage"
        )
        response = MagicMock()
        response.__enter__.return_value.headers = self.headers
        opener_patch = patch.object(updater, "urlopen", return_value=response)
        self.urlopen = opener_patch.start()
        self.addCleanup(opener_patch.stop)
        self.digest = "sha256-" + "A" * 43 + "="
        run_patch = patch.object(
            updater.subprocess, "run",
            return_value=subprocess.CompletedProcess([], 0, json.dumps({"hash": self.digest})),
        )
        self.run = run_patch.start()
        self.addCleanup(run_patch.stop)

    def test_update_fetches_the_discovered_version_and_records_its_hash(self):
        updater.update(self.release_file)
        self.assertEqual(
            json.loads(self.release_file.read_text()),
            {"version": "0.5.1", "hash": self.digest},
        )
        self.assertEqual(
            self.run.call_args.args[0][-1], updater.DOWNLOAD_URL + "&version=0.5.1"
        )
        self.assertEqual(list(self.release_file.parent.iterdir()), [self.release_file])

    def test_same_version_keeps_the_existing_pin_without_downloading(self):
        self.headers.replace_header(
            "Content-Disposition",
            "attachment; filename=Wooting.Background.Service_0.5.0_amd64.AppImage",
        )
        updater.update(self.release_file)
        self.run.assert_not_called()
        self.assertEqual(self.release_file.read_text(), self.original)

    def test_unknown_filename_preserves_the_pin(self):
        self.headers.replace_header("Content-Disposition", "attachment; filename=error.html")
        with self.assertRaises(ValueError):
            updater.update(self.release_file)
        self.run.assert_not_called()
        self.assertEqual(self.release_file.read_text(), self.original)

    def test_discovery_failure_preserves_the_pin(self):
        self.urlopen.side_effect = OSError("upstream unavailable")
        with self.assertRaises(OSError):
            updater.update(self.release_file)
        self.run.assert_not_called()
        self.assertEqual(self.release_file.read_text(), self.original)

    def test_download_failure_preserves_the_pin(self):
        self.run.side_effect = subprocess.CalledProcessError(1, ["nix"])
        with self.assertRaises(subprocess.CalledProcessError):
            updater.update(self.release_file)
        self.assertEqual(self.release_file.read_text(), self.original)

    def test_invalid_hash_preserves_the_pin(self):
        self.run.return_value.stdout = json.dumps({"hash": "sha256-too-short"})
        with self.assertRaises(ValueError):
            updater.update(self.release_file)
        self.assertEqual(self.release_file.read_text(), self.original)


unittest.main()
