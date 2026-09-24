# Recordo 出題の小窓・メニュー・設定 — 方向確認モック

2026-09-23。以前作った別のアプリのクイズpopupの構造・トークン・motionを流用し、Recordo固有（メニューバー常駐・NSMenu・Settings window）を追加した「方向確認」レベルのモック。本番実装はSwiftで別途行う。

[操作モック](apple-quiz.html) · 状態一覧は下記のstate linkを参照

## トークン（手本のアプリから継承）

`QuizStyle.swift`・DESIGN.md「Quiz Popup Style」「Color」・`Theme.Quiz`をそのまま採用。

- panel幅 340px（text=200時480px）、option最小高48px・角丸10px・1列・gap 8px、A–Dキー22×22角丸6のhairline枠、4pxグリッド。
- 文字：term 22px semibold（軽い負のtracking）、option 14px、body 13px、meta 11px。
- 色（light/dark）：window #FFFFFF/#1C1C1E、inset #F5F5F7/#2C2C2E、text #1D1D1F/#F5F5F7、secondary #68686D/#B5B5BB、line #DEDEE3/#454549、action #0068D9/#0071E3、selected #E0ECFC/#223C59、success #267843/#79D794、bad #B3261E/#FF746D（`Theme.Pronunciation.bad`由来）、correct-face #EDF7F0/#173C29、wrong-face #FFF2F1/#482321（`Theme.Practice`由来）。
- panel背景は半透明のpopover material（`backdrop-filter: blur(28px) saturate(180%)` + 半透明window色）+ hairline境界 + soft shadow。モック画面には青いグラデーションのデスクトップと、ぼかしの効いた偽ウィンドウを背景に置き、透明度を見せている。

## 画面ごとの仕様

### 1. 出題panel（`quiz-panel`、aria-label「Recordo 出題」）

**question** — header leading「復習 N/3」・trailing 24×24のclose(×)。meta「トレーディング · 段 2」(11px secondary)。term「Mark price」(22px)。option A–D。下に控えめな「分からない」テキストボタン。固定action row：quiet「後で」leading（この状態ではprimaryなし）。本文（quiz-body）だけがoverflow:auto、header/action rowは固定、640pxを超えたら内側でスクロール（Swiftの`QuizPanelFrame`契約と同じ）。

**回答後の共通レイアウト（correct / wrong / idk / discarded / last）** — 実際のカード定義は長い（中央値約76文字、90パーセンタイル約104文字）。4択すべてがそれぐらいの長さだと本文（`quiz-body`）は常に最大高さに達し、optionの下にfeedbackを置くと正誤・出典・捨てるボタンが常にfold外になる。そこでoption群の下にfeedback blockは置かず、**決してスクロールしないfooter**（`quiz-footer` = `quiz-verdict` + `quiz-actions`）に判定を1行で表示する：
- correct：「✓ 正解」(success色、太字) の隣に出典「9/20 · recordo · /btw で質問」(11px相当 secondary)。収まらなければ折り返す。
- wrong：「✗ 不正解」(bad色) ＋ 出典。C行の✗・A行の✓はそのまま。
- idk：「正しい答えは A」(primary text色、中立。Aは実際の正解キー) ＋ 出典。
- action row（footer内、常時固定）：quiet「このカードを捨てる」leading、primary「次へ ␣」（3問目のみ「閉じる」）trailing。**「後で」は回答後は表示しない**（×ボタンで閉じられるため）。未回答時はleadingが「後で」のみでprimaryは非表示。
- 回答直後、正解optionが本文scroll内で見えていなければ`scrollIntoView({block:'nearest'})`で自動的にスクロールする（`motion=reduce`時は瞬時、それ以外はsmooth）。footer自体は常に画面内。

**discarded**（wrongで「このカードを捨てる」を押した後）— footerのleadingが「このカードを捨てる」から「捨てました　元に戻す」に置き換わる（verdict行はそのまま「✗ 不正解」＋出典）。primaryは引き続き「次へ」。確認ダイアログではなくUndoで許容する設計（apple-designスキルのAgency原則：破壊的確認は使いすぎない）。

