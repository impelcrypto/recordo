import Foundation

enum Prompts {
    struct Question {
        let id: Int
        let question: String
        let context: String?
        let term: String
    }

    static let classifySchema = #"{"type":"object","properties":{"items":{"type":"array","items":{"type":"object","properties":{"id":{"type":"integer"},"term":{"type":"string"}},"required":["id","term"]}}},"required":["items"]}"#

    static let generateSchema = #"{"type":"object","properties":{"cards":{"type":"array","items":{"type":"object","properties":{"id":{"type":"integer"},"skip":{"type":"boolean"},"term":{"type":"string"},"definition":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}},"distractors":{"type":"array","minItems":3,"items":{"type":"string"}}},"required":["id","skip"]}}},"required":["cards"]}"#

    static func classify(_ questions: [(id: Int, text: String)]) -> String {
        let list = questions.map { "\($0.id): \($0.text)" }.joined(separator: "\n")
        return """
        ソフトウェアエンジニアが Claude Code に送った質問の一覧です。言葉、略語、概念の意味を聞いている質問だけを選んでください。

        選ぶ例：「immutable とは？」「what is PAR?」「LCP?」「TF change とは？」
        選ばない例：意味は分かったうえで原因ややり方を聞く質問（「LCP が悪いのはなぜ？」）、作業の依頼、翻訳の依頼、雑談
        そのプロジェクトの中でしか通じない呼び名も選ばない：人の略称やあだ名、マイルストーンや段階の番号、特定のファイル・文書・関数・変数・画面部品の名前

        選んだ質問ごとに、聞かれている用語を質問に書かれた表記のまま term に入れてください。1つの質問で複数の用語を聞いていれば、用語ごとに1件にします。該当がなければ items は空にします。

        質問一覧（id: 本文）:
        \(list)
        """
    }

    static func generate(_ questions: [Question], tags: [String], japanese: Bool) -> String {
        let known = tags.isEmpty ? "（なし）" : tags.joined(separator: "、")
        let items = questions.map { question in
            "### id \(question.id)\n質問: \(question.question)\n聞かれている用語: \(question.term)\n会話:\n\(question.context ?? "（会話の記録なし）")"
        }.joined(separator: "\n\n")
        // English letters are about half as wide, so doubling the counts keeps the options the same size in the panel.
        let definition = japanese
            ? "その会話の文脈での意味を日本語で60字以内。用語そのものは定義に書かない。「〜ではない」のような否定から始めない。いくつか並べるときは「・」でなく「と」や「や」でつなぐ"
            : "その会話の文脈での意味を英語で120字以内。用語そのものは定義に書かない。「Not ...」のような否定から始めない"
        let language = japanese ? "" : "英語で"
        let gap = japanese ? 10 : 20
        let stop = japanese ? "句点" : "ピリオド"
        return """
        Claude Code で作業中に聞かれた用語の復習カードを作ります。各項目の質問と、その質問をしたときの会話を読み、次を返してください。

        - term: 用語。会話で使われていた表記にそろえる（略語は略語のまま）
        - definition: \(definition)
        - tags: 分野のタグを\(language)1〜2個。既存のタグに合うものがあればそれを使う
        - distractors: 同じ分野で紛らわしいが誤っている定義を\(language)3つ。その用語の一般的な意味や、別の場面なら正しい意味は入れない（正解が2つになるため）。長さは definition との差を\(gap)字以内にし、少なくとも1つは definition より長くする。書き方もそろえ、\(stop)の有無と文末の言い方を definition と同じにする（長さや書き方で正解が分からないようにするため）
        - skip: 会話の記録がなく、質問文だけでは意味が1つに決まらないときは true。そのときは他の項目を省いてよい

        既存のタグ: \(known)

        \(items)
        """
    }

    struct ClassifyResponse: Decodable {
        struct Item: Decodable {
            let id: Int
            let term: String
        }
        let items: [Item]
    }

    struct GenerateResponse: Decodable {
        struct Card: Decodable {
            let id: Int
            let skip: Bool
            let term: String?
            let definition: String?
            let tags: [String]?
            let distractors: [String]?
        }
        let cards: [Card]
    }
}
