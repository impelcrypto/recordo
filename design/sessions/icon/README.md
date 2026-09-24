# Recordo アイコン案

- A：真鍮の想起ループと扇状に重ねたアイボリーの単語カード。深いインクティールのタイル。`recordo-appicon-a.svg`、`recordo-menubar-a.svg`
- B：真鍮の復習箱からチェック済みのカードが現れる構図。深いミッドナイトインディゴのタイル。`recordo-appicon-b.svg`、`recordo-menubar-b.svg`

## 採用：B案（2026-09-24）

- アプリのアイコンは `assets/AppIcon.svg`、メニューバーのアイコンは `assets/MenuBarIcon.svg` にコピーした。
- A案を採らなかった理由：32px ではカードの束がフォルダーに見え、似た形の別のアプリと色でしか区別できなくなる。メニューバー用は 16px で南京錠に見えた。
- アプリのアイコンは `assets/AppIcon.icns` にして、`scripts/bundle.sh` が `.app` に入れる（2026-09-24）。この Mac の `sips` は SVG を読めず、`qlmanage` は背景を白で塗り、`magick` はグラデーションを描けなかった。そこで NSImage で 1024px の透過 PNG に描き、`sips -z` で各サイズにしてから `iconutil` で作った。SVG を変えたら作り直す。
- メニューバー用はまだ組み込んでいない。黒一色のテンプレート画像として読み込む予定。
