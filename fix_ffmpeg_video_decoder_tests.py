#!/usr/bin/env python3
"""Fix FFplay input frame-rate arguments and align tests with decoder policy.

Usage:
  python fix_ffmpeg_video_decoder_tests.py [repository-root]

Idempotent. Both files are validated before either one is written.
"""
from __future__ import annotations

import argparse
from pathlib import Path


def transform(
    content: str,
    old: str,
    new: str,
    description: str,
) -> tuple[str, bool]:
    # Test for the old block first: the new block may be contained within it.
    if old in content:
        count = content.count(old)
        if count != 1:
            raise RuntimeError(
                f"Expected exactly one occurrence of {description}; found {count}."
            )
        return content.replace(old, new, 1), True
    if new in content:
        return content, False
    raise RuntimeError(
        f"Could not find the expected source block for {description}. "
        "Your checkout may differ from the version this repair targets."
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "repository_root",
        nargs="?",
        default=".",
        help="FlutterAuto repository root (default: current directory)",
    )
    root = Path(parser.parse_args().repository_root).resolve()

    decoder = root / (
        "headunit_runtime/lib/src/media/presentation/src/ffmpeg_video_decoder.dart"
    )
    tests = root / (
        "headunit_runtime/test/media/presentation/ffmpeg_video_decoder_test.dart"
    )

    for path in (decoder, tests):
        if not path.is_file():
            raise FileNotFoundError(f"Required file not found: {path}")

    decoder_original = decoder.read_text(encoding="utf-8")
    tests_original = tests.read_text(encoding="utf-8")

    decoder_updated, decoder_changed = transform(
        decoder_original,
        """      '-f',
      demuxer,
      '-i',
      inputUri.toString(),
      '-an',
      '-sn',
""",
        """      '-f',
      demuxer,
      // Raw H.264/HEVC does not carry a reliable presentation time base.
      // Apply the configured input frame rate before opening the demuxer.
      '-r',
      configuration.framesPerSecond.toString(),
      '-i',
      inputUri.toString(),
      '-an',
      '-sn',
      '-dn',
""",
        "input frame-rate and data-stream arguments",
    )

    tests_updated, tests_changed = transform(
        tests_original,
        """      expect(arguments, contains('-framedrop'));
      expect(arguments, contains('-hwaccel'));
""",
        """      expect(arguments, contains('-framedrop'));
      // Do not force -hwaccel: the Windows FFplay texture path selects its
      // supported renderer itself, and forcing hardware decoding can break it.
      expect(arguments, isNot(contains('-hwaccel')));
""",
        "hardware-acceleration expectation",
    )

    # Write only after both source blocks have been found and validated.
    if decoder_changed:
        decoder.write_text(decoder_updated, encoding="utf-8", newline="")
    if tests_changed:
        tests.write_text(tests_updated, encoding="utf-8", newline="")

    print("FFmpeg decoder repair complete.")
    print(f"  decoder: {'updated' if decoder_changed else 'already fixed'}")
    print(f"  tests:   {'updated' if tests_changed else 'already fixed'}")
    print("No GitHub files were changed.")


if __name__ == "__main__":
    main()
