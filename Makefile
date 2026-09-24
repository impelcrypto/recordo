.PHONY: test dev sync app install install-skill clean

test:
	swift test

# swift run builds have no bundle id, so dev runs read and write dev-cards.json.
dev:
	swift build
	"$$(swift build --show-bin-path)/Recordo"

# Only a dev build shares dev-cards.json; its in-memory cards would overwrite what this sync saves.
sync:
	@! pgrep -f "^$(CURDIR)/.build/.*/Recordo" >/dev/null || { echo "A dev build of Recordo is running; quit it before make sync" >&2; exit 1; }
	swift run Recordo --sync-once

app:
	./scripts/bundle.sh

install: app
	@killall Recordo 2>/dev/null || true
	rm -rf /Applications/Recordo.app
	cp -R build.noindex/Recordo.app /Applications/
	open /Applications/Recordo.app

install-skill:
	mkdir -p "$(HOME)/.claude/skills"
	ln -sfn "$(CURDIR)/skills/term" "$(HOME)/.claude/skills/term"

clean:
	rm -rf .build build.noindex
