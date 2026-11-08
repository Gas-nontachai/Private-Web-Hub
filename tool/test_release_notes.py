import unittest

from generate_release_notes import render_notes


class ReleaseNotesTests(unittest.TestCase):
    def test_initial_release_notes(self):
        notes = render_notes("v1.0.0", prior_tag="")
        self.assertIn("# Movie.exe v1.0.0", notes)
        self.assertIn(
            "https://github.com/Gas-nontachai/Private-Web-Hub/"
            "releases/download/v1.0.0/Movie.exe-v1.0.0.apk",
            notes,
        )
        self.assertIn(
            "https://github.com/Gas-nontachai/Private-Web-Hub/"
            "releases/download/v1.0.0/Movie.exe-v1.0.0.zip",
            notes,
        )
        self.assertIn("Android app for supported movie and series websites.", notes)
        self.assertIn("Chrome extension for supported movie and series websites.", notes)
        self.assertIn("/commits/v1.0.0", notes)
        self.assertNotIn("${", notes)

    def test_later_release_notes_use_compare_link_without_invented_changes(self):
        notes = render_notes("v1.2.0", prior_tag="v1.1.0")
        self.assertIn("# Movie.exe v1.2.0", notes)
        self.assertIn("/compare/v1.1.0...v1.2.0", notes)
        self.assertIn("No user-facing change details are provided", notes)
        self.assertNotIn("### Added", notes)
        self.assertIn("Movie.exe-v1.2.0.apk", notes)
        self.assertIn("Movie.exe-v1.2.0.zip", notes)

    def test_invalid_or_non_prior_tags_are_rejected(self):
        for tag in ("1.0.0", "v1.2", "v1.0.0-beta"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                render_notes(tag, prior_tag="")
        with self.assertRaisesRegex(ValueError, "lower version"):
            render_notes("v1.0.0", prior_tag="v1.0.0")


if __name__ == "__main__":
    unittest.main()
