# Recordo カード一覧：方向確認モック

2026-09-24。持っているカードを見て、要らないものを捨てるためのウィンドウ。出題の小窓モック（`../quiz/apple-quiz.*`）のトークンと fixture toolbar をそのまま使い、並べ方は別のアプリの単語一覧のモックに合わせた。Swift はこのモックの承認後に書く。

[操作モック](apple-cards.html)

## トークン
色、`--scale`、press feedback、デスクトップ背景は `apple-quiz.css` と同じ値を使う（`Theme.swift` とも一致）。ウィンドウ本文は不透明な `--window`。カードの内容はすべて架空で、時計は 2026-09-24 19:42 に固定している。今日、明日、出題待ちの表示がモックを開いた日で変わらないようにするため。

## 画面

### ウィンドウ

640×720、最小幅 480。右下のつまみで大きさを変えられる（CSS の `resize`）。タイトルバーは信号機だけで、タイトル文字は出さない。本文は最大幅 600 の1列で、左右の余白は 32。text=200 のときはウィンドウ幅 900 で、本文の最大幅を外す。

### ヘッダー（スクロールしても上に残る）

- 「カード」26px bold、tracking -0.02em。右に「12 枚」13px secondary。
- 検索欄：虫眼鏡、入力欄、文字があるときだけ出る × ボタン。placeholder は「用語や定義で探す」。
- 同期中だけ、検索欄の下に小さいスピナーと「同期中はカードを捨てられません」を出す。
- 境目に線は引かない。本文がヘッダーの下に潜ったときだけ、18px のぼかしとフェードを出す。ヘッダー自体は 90% の半透明に blur(20px)。

### セクション

「覚えている途中」は段 0〜5、「覚えた」は段 6。覚えたの見出しの下に「30日ごとに出題します」を添える。どちらも最後に聞いた日時（`asked.last.at`）の新しい順に並べる。見出しの横の数は、検索中だけ「3 / 12」のように一致数と全体数を並べる。カードが1枚もないセクションは見出しごと出さない。

### 行

1. 用語 16px semibold、折り返す。
2. 定義 13px、本文色、全文を折り返して出す。
3. `Web性能 · 段 2 · 次の出題 明日 9:00`（12px secondary）。期日を過ぎたカードは日時の代わりに太字の「出題待ち」。日時の書き方は `AppModel.when()` と同じ（今日 H:mm、明日 H:mm、M/d H:mm）。
4. `9/21 · sample-app · /term で質問`（12px secondary）。`QuizSession.source()` と同じ形。
5. 右端にゴミ箱ボタン（32×32、常に表示）。名前は「LCP を捨てる」のように用語を含める。

行の最小高は 48、下に hairline。行にマウスを乗せるか、行の中のボタンにキーボードのフォーカスがあるとき、用語だけが 120ms で `--action` 色に変わる。

### 捨てる確認

ゴミ箱を押すと、ウィンドウの上端寄りに macOS のアラートシートが出る。アプリアイコン、「“LCP” を捨てますか？」、「段と回答の記録も消えます。元に戻せません。」、ボタンは左から「捨てる」（`--bad` 色の文字、塗りなし）と「キャンセル」（既定、`--action` の塗り）。

- 開いた時点のフォーカスはキャンセル。Tab は2つのボタンの間だけを行き来する。後ろの一覧は操作できない。
- Escape とキャンセルは閉じて、押したゴミ箱ボタンにフォーカスを戻す。
- 捨てると行が消え、下の行が詰まり、数が変わる。フォーカスは次の行のゴミ箱へ、最後の行なら前の行へ移る。アニメーションの終わりは待たない。
- モックの Return はフォーカスのあるボタンを押す。本物の macOS では、フォーカスがどこにあっても既定のキャンセルが押される。

### 検索

入力のたびに絞り込む（待ち時間なし）。用語か定義のどちらかに、大文字小文字を区別せずに含まれていれば一致。Escape か × で消える。1件も合わないときは「“xyz” に合うカードはありません」と「検索を消す」ボタンを出す。

### ページ送り

覚えている途中から覚えたへと続く1本の並び（検索中は一致したものだけ）を、先頭から100枚ずつ区切る。
- 行があるセクションの見出しを、そのページにも出す。セクションが2ページにまたがれば、見出しは両方に出る。数はページ内ではなく全体の数。
- 検索で0件になったセクションの「0 / N」見出しは、覚えている途中なら1ページ目、覚えたなら最後のページにだけ出す。
- 一覧の下の中央に「‹ 前へ」「2 / 3」「次へ ›」（数字は tabular-nums）。端のボタンは `aria-disabled` にして、フォーカスは受けられるようにしておく。1ページしかなければ出さない。
- ページを変えたら一覧の先頭へスクロールし（reduce motion は瞬時）、フォーカスは押したボタンに残す。
- 検索の文字が変わると1ページ目に戻る。捨てた後は同じページに留まり、そのページが空になったら最後のページへ寄せ、そのページの最後の行にフォーカスを置く。

## 状態

