# Recordo

A macOS menu bar app that quizzes you, four choices at a time, on terms you asked about in Claude Code.

## Public repository

This repository is public. Anyone can read what gets committed, including old commits, and removing it later means rewriting history.

- Keep personal and private information out of code, comments, docs, commit messages, and fixtures. That covers names of other projects or apps (write "an earlier app" instead), absolute local paths like `/Users/<name>/...` (use `~` or a placeholder), email addresses, tokens, and anything from a real `history.jsonl`, session log, or `cards.json`.
- Check the diff for these before committing.

## Docs

- `README.md`: install and usage (for people)
- `docs/guides/term-skill.md`: the `/term` skill (for people)
- `docs/superpowers/specs/2026-09-23-recordo-design.md`: design spec. It decides importing, quizzing, the data format, and failure behavior
- `docs/superpowers/plans/2026-09-23-recordo-core.md`: plan 1 (importing and cards)
- `docs/superpowers/plans/2026-09-23-recordo-ui.md`: plan 2 (screens)
- `docs/superpowers/plans/2026-09-24-recordo-cards.md`: plan 3 (card list)
- `design/README.md`: HTML prototypes of the screens and a list of design decisions
- `docs/index.html`: the landing page, served by GitHub Pages from `/docs` on `master`. It draws the quiz panel and the card list as HTML mockups with made-up cards, so when their English text or `Theme.swift` colors change, update the page too

## Where the code lives

In `Sources/RecordoKit/`:

- `RecordoApp.swift`: the entry point `RecordoMain` (`--sync-once`, `--quiz-now`) and the menu
- `AppModel.swift`: `tick()` every 60 seconds. It decides whether to run a sync or a quiz
- `QuizGate.swift`: whether a quiz may show (interval, Quiet Hours, Focus, full screen) and whether a sync is needed
- `Importer.swift`: the import flow. `HistoryReader` (`history.jsonl`) and `TranscriptReader` (session logs) read the input, and `ClaudeRunner` and `Prompts` build cards
- `Card.swift`, `CardStore.swift`, `TermKey.swift`, `Leitner.swift`: the card model, storage, term normalization, and box math
- `QuizSession.swift`, `Distractors.swift`: running one quiz and picking wrong answers
- `QuizPanel.swift`, `QuizView.swift`, `QuizNoticeView.swift`, `QuizStyle.swift`, `Theme.swift`: the quiz panel and its look
- `Settings.swift`: the Settings window and `tr()`, which switches UI text by language
- `CardListView.swift`: the card list window. `CardList` does the search, sorting, and paging by 100. `CardListWindow` is a plain AppKit window, so the global shortcut can open it from outside SwiftUI
- `Hotkey.swift`: the global shortcut. `Hotkey` is the stored value, `GlobalHotkey` registers it with Carbon, and `HotkeyRecorder` is the field in Settings

## Commands

- `make test`: `swift test`
- `make dev`: launch the development build. It uses `dev-cards.json`. To check the screens, launch with `"$(swift build --show-bin-path)/Recordo" --quiz-now` to get a quiz right away
- `make sync`: run one import with the real `claude -p` and write to `~/Library/Application Support/Recordo/dev-cards.json`. It refuses while the development build is running, because that build would overwrite the save with the cards it holds, so quit it first. The Recordo in `/Applications` uses `cards.json` and can keep running
- `make app`: build `build.noindex/Recordo.app`
- `make install`: copy the `.app` to `/Applications` and launch it. It uses the everyday `cards.json`, and the first launch starts a 30-day sync (about 30 minutes) in the background
- `make install-skill`: link `skills/term` to `~/.claude/skills/term`
- `make clean`: delete `.build` and `build.noindex`

## Conventions

- Build with SwiftPM only. Don't create an Xcode project file. Put logic in `RecordoKit` and keep `Sources/Recordo/main.swift` to the entry point.
- Tests use XCTest. Tests that call the real `claude -p` run only when `CLAUDE_LIVE=1`.
- Write test fixtures with made-up content. Don't paste real `history.jsonl` or session log content.
- Always call `claude -p` with `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1` and `--no-session-persistence`. Without them, Recordo imports its own prompts.
- Run `claude -p` in the empty folder `~/Library/Application Support/Recordo/claude-cwd/`, so it doesn't read a project's `.mcp.json` or CLAUDE.md.
- The development build (`Bundle.main.bundleIdentifier == nil`) uses `dev-cards.json`, and the `.app` uses `cards.json`.
- If `cards.json` can't be read, don't overwrite it. Saving empty data erases every card. Stop importing and quizzes, and show the error in the menu.
- Never run a sync and a quiz at the same time. A sync holds the cards it read at the start and saves them after each chunk, so answers given during the sync get lost.
- Advance `importedThrough` only when both the chunk's filtering and its card creation succeed. If a sync stops midway, the next one restarts from the same place.
- Sign the `.app` with an Apple Development certificate and keep the bundle id `app.recordo`. The Full Disk Access grant is tied to both, and changing either means granting it again.
- Write `README.md` and `AGENTS.md` in English.
- Code comments are in English, at most two lines, and explain only why.
- Write UI text as `tr("日本語", "English")` with both languages side by side. The user picks the language in Settings. It defaults to the system language: Japanese when macOS prefers Japanese, English otherwise. Don't translate card terms and definitions; keep them as claude wrote them. New definitions follow the language setting, which `Importer` reads for each batch and passes to `Prompts.generate`.
- When a test compares UI text, pin the language with `useLanguage(.japanese)` or similar. Other packages' tests can leave the same `appLanguage` key behind in the shared test process defaults.
- Mark something `public` only if code outside `RecordoKit` uses it.
- Before writing Swift for a screen, build an HTML prototype and get it approved. Use the `apple-design` skill for the prototype, and base it on `QuizStyle.swift` and the prototypes in `design/sessions/quiz/`.
