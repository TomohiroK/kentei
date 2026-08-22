import Foundation

/// プロトタイプ用の教材パック。
///
/// 各問の `choices` は先頭を正解として書く。表示順はセッションごとに入れ替わるため、
/// ここでの並びが学習者に見える順序になることはない。
/// 誤答は無作為に作らず、音の類似・意味の近さ・場面違いのいずれかの理由を持たせる。
enum DemoLearningContent {
    /// 教材を差し替えたら版を上げる。版が変わると保存済みセッションは復帰せず破棄される。
    static let version = "demo-2026-08-v3"

    static var pack: LearningContentPack {
        LearningContentPack(version: version, questions: questions)
    }

    private struct Template: Sendable {
        let lines: [(speaker: Int, text: String)]
        let choices: [String]
        let explanation: String
        let scenario: String
    }

    private static func single(
        _ text: String,
        _ choices: [String],
        _ explanation: String,
        _ scenario: String
    ) -> Template {
        Template(lines: [(0, text)], choices: choices, explanation: explanation, scenario: scenario)
    }

    private static func dialogue(
        _ first: String,
        _ second: String,
        _ choices: [String],
        _ explanation: String,
        _ scenario: String
    ) -> Template {
        Template(lines: [(0, first), (1, second)], choices: choices, explanation: explanation, scenario: scenario)
    }

