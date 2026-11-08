import unittest
from tool.release.release_extension import release_version, android_build_number, chrome_version


class ReleaseVersionTests(unittest.TestCase):
    def test_release_version(self):
        self.assertEqual(release_version("v0.2.0"), "0.2.0")
        self.assertEqual(release_version("v65535.0.1"), "65535.0.1")

    def test_invalid_tags(self):
        for tag in (
            "0.2.0", "v0.0.0", "v65536.0.1", "v01.2.3", "v1.2", "v1.2.3.4",
            "v1.2.3-beta", "v1.2.3+build", "v1.2.3\n", "$(echo v1.2.3)",
        ):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release_version(tag)

    def test_android_build_number_from_tag(self):
        self.assertEqual(android_build_number("v1.2.3"), 1002003)
        self.assertEqual(android_build_number("v1.0.0"), 1000000)
        self.assertEqual(android_build_number("v1.0.1"), 1000001)
        self.assertEqual(android_build_number("v0.0.1"), 1)
        self.assertEqual(android_build_number("v2099.999.999"), 2099999999)

    def test_invalid_android_build_numbers(self):
        for tag in ("v1.1000.0", "v1.0.1000", "v2101.0.0"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                android_build_number(tag)

    def test_source_manifest_version(self):
        for version in ("1", "1.0", "1.0.0", "1.2.3.4", "0.0.0.1"):
            chrome_version(version)
        for version in ("0", "0.0.0.0", "1.02", "1.2.3.4.5", "65536", "1-beta", 1):
            with self.subTest(version=version), self.assertRaises(ValueError):
                chrome_version(version)