**last**（3問目を正解）— header「復習 3/3」、primaryラベルが「次へ」ではなく「閉じる」（␣マークは維持）。verdict行・footerの構成は他の回答後状態と同じ。

**empty-none**（0枚で「出題」）— header close(×)のみ、本文タイトル「まだカードがありません」、本文「Claude Code で用語の意味を聞くと、次の同期でカードになります。」、action row：quiet「閉じる」leading・primary「同期」trailing。

**empty-due**（該当日時なし）— タイトル「今出せるカードはありません」、本文「次は今日 21:40 に 2 枚出ます。」、primary「閉じる」1つのみ（trailing寄せ）。

**empty-broken**（cards.json読み込み失敗）— タイトル「cards.json を読めませんでした」、本文「ファイルを直すまで、取り込みと出題を止めています。」、action row：quiet「Finder で表示」leading・primary「閉じる」trailing。

### 2. メニューバー（`menubar` + `menu-dropdown`）

メニューバーはRecordoの状態を問わず常駐。stacked-cardsのstatus icon（inline SVG）をクリックするとdropdownが開閉する。dropdownはNSMenu風：13px、行高22px相当（1.7em）、角丸selection highlight（hover時にaction色で塗る、native likeにwhiteテキストへ反転）、separator、右寄せshortcut glyph、disabled行はsecondary色。

**menu** — 「出題」／「同期」／separator／disabled「最後の同期：今日 19:04」／separator／「設定…」⌘,／「Recordo を終了」⌘Q。

**menu-syncing** — 「同期」がdisabled「同期中 3/11」＋小さいspinnerに置き換わる。最後の同期行は変わらない。

**menu-failed** — 「同期」は再度有効、その下に警告glyph付きdisabled行「同期できませんでした：claude にログインしてください」（menu幅≤300pxで2行に折り返す）。

### 3. 設定window（`settings-window`）

macOS Settings風のwindow（traffic light付きtitlebar、タイトル「Recordo 設定」、幅460px、200%時600px）。grouped formに3行：
- 「出題の間隔」— popup button「3 時間」（native NSPopUpButton風、下向きchevron）。
- 「静かな時間帯」— ON状態のswitch＋time field「22:00」〜「9:00」。
- 「claude の場所」— text field（placeholder「自動で探す」）と、その下に secondary行「見つかりました：~/.nvm/versions/node/v24/bin/claude」。

## グローバルパラメータ

`?state=<id>&theme=light|dark&text=100|200&motion=full|reduce`。ページ内のtoolbar（fixture-bar）からも同じ状態を切り替えられ、切り替えるとURLも同期する（history.replaceState）。

- **theme** — Home semantic paletteのlight/dark（CSS変数の再定義）。
- **text** — 200は全文字サイズを2倍にし、panelは340→480px・settings windowは460→600pxへ**幅を広げる**。文字を縮めたりclipしたりしない。縦方向はpanelの`max-height:min(640px, calc(100% - 56px))`を超えた分だけ本文が内部scrollする（640px上限はSwift契約のまま）。
- **motion** — full/reduceの2値。CSSの`prefers-reduced-motion`も同時に見る。

## Motion

動きは`MOTION_INTENSITY 2`の予算に従う：どの動きもユーザー操作か状態変化への応答で、500ms以内に収まり、ループや待機中の動きはない（同期中spinnerのみ例外）。既定のeasingはcritically damped spring（response ~0.25–0.35s、overshootなし）、✓/✗ glyphのpopだけdamping ~0.8相当の軽いbounceを使う。transformとopacity（＋background/border colorのcrossfade）だけを動かし、spring風カーブはCSS `cubic-bezier`（ほぼ`linear()`と同じ役割）で近似している。