    private static let templates: [Template] = [
        single("Selamat pagi.",
               ["おはようございます", "こんばんは", "おやすみなさい", "さようなら"],
               "selamat はあいさつの頭に付き、pagi は朝を指します。", "あいさつ"),
        single("Terima kasih banyak.",
               ["本当にありがとうございます", "どういたしまして", "すみません", "お願いします"],
               "terima kasih が「ありがとう」、banyak が「たくさん」で感謝を強めます。", "あいさつ"),
        single("Berapa harganya?",
               ["いくらですか", "どこですか", "何時ですか", "いくつありますか"],
               "berapa は数量や値段を尋ね、harganya は「その値段」です。", "買い物"),
        single("Di mana toilet?",
               ["トイレはどこですか", "トイレは使えますか", "トイレは何時までですか", "トイレは新しいですか"],
               "di mana は場所を尋ねる表現です。", "コンビニ"),
        single("Saya mau pesan nasi goreng.",
               ["ナシゴレンを注文したいです", "ナシゴレンを作りました", "ナシゴレンは辛いですか", "ナシゴレンが好きです"],
               "mau は「〜したい」、pesan は「注文する」です。", "ワルン"),
        single("Tolong antar saya ke bandara.",
               ["空港まで送ってください", "空港で待っていてください", "空港はどこですか", "空港まで歩きます"],
               "tolong は依頼、antar は「送る」、ke bandara は「空港へ」です。", "Grab"),
        single("Saya tidak mengerti.",
               ["わかりません", "知っています", "聞こえています", "話せます"],
               "tidak は否定、mengerti は「理解する」です。", "あいさつ"),
        single("Bisa bicara pelan-pelan?",
               ["ゆっくり話してもらえますか", "大きい声で話してください", "もう一度書いてください", "英語で話せますか"],
               "pelan-pelan は「ゆっくり」。bisa は可能を尋ねます。", "あいさつ"),
        single("Ini terlalu mahal.",
               ["これは高すぎます", "これは安いです", "これは新しいです", "これは重いです"],
               "terlalu は「〜すぎる」、mahal は「高い」です。", "買い物"),
        single("Boleh saya lihat?",
               ["見てもいいですか", "買ってもいいですか", "持って帰ってもいいですか", "使ってもいいですか"],
               "boleh は許可を尋ね、lihat は「見る」です。", "買い物"),
        single("Tolong bungkus untuk dibawa pulang.",
               ["持ち帰り用に包んでください", "ここで食べます", "袋はいりません", "温めてください"],
               "bungkus は「包む」、dibawa pulang は「持ち帰る」です。", "ワルン"),
        single("Saya alergi udang.",
               ["エビのアレルギーがあります", "エビが好きです", "エビを追加してください", "エビは高いです"],
               "alergi はアレルギー、udang はエビです。", "ワルン"),
        single("Jam berapa sekarang?",
               ["今何時ですか", "何時に始まりますか", "どのくらいかかりますか", "いつ行きますか"],
               "jam berapa は時刻を尋ね、sekarang は「今」です。", "あいさつ"),
        single("Kartu saya tidak bisa dipakai.",
               ["私のカードが使えません", "私のカードをなくしました", "カードで払います", "カードはありますか"],
               "dipakai は「使われる」。tidak bisa で「〜できない」です。", "コンビニ"),
        single("Tolong panggil taksi.",
               ["タクシーを呼んでください", "タクシーはどこですか", "タクシーで行きます", "タクシーは高いです"],
               "panggil は「呼ぶ」です。", "Grab"),
        single("Berapa lama perjalanannya?",
               ["移動はどのくらいかかりますか", "いくらかかりますか", "何時に着きますか", "どこへ行きますか"],
               "berapa lama は所要時間、perjalanan は「移動・道のり」です。", "Grab"),
        single("Saya menginap di hotel dekat sini.",
               ["この近くのホテルに泊まっています", "この近くのホテルを探しています", "ホテルは遠いです", "ホテルまで歩きます"],
               "menginap は「宿泊する」、dekat sini は「この近く」です。", "Grab"),
        single("Tolong tunggu sebentar.",
               ["少し待ってください", "急いでください", "また来てください", "先に行ってください"],
               "tunggu は「待つ」、sebentar は「少しの間」です。", "空港"),
        single("Ada yang bisa berbahasa Inggris?",
               ["英語が話せる人はいますか", "英語で書いてください", "英語のメニューはありますか", "英語を勉強しています"],
               "ada yang bisa は「〜できる人がいる」です。", "空港"),
        single("Saya mau bayar dengan kartu.",
               ["カードで払いたいです", "現金で払います", "領収書をください", "両替したいです"],
               "bayar は「払う」、dengan kartu は「カードで」です。", "コンビニ"),
        single("Permisi, boleh numpang lewat?",
               ["すみません、通してもらえますか", "すみません、道を教えてください", "すみません、席は空いていますか", "すみません、手伝ってください"],
               "numpang lewat は「通して通る」で、人の前を通るときの定型です。", "空港"),
        single("Tolong isi bensin penuh.",
               ["ガソリンを満タンにしてください", "ガソリンスタンドはどこですか", "ガソリンが切れました", "ガソリン代を払います"],
               "isi は「入れる」、penuh は「いっぱい」です。", "Grab"),
        single("Saya sudah pesan lewat aplikasi.",
               ["アプリで予約済みです", "アプリで予約したいです", "アプリが使えません", "アプリを消しました"],
               "sudah は完了、lewat aplikasi は「アプリ経由で」です。", "Grab"),
        single("Airnya tidak dingin.",
               ["水が冷たくないです", "水がありません", "水が熱いです", "水をください"],
               "dingin は「冷たい」。tidak で否定します。", "ワルン"),
        single("Tolong tambah sambal.",
               ["サンバルを追加してください", "サンバルは要りません", "サンバルは辛いですか", "サンバルはどこですか"],
               "tambah は「追加する」です。", "ワルン"),
        single("Kembaliannya kurang.",
               ["おつりが足りません", "おつりは要りません", "おつりをください", "おつりが多いです"],
               "kembalian は「おつり」、kurang は「足りない」です。", "コンビニ"),
        single("Bisa pakai QRIS?",
               ["QRISは使えますか", "QRISで払いました", "QRISを登録したいです", "QRISは便利です"],
               "bisa pakai で「使えるか」を尋ねます。", "コンビニ"),
        single("Tolong tulis alamatnya di sini.",
               ["ここに住所を書いてください", "住所を教えてください", "住所が分かりません", "ここが私の住所です"],
               "tulis は「書く」、alamat は「住所」です。", "空港"),
        single("Saya baru pertama kali ke sini.",
               ["ここに来るのは初めてです", "ここには何度も来ています", "ここは初めての店です", "ここで待っています"],
               "baru pertama kali で「初めて」を表します。", "あいさつ"),
        single("Hati-hati di jalan.",
               ["道中お気をつけて", "道が混んでいます", "道を教えてください", "道で待っています"],
               "hati-hati は「気をつけて」、di jalan は「道で」です。別れ際の定型です。", "あいさつ"),
        dialogue("Mau pesan apa?", "Saya mau es teh manis.",
                 ["注文を聞かれ、甘いアイスティーを頼んだ", "注文を聞かれ、温かいお茶を頼んだ",
                  "会計を頼み、現金で払った", "席を尋ね、窓側を頼んだ"],
                 "es は氷、teh manis は甘い紅茶です。es teh manis で「甘いアイスティー」。", "ワルン"),
        dialogue("Bapak mau ke mana?", "Ke stasiun, ya.",
                 ["行き先を聞かれ、駅までと答えた", "行き先を聞かれ、空港までと答えた",
                  "料金を聞かれ、値切った", "到着時刻を聞かれ、7時と答えた"],
                 "ke mana は「どこへ」、stasiun は駅です。", "Grab"),
        dialogue("Ada yang bisa saya bantu?", "Saya cari obat sakit kepala.",
                 ["用件を聞かれ、頭痛薬を探していると答えた", "用件を聞かれ、胃薬を探していると答えた",
                  "体調を聞かれ、熱があると答えた", "支払い方法を聞かれ、カードと答えた"],
                 "obat は薬、sakit kepala は頭痛です。", "コンビニ"),
        dialogue("Totalnya lima puluh ribu.", "Saya bayar pakai kartu.",
                 ["合計5万ルピアと言われ、カードで払うと答えた", "合計1万5千ルピアと言われ、現金で払うと答えた",
                  "合計5万ルピアと言われ、高いと断った", "合計5万ルピアと言われ、割り勘にした"],
                 "lima puluh ribu は5万。lima belas ribu（1万5千）と聞き分けます。", "買い物"),
        dialogue("Paspornya, Pak.", "Ini, silakan.",
                 ["パスポートを求められ、どうぞと渡した", "パスポートを求められ、無くしたと答えた",
                  "搭乗券を求められ、どうぞと渡した", "荷物を預けるか聞かれ、断った"],
                 "silakan は「どうぞ」。ini と一緒に手渡すときに使います。", "空港"),
        dialogue("Mau pedas atau tidak?", "Jangan pedas, ya.",
                 ["辛さを聞かれ、辛くしないよう頼んだ", "辛さを聞かれ、とても辛くと頼んだ",
                  "量を聞かれ、少なめと頼んだ", "持ち帰りか聞かれ、店内と答えた"],
                 "jangan は「〜しないで」。pedas は辛いです。", "ワルン"),
        dialogue("Kamarnya untuk berapa malam?", "Dua malam.",
                 ["何泊か聞かれ、2泊と答えた", "何名か聞かれ、2名と答えた",
                  "何泊か聞かれ、1泊と答えた", "何時に着くか聞かれ、2時と答えた"],
                 "malam は夜・泊、dua は2です。berapa malam で「何泊」。", "Grab"),
        dialogue("Sudah makan?", "Belum, nanti saja.",
                 ["食事を済ませたか聞かれ、まだで後にすると答えた", "食事を済ませたか聞かれ、もう食べたと答えた",
                  "空腹か聞かれ、大丈夫だと答えた", "何を食べるか聞かれ、後で決めると答えた"],
                 "sudah は完了、belum は「まだ」。nanti saja は「後でいい」です。", "あいさつ"),
        dialogue("Boleh minta struknya?", "Sebentar, ya.",
                 ["レシートを頼まれ、少し待つよう答えた", "レシートを頼まれ、出せないと答えた",
                  "袋を頼まれ、少し待つよう答えた", "会計を頼まれ、合計を伝えた"],
                 "struk はレシート、sebentar は「少し待って」です。", "コンビニ"),
        dialogue("Jam berapa kita berangkat?", "Jam tujuh pagi.",
                 ["出発時刻を聞かれ、朝7時と答えた", "出発時刻を聞かれ、夜7時と答えた",
                  "到着時刻を聞かれ、朝7時と答えた", "集合場所を聞かれ、ロビーと答えた"],
                 "berangkat は「出発する」、pagi は朝です。malam なら夜になります。", "空港")
    ]

    static let questions: [LearningQuestion] = templates.enumerated().compactMap { index, template in
        let number = index + 1
        let choices = template.choices.enumerated().map { choiceIndex, text in
            LearningChoice(
                id: ChoiceID(rawValue: "demo-question-\(number)-choice-\(choiceIndex + 1)"),
                text: text
            )
        }

        guard let correctChoice = choices.first else { return nil }

        return LearningQuestion(
            id: QuestionID(rawValue: "demo-question-\(number)"),
            utterances: template.lines.map { ScriptedUtterance(speakerIndex: $0.speaker, text: $0.text) },
            choices: choices,
            correctChoiceID: correctChoice.id,
            explanation: template.explanation,
            scenarioName: template.scenario
        )
    }
}
