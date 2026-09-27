# Recordo デザインモック

## 出題の小窓・メニュー・設定：承認済み（2026-09-23）

以前作った別のアプリのクイズpopupのトークン・構造・motionを流用したRecordoの静的HTMLモック。Swift の実装は計画2（`docs/superpowers/plans/2026-09-23-recordo-ui.md`）で作った。英語の文言と、設定の「言語」と「外観」の行はモックにない。設定ウィンドウは、モックの1枚のフォームから、左にサイドバーがある形に変えた（2026-09-23）。サイドバーの一番下の「情報（About）」は、ユーザーの指示でモックを作らなかった（2026-09-24）。同じ日に、最後の問題に答えたときの花吹雪と、設定の「1回の問題数」（1〜10問、既定3問）をモックに足して承認を得た。花吹雪の値は以前作った別のアプリの完了時の花吹雪に合わせた。同じ日に、サイドバーを全幅のタイトルバーの下に置き、見出し付きのセクションに分けた。

- [操作モック（apple-quiz.html）](sessions/quiz/apple-quiz.html)
- [仕様書（apple-quiz-spec.md）](sessions/quiz/apple-quiz-spec.md)

### 状態リンク（light / text=100）

出題panel:
- [question](sessions/quiz/apple-quiz.html?state=question&theme=light&text=100) — 復習1/3、未回答
- [correct](sessions/quiz/apple-quiz.html?state=correct&theme=light&text=100) — Aを選んで正解
- [wrong](sessions/quiz/apple-quiz.html?state=wrong&theme=light&text=100) — Cを選んで不正解
- [idk](sessions/quiz/apple-quiz.html?state=idk&theme=light&text=100) — 「分からない」
- [discarded](sessions/quiz/apple-quiz.html?state=discarded&theme=light&text=100) — 不正解後にカードを捨てた
- [last](sessions/quiz/apple-quiz.html?state=last&theme=light&text=100) — 3問目を正解（primaryが「閉じる」）。答えた瞬間に花吹雪が一度降る（「もう一度再生」で再生し直せる）
- [empty-none](sessions/quiz/apple-quiz.html?state=empty-none&theme=light&text=100) — カードが1枚もない
- [empty-due](sessions/quiz/apple-quiz.html?state=empty-due&theme=light&text=100) — 該当日時のカードがない
- [empty-broken](sessions/quiz/apple-quiz.html?state=empty-broken&theme=light&text=100) — cards.jsonが読めない

メニューバー:
- [menu](sessions/quiz/apple-quiz.html?state=menu&theme=light&text=100) — 通常のdropdown
- [menu-syncing](sessions/quiz/apple-quiz.html?state=menu-syncing&theme=light&text=100) — 同期中
- [menu-failed](sessions/quiz/apple-quiz.html?state=menu-failed&theme=light&text=100) — 同期失敗

設定:
- [settings](sessions/quiz/apple-quiz.html?state=settings&theme=light&text=100) — Recordo設定window

### 確認用パラメータ

`?state=<上記id>&theme=light|dark&text=100|200&motion=full|reduce` を組み合わせて確認できる。HTML内のtoolbar（画面外のstate switcher）からも同じ状態に切り替え可能。「もう一度再生」ボタンで、その状態のenter/revealモーションを再生し直せる。

## カード一覧：承認済み（2026-09-24）

持っているカードを見て、要らないものを捨てるウィンドウ。出題の小窓モックのトークンを使い、並べ方は別のアプリの単語一覧のモックに合わせた。承認のときにページ送り（1ページ100枚）を足した。Swift の実装は計画3（`docs/superpowers/plans/2026-09-24-recordo-cards.md`）で作った。確認ダイアログは macOS 標準のものなので、ボタンの並びと色は OS に任せている。

- [操作モック（apple-cards.html）](sessions/cards/apple-cards.html)
- [仕様書（apple-cards-spec.md）](sessions/cards/apple-cards-spec.md)

状態は `?state=normal|search|no-match|empty|syncing|unreadable|confirm|many` で開ける。many は240枚で3ページになり、`page=2` のように直接開ける。

## 同期中のメニューバー：案Aを採用（2026-09-24）

初回の同期は30分ほどかかるのに、進み具合はメニューを開かないと見えなかった。そこで同期のあいだ、メニューバーのアイコンの横に終わった塊の割合を「40%」のように出す。案A（アイコンはそのまま横に％）と案B（同期の矢印に替えて横に％）から、いつものアイコンが消えない案Aを選んだ。メニューの「同期中 3/15」も「同期中 40%」に替えた。

- [2案の比較（sync-progress.html）](sessions/menubar/sync-progress.html)

## アイコン：B案を採用（2026-09-24）

Codex が作った2案から B案（チェックの付いたカードが箱から出てくる形、紺のタイル）を採用した。

- [案の説明と採用理由](sessions/icon/README.md)
- 採用したファイル：`assets/AppIcon.svg`、`assets/MenuBarIcon.svg`
- アプリのアイコンは `assets/AppIcon.icns` にして `.app` に入れた（2026-09-24）
