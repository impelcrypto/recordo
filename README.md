# Recordo

A macOS menu bar app that turns the terms you ask about in Claude Code into four-choice quizzes and asks them every few hours. You keep using Claude Code as usual. Once a day Recordo picks up questions like "what is LCP?", turns them into cards, and asks you again in the bottom-right corner of the screen just as you start to forget.

## How it works

1. Once a day, Recordo reads the prompts in `~/.claude/history.jsonl` added since the last sync.
2. `claude -p` (Sonnet) picks the lines that ask what a word or abbreviation means. It drops questions about causes or how to do something, and names that only make sense inside one project.
3. Recordo cuts the answer you actually read out of that question's session log (`~/.claude/projects/`).
4. `claude -p` writes the term, a definition of up to 60 characters, tags, and three plausible wrong answers. Recordo saves them to `cards.json`.
5. Every 60 seconds Recordo checks whether it may ask, and shows up to three due cards in a small panel in the bottom-right corner.
6. A correct answer pushes the card's next review further out. A wrong answer sends it back to the start (the Leitner system).

## Requirements

- macOS 14 or later
- A Swift 6 toolchain (Xcode or the Command Line Tools)
- `claude` (the Claude Code CLI), logged in
- An Apple Development signing certificate (optional)

Without the certificate the build falls back to ad-hoc signing, and you have to grant Full Disk Access again after every rebuild.

## Install

```sh
make install        # build the .app, copy it to /Applications, and launch it
make install-skill  # link the /term skill to ~/.claude/skills/term
```

An icon appears in the menu bar. Recordo has no Dock icon. The first launch syncs the last 30 days in the background, which takes about 30 minutes. The menu shows progress like "Syncing 3/15".

### Pausing during Focus

Give Recordo Full Disk Access. macOS writes the Focus state to `~/Library/DoNotDisturb/DB/Assertions.json`, and Recordo can't read that file without the permission. The Quizzes page in Settings has a button that opens the right pane in System Settings.

The permission also covers the `claude -p` child process that Recordo runs. Recordo calls `claude -p` with its tools removed (`--tools ""`).

A Focus that turns on from a schedule doesn't show up in this file. Cover those hours with Quiet Hours in Settings.

## Usage

### Asking about terms

Ask in Claude Code as you always do. Recordo picks up both normal prompts and `/btw` questions.

If you don't want the filter to miss a term, ask with `/term <term>`. That skips the filter and goes straight to card creation. You can still end up without a card if the conversation doesn't pin down a single meaning. Run `make install-skill` to set it up, and see [the /term skill](docs/guides/term-skill.md) for details.

Recordo ignores questions older than 30 days. Claude Code deletes session logs after 30 days by default, so the conversation the definition would come from is gone.

### Quizzes

The panel appears in the bottom-right corner when all of these hold:

- The quiz interval you set (3 hours by default) has passed since the last quiz
- At least one card is due
- Neither Focus nor Quiet Hours is on
- The frontmost app isn't in full screen

The four choices A–D are definitions. When the panel appears it doesn't take keyboard focus from the app you're working in, so click the panel first if you want to answer with keys.

| Key | Action |
|---|---|
| A–D | Pick that choice |
| Space | Next. Closes the panel on the last question |
| Esc | Close |

"I don't know" counts as wrong. A lucky guess would otherwise stretch the interval of a card you haven't learned. "Later" only closes the panel, and the cards come back next time. If claude wrote a wrong definition, click "Discard This Card" after you answer.

Each correct answer moves the next review to 4 hours, then 1 day, 3 days, 7 days, 14 days, and 30 days. A wrong answer, or asking about the same term again in Claude Code, sends the card back to the start, and it comes up in the next quiz.

### Menu

- Quiz: ask now, ignoring the interval and the pause conditions. If no card is due, the menu says why
- Sync: sync now instead of waiting for the daily run. It also skips the one-hour wait after a failure
- Cards…: browse your cards and discard the ones you don't want. You can search terms and definitions, and the list splits into pages of 100. Discarding asks for confirmation and can't be undone. You can't discard while a sync is running. ⌃⌥⌘C opens it from any app; change or clear that shortcut in Settings
- Settings… (⌘,)
- Quit Recordo (⌘Q)

You can't press Quiz during a sync, and Recordo doesn't start a sync while the panel is open.

### Settings

| Page | Items |
|---|---|
| General | Language (Japanese by default), Appearance, Open Cards shortcut (⌃⌥⌘C by default) |
| Quizzes | Quiz Interval, Quiet Hours, Focus |
| Sync | claude Location (leave empty to find it automatically), Last Sync |
| About | Version, Open Data Folder (opens `~/Library/Application Support/Recordo/` in Finder) |

Changing the language doesn't translate cards. Terms and definitions stay as claude wrote them.

## Data

All cards live in one file, `~/Library/Application Support/Recordo/cards.json`. Recordo writes to a temporary file and then swaps it in, so a crash mid-write never leaves a broken file.

If loading fails, Recordo doesn't overwrite the file, because saving empty data would erase every card. The menu shows "Couldn't read cards.json" and importing and quizzes stop. Fix the file, then press Quiz to reload it.

The development build (`make dev`) uses `dev-cards.json` in the same folder and doesn't touch your everyday cards.

## Troubleshooting

When a sync fails, the menu shows "⚠︎ Sync failed: (reason)". Recordo retries after an hour, or you can retry right away with Sync in the menu. Relaunching Recordo also clears the one-hour wait. The next sync resumes where the last one stopped, so it neither misses nor duplicates anything.

| Reason | What to do |
|---|---|
| claude not found | Enter the path to `claude` on the Sync page in Settings. At launch Recordo looks for `claude` through a login shell (`/bin/zsh -lic`), and that lookup failed |
| Log in to claude | Run `claude` in a terminal and log in |
| Couldn't read the response from claude | Retry with Sync in the menu |

If the menu shows "⚠︎ Couldn't read cards.json", see Data above.

## Development

Commands and conventions are in [AGENTS.md](AGENTS.md). These three come up most:

```sh
make test   # swift test
make dev    # launch the development build (uses dev-cards.json)
make sync   # run one import with the real claude -p and write to dev-cards.json
```

## Docs

- [The /term skill](docs/guides/term-skill.md): installing and using `/term`, and how a question becomes a card
- [Design spec](docs/superpowers/specs/2026-09-23-recordo-design.md): rules for importing and quizzing, the data format, and failure behavior
- [Screen prototypes](design/README.md)

## License

MIT. See [LICENSE](LICENSE).
