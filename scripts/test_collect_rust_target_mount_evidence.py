#!/usr/bin/env python3
from __future__ import annotations

import unittest
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path


spec = spec_from_file_location(
    "collect_rust_target_mount_evidence",
    Path(__file__).with_name("collect-rust-target-mount-evidence.py"),
)
assert spec is not None and spec.loader is not None
module = module_from_spec(spec)
spec.loader.exec_module(module)
parse_events = module.parse_events
parse_observability_events = module.parse_observability_events
merge_events = module.merge_events
summarize = module.summarize


class CollectRustTargetMountEvidenceTest(unittest.TestCase):
    def test_reports_rolling_target_archive_growth(self) -> None:
        log = """
#8 boringcache cache mount hydrate cacheID="/cargo-target-linux-amd64-musl" status=hit archive="target-old" compressedBytes=10000000 transfer=stream total=1s
#19 boringcache cache mount publish cacheID="/cargo-target-linux-amd64-musl" status=archive_built compressedBytes=10000061 uncompressedBytes=50000000 files=120 archive=1s
#19 boringcache cache mount publish cacheID="/cargo-target-linux-amd64-musl" status=published compressedBytes=10000061 total=1s
"""
        payload = summarize(parse_events(log, "^/?cargo-target-"), "^/?cargo-target-")

        self.assertEqual(payload["classification"], "stable")
        self.assertEqual(payload["compressed_bytes_delta"], 61)
        self.assertEqual(payload["current_uncompressed_bytes"], 50_000_000)
        self.assertEqual(payload["current_files"], 120)
        self.assertTrue(payload["publish_complete"])

    def test_uses_terminal_publish_events_from_managed_trace(self) -> None:
        log = '''
#8 boringcache cache mount hydrate cacheID="/cargo-target-linux-amd64-musl" status=miss archive="target-new" http_status=404
'''
        trace = '''
{"operation":"cache_session_summary","buildkit":{"mountcache":{"samples":[{"event":"mountcache_publish_archive_built","cache_id":"/cargo-target-linux-amd64-musl","compressed_bytes":739526718,"uncompressed_bytes":3464012613,"file_count":8915},{"event":"mountcache_publish_done","cache_id":"/cargo-target-linux-amd64-musl","compressed_bytes":739526718,"uncompressed_bytes":3464012613,"file_count":8915}]}}}
'''
        pattern = "^/?cargo-target-"
        payload = summarize(
            merge_events(
                parse_events(log, pattern),
                parse_observability_events(trace, pattern),
            ),
            pattern,
        )

        self.assertEqual(payload["classification"], "seeded")
        self.assertEqual(payload["current_compressed_bytes"], 739_526_718)
        self.assertEqual(payload["current_files"], 8_915)
        self.assertTrue(payload["publish_complete"])

    def test_rejects_miss_without_terminal_publish_evidence(self) -> None:
        log = '''
#8 boringcache cache mount hydrate cacheID="/cargo-target-linux-amd64-musl" status=miss archive="target-new" http_status=404
'''
        events = parse_events(log, "^/?cargo-target-")

        with self.assertRaisesRegex(ValueError, "did not complete"):
            summarize(events, "^/?cargo-target-")

    def test_totals_each_platform_target_mount(self) -> None:
        log = """
#8 boringcache cache mount hydrate cacheID="/proteus-target-amd64" status=hit compressedBytes=10000000 uncompressedBytes=50000000 files=120
#9 boringcache cache mount hydrate cacheID="/proteus-target-arm64" status=hit compressedBytes=20000000 uncompressedBytes=90000000 files=220
#19 boringcache cache mount publish cacheID="/proteus-target-amd64" status=archive_built compressedBytes=10000061 uncompressedBytes=50000100 files=121
#19 boringcache cache mount publish cacheID="/proteus-target-amd64" status=published compressedBytes=10000061
#20 boringcache cache mount publish cacheID="/proteus-target-arm64" status=archive_built compressedBytes=20000039 uncompressedBytes=90000200 files=222
#20 boringcache cache mount publish cacheID="/proteus-target-arm64" status=published compressedBytes=20000039
"""
        pattern = "^/?proteus-target-"
        payload = summarize(parse_events(log, pattern), pattern)

        self.assertEqual(payload["classification"], "stable")
        self.assertEqual(payload["previous_compressed_bytes"], 30_000_000)
        self.assertEqual(payload["current_compressed_bytes"], 30_000_100)
        self.assertEqual(payload["compressed_bytes_delta"], 100)
        self.assertEqual(payload["current_uncompressed_bytes"], 140_000_300)
        self.assertEqual(payload["current_files"], 343)
        self.assertEqual(len(payload["mounts"]), 2)
        self.assertTrue(payload["publish_complete"])

    def test_requires_terminal_evidence_for_every_matching_mount(self) -> None:
        log = """
#8 boringcache cache mount hydrate cacheID="/proteus-target-amd64" status=miss
#9 boringcache cache mount hydrate cacheID="/proteus-target-arm64" status=miss
#19 boringcache cache mount publish cacheID="/proteus-target-amd64" status=archive_built compressedBytes=10000000 uncompressedBytes=50000000 files=120
#19 boringcache cache mount publish cacheID="/proteus-target-amd64" status=published compressedBytes=10000000
"""
        pattern = "^/?proteus-target-"

        with self.assertRaisesRegex(ValueError, "proteus-target-arm64"):
            summarize(parse_events(log, pattern), pattern)


if __name__ == "__main__":
    unittest.main()
