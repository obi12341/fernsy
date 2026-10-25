# Proposal

## Why

Releases go out with placeholder text. Without `RELEASE_NOTES.md`, the GitHub release says
only "Signed with Developer ID and notarized by Apple", and Sparkle's update window lists raw
commit subjects. Half of those are noise ("Mark … done", "Archive …"), and the rest is
developer English. For 1.1.1, the two user-visible changes (the Recordings sidebar fix,
automatic updates) are buried among them.

The user wants release notes without a manual writing step. The sentence a user should read is
written when the change is made, and the release workflow collects it.

## What Changes

- **Release notes as commit trailers.** A commit with a user-visible change carries
  `Release-Note-de: …` and `Release-Note-en: …`. Internal commits (task marks, archives, CI,
  refactoring) carry none.
- **The release workflow collects them.** For a tag, it collects the trailers since the
  previous `v*` tag; for a nightly, since the last release tag. From them it builds:
  - the GitHub release text: German and English sections;
  - Sparkle's update notes, per language (`xml:lang`), so the window shows the system
    language.

  `RELEASE_NOTES.md` is no longer used.
- **A safety net.** When a range has no trailers, the run shows a warning and falls back to
  the commit subjects, filtered from task marks and archive commits. A release never goes out
  empty, and a forgotten trailer is visible in the run.
- **The rule is written down.** `CLAUDE.md` gets the rule with format and example, so every
  session follows it, plus a memory entry. The README documents it for manual commits.
- **1.1.1 once by hand.** Its GitHub text gets the two user-visible points, because those
  commits predate the trailers.

Out of scope:
- App Store Connect "What's New" (stays manual for now);
- AI-generated notes;
- a hard per-commit check.

## Capabilities

### New Capabilities
- (none)

### Modified Capabilities
- `distribution`: "Release build in GitHub Actions" takes its release text from commit
  trailers; "Signed update feeds" carries per-language notes.
- `app-updates`: "Checking for updates" shows the notes in the system language.

## Impact

- `.github/workflows/release.yml`: collecting trailers (`git log --format='%(trailers:…)'`),
  release text, localized appcast notes, warning and fallback.
- `CLAUDE.md`: the commit rule.
- README (release section).
- Memory: a feedback entry.
- No app code. Sparkle already chooses `<description xml:lang>` by the preferred languages.
