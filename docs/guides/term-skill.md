# The /term skill

`/term` is a Claude Code skill that ships with Recordo. Type `/term <term>` in Claude Code, and Claude explains what the term means in the conversation you're having. At the next sync, Recordo turns that question into a quiz card.

## Why use it

Recordo already picks up plain questions like "what is LCP?". To find them, `claude -p` reads each prompt and guesses whether it asks what something means, and that guess can miss. A `/term` question skips the guess: Recordo takes the argument as the term and goes straight to card creation.

## Install

```sh
make install-skill
```

This links `~/.claude/skills/term` to `skills/term` in this repository. After you edit `skills/term/SKILL.md`, you don't need to run the command again.

To remove the skill, delete the link with `rm ~/.claude/skills/term`.

## Usage

```
/term idempotent
```

Claude answers in a few sentences. The first one or two give the definition, and the next one or two say how the conversation used the term. For an abbreviation, Claude also spells out the full name. The skill doesn't read or write files and doesn't touch your code.

## From question to card

1. Claude Code records `/term idempotent` in `~/.claude/history.jsonl`, the same as any prompt.
2. At the next daily sync, or when you press Sync in the menu, Recordo finds the line and uses `idempotent` as the term.
3. Recordo cuts Claude's answer out of the session log (up to 6,000 characters), and `claude -p` writes the card from it.

You can still end up without a card: `claude -p` skips the term when the conversation doesn't pin down a single meaning. Recordo also ignores questions older than 30 days.

If you already have a card for the term, asking again sends that card back to the start of the review schedule, and it comes up in the next quiz.