| state | 中身 | 例 |
|---|---|---|
| normal | 途中 9 枚、覚えた 3 枚。出題待ち、今日、明日、先の日付、/btw と /term と会話が混ざる | [link](apple-cards.html?state=normal&theme=light&text=100) |
| search | 「late」で3件（用語で2件、定義で1件） | [link](apple-cards.html?state=search&theme=light&text=100) |
| no-match | 「xyz」で0件 | [link](apple-cards.html?state=no-match&theme=light&text=100) |
| empty | カードなし。`noticeCopy(.noCards)` の文言。検索欄と枚数は隠す | [link](apple-cards.html?state=empty&theme=light&text=100) |
| syncing | 一覧は見える。ゴミ箱はすべて `aria-disabled` で薄くなり、押しても何も起きない | [link](apple-cards.html?state=syncing&theme=light&text=100) |
| unreadable | 「cards.json を読めませんでした」と直し方。一覧と検索は出さない | [link](apple-cards.html?state=unreadable&theme=light&text=100) |
| confirm | normal に LCP の確認シートを開いた状態 | [link](apple-cards.html?state=confirm&theme=light&text=100) |
| many | 240 枚で3ページ（100 / 100 / 40）。覚えた60枚が2〜3ページ目にまたがる。用語は12語に番号を付けて使い回す | [link](apple-cards.html?state=many&page=2&theme=light&text=100) |

URL は `?state=&page=1..&theme=light|dark&text=100|200&motion=full|reduce&lang=ja|en`。toolbar で切り替えると URL も変わる。Reset は捨てたカードを元に戻す。lang=en は画面の文言だけを英語にし、カードの用語、定義、タグは書かれたまま残す。

## Motion

| 操作 | 動き | 時間 | motion=reduce | SwiftUI |
|---|---|---|---|---|
| 押す | scale(.985) と brightness(.94) を押した瞬間に | 戻り 250ms | scale なし | 出題の小窓と同じ |
| 行の hover / focus | 用語の色だけ | 120ms ease-out | 同じ | `.animation(.easeOut(duration:0.12), value: hovering)` |
| シートが出る | opacity と translateY(-8px) scale(.97) から | ばね 360ms（見た目は約250msで止まる） | opacity のみ 150ms | `.confirmationDialog` の標準 |
| シートが閉じる | 来た道を戻る | 150ms ease-in | opacity のみ | 標準 |
| ページを変える | 一覧の先頭へ smooth scroll（240枚の many で約1秒） | ブラウザ標準 | 瞬時 | `ScrollViewReader` の `scrollTo(_:anchor: .top)` を `withAnimation` で |
| 行が消える | 消える行は 150ms で透明に。下の行は元の位置から詰まる | ばね 360ms、overshoot なし | 行は動かさず、消える行の透明化だけ | `withAnimation(.spring(response:0.25, dampingFraction:1)) { deck.remove }` |

ばねは臨界減衰 `1-(1+ωt)e^(-ωt)`、`ω=2π/0.25` を WAAPI の `linear()` で近似している。詰まっている途中でもう1枚捨てた場合は、画面に描かれている位置から次の動きを始めるので、行が跳ばない。

## アクセシビリティ

- 操作はすべて `<button>`。ゴミ箱の名前とツールチップは「LCP を捨てる」「Discard LCP」。同期中は `aria-describedby` で同期中の一文を読ませる。
- シートは `role="alertdialog"`、タイトルと本文を名前と説明に使う。

## SwiftUI での作り

- `RecordoApp` の `MenuBarExtra` と `Settings` の隣に `Window("カード", id: "cards")` を足し、`.windowToolbarStyle(.unified(showsTitle: false))` と `.frame(minWidth: 480)` を付ける。`.accessory` のアプリなので、メニューから `openWindow(id:)` のあとに `NSApp.activate` で前に出す。
- 一覧は `ScrollView { LazyVStack(alignment: .leading, spacing: 0) }`。セクションは `Section` ではなく自前の見出し View にする（線を見出しに付けて、詰まるときに一緒に動かすため）。
- ヘッダーは `.safeAreaInset(edge: .top)` に置き、背景は `.bar` の material とグラデーションの重ね。Package.swift が macOS 14 なので `scrollEdgeEffectStyle` は使えない。macOS 26 だけ `if #available` で足してもよい。
- 確認は `.confirmationDialog(_:isPresented:presenting:)` に `Button(role: .destructive)` と `Button(role: .cancel)`。
- ゴミ箱は `.disabled(model.isSyncing)` と `.help(...)`、`.accessibilityLabel(tr("\(term) を捨てる", "Discard \(term)"))`。
- 検索は `@State var query` と `localizedCaseInsensitiveContains` で絞る。`.searchable` はツールバーに出てしまうので使わない。
- ページは `CardList.page(...)` で切り出し、ページ番号は `@State`。

## 元にしたモックとの違い

- 行の hover で色が変わるのは用語だけ。手本のモックはゴミ箱も hover で赤くなるが、今回は変えない。ボタン自身の hover で薄い背景が付くだけにした。
- 復習を始めるボタンや検索以外の操作は置かない。この画面は見ることと捨てることだけ。
- 出題の小窓の「このカードを捨てる」は Undo で済ませているが、こちらは確認シートを出す。一覧からは連続で捨てられ、捨てた後に戻す場所がないため。

## レビューで決めたこと（2026-09-24）

1. unreadable の本文は、出題の小窓と同じ `noticeCopy(.unreadable)` を使う。同じ状態に2つの文を置かない。
2. 検索中に片方のセクションが0件になっても、見出しと「0 / 3」は残す。どちらの区分けに何枚あるかが検索中も分かるため。
3. シートのボタンの並びは、Swift で実際の `.confirmationDialog` を出してから合わせる。