| # | 操作・変化 | 対象・プロパティ | 時間・easing | motion=reduce | SwiftUI相当 |
|---|---|---|---|---|---|
| 1 | 出題が表示される（初回・replay時、未回答のoption） | `.option` の opacity・translateY(4px→0)、A→D 30ms刻みのstagger | 160ms、`--ease-spring`（`cubic-bezier(.22,1,.36,1)`）。D=90ms delay+160ms=250ms以内 | opacity crossfadeのみ、stagger省略、≤200ms | `.transition(.opacity)` + `.animation(.spring(response:.28,dampingFraction:1).delay(Double(index)*0.03))` |
| 2 | press feedback（option・button全般） | `transform: scale(.985)`（pointer-down即時）／離すとbase ruleの`.25s`で復帰、`filter: brightness(.94)`も併走 | 押下は0s（即時）、復帰0.25s `--ease-spring` | scaleなし、`filter`のみ0.15s | `.scaleEffect(pressed ? 0.985 : 1).animation(.spring(response:.25,dampingFraction:1), value: pressed)` |
| 3a | 回答：選んだ行の背景・枠 | `.option` background-color・border-color | 200ms `--ease-spring` | 同じ（color crossfadeはreduceでも許容） | `.animation(.spring(response:.2,dampingFraction:1), value: verdict)` |
| 3b | 回答：✓/✗ glyphのpop | `.option-mark`/`.quiz-verdict-mark` の opacity・scale(.6→1) | 300ms `cubic-bezier(.34,1.56,.64,1)`（damping ~0.8のbounce近似） | opacity のみ、scaleなし、180ms | `.spring(response:.3,dampingFraction:0.8)` |
| 3c | 回答：他の行が inert に | `.option.opt-inert` の opacity(.72) | 200ms ease | 同じ | `.opacity(0.72).animation(.easeOut(duration:.2))` |
| 3d | 回答：footerの正誤ラベルが現れる | `.quiz-verdict-line` の opacity・translateY(6px→0)、glyph popの60ms後に開始 | 250ms `--ease-spring`、`transition-delay:.06s` | opacity のみ、delayなし、180ms | `.transition(.move(edge:.top).combined(with:.opacity)).animation(.spring(response:.25,dampingFraction:1).delay(0.06))` |
| 4 | 次の問題へ（次へ） | `.quiz-body-inner` 全体が左へslide+fade out→内容差し替え→右からslide+fade in。`.quiz-title`（件数）はopacityでcrossfade | out 160ms ease、in 180ms `--ease-spring`、件数crossfade 120ms | `motion=reduce`時はこの経路自体を使わず、パネル全体のopacity crossfade（180ms）にfall back | `.transition(.asymmetric(insertion: .move(edge:.trailing).combined(with:.opacity), removal: .move(edge:.leading).combined(with:.opacity)))` |
| 5 | 閉じる（✕・後で・閉じる）→再入場 | `.quiz-panel`/`.quiz-panel`(notice) の opacity・translate(10px,14px)・scale(.98) | 入場300ms／退場220ms、いずれも`--ease-spring`。入退場は同じ経路（spatial consistency） | opacityのみのfade、入場220ms／退場200ms | `.transition(.move(edge:.trailing).combined(with:.opacity))` + `.spring(response:.3,dampingFraction:1)` |
| 6 | このカードを捨てる ⇄ 捨てました・元に戻す | footerのleading領域をopacityでcrossfade | 150ms（75ms×2、fillの差し替えを挟む） | 同じ（既にopacityのみ） | `.transition(.opacity).animation(.easeInOut(duration:.15))` |
| 7 | メニューの開閉 | `.menu-dropdown` の opacity・scale(.97→1)、`transform-origin`はstatus iconの角 | 開160ms `--ease-spring`／閉120ms ease | opacityのみ、≤200ms | `.transition(.scale(scale:0.97, anchor:.topTrailing).combined(with:.opacity))` |
| 8a | 静かな時間帯トグル | `.switch::after` のtransform(translateX)、track背景色 | knob 250ms `--ease-spring`、背景色200ms ease | 同じ（transform一つだけの小さな動きなので維持、colorはreduceでも許容） | `.spring(response:.25,dampingFraction:1)` |
| 8b | トグルOFF時の時刻欄 | `.time-field:disabled` の opacity(.5) | 150ms ease | 同じ | `.opacity(0.5).animation(.easeOut(duration:.15))` |
| 8c | 出題の間隔ポップアップ押下 | 項目2と同じ press feedback | 同上 | 同上 | 同上 |
| 9 | 空状態パネルの表示 | パネル本体は#5と同じenter、`.notice-title`/`.notice-body`はopacityで少し遅れて追いかける | 本文フェード200ms ease、.08s delay | delayなし、180ms | `.opacity(0).animation(.easeOut(duration:.18).delay(0.08))` |

`motion=reduce`のときはOS設定ではなくtoolbarが最終決定権を持つ：初回だけ`prefers-reduced-motion`をtoolbarの既定値として読み、以後は`data-motion`属性だけを見る（`@media`によるCSS側の常時上書きは廃止した）。toolbarの「もう一度再生」で現在の状態のenter＋revealを再生できる。

## アクセシビリティ

- 実操作はすべて`<button>`。disabled行（メニューの情報行・状態行）は`disabled`＋`aria-disabled`。
- panelに`aria-label="Recordo 出題"`。
- 正誤は色だけで伝えない：✓/✗はaria-hiddenの装飾で、option自体の`aria-label`に「A. 本文、正解」「C. 本文、選択した回答・不正解」のように文字で正誤を含める。
- フォーカスリングは`:focus-visible`で常時可視。
- キーボード：未回答時はA–D／1–4で選択、Spaceでprimary（フォーカスがbutton上にあるときはbutton自身の既定動作に任せ、二重発火しない）。修飾キー・repeatは無視。

## 手本の出題panelと異なる決定（理由つき）

- **カード1枚を3問まで**というRecordo固有の「復習 N/3」ヘッダーに置き換え、手本にあった単語学習向けの要素は全て削除。Recordoは用語カードのクイズのみで、正誤の説明＋出典行で完結するため。
- **「このカードを捨てる」→Undo**という単独機能を追加。手本のクイズにはカード破棄という概念がないため新設。確認ダイアログではなくinline Undoにしたのは、apple-designスキルのAgency原則（破壊的確認は使いすぎない、取り消しやすさで許容する）に沿わせるため。
- **メニューバー常駐UIとNSMenu風dropdown、Settings windowを新規追加**。手本のモックは通常のウィンドウを持つアプリで、メニューバー常駐という概念がない。Recordoはメニューバーのみのアプリなので、このモックで新規に設計した。
- **出典行「9/20 · recordo · /btw で質問」**をfeedbackに追加。Recordoのカードは会話由来（`/btw`コマンド）なので、例文の代わりに出典を明示する行にした。
- **空状態3種（カードなし／該当なし／読み込み失敗）**を新設。「出すものがない」状態をRecordoの同期・cards.jsonという実装に合わせて具体化した。
- **正誤・出典をoption群の下からfooterへ移設**。手本の選択肢は短めだが、Recordoの実カードは中央値76文字・p90 104文字の説明文が4択に並ぶため、feedbackを本文内に置くと常にfold外になる。footerは`quiz-body`と独立してスクロールしないため、正誤・出典・次への動線を毎回スクロールなしで保証できる。正解の説明文はA行の✓表示と重複するため、feedback本文としての再掲はやめた。

## モックと本番の差

架空のカード1枚（Mark price）を使い回し、2問目・3問目も同じ内容を表示する。同期・claude検出・cards.jsonの読み書き・NSStatusItem・非activating panelの実際の挙動はnative側の実装。メニューの「出題」「同期」「設定…」クリックは、このモック内の画面切り替えのみを行う簡易的な配線で、実コマンドには繋がっていない。
