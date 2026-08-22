import Foundation

/// プロトタイプ用の教材パック。
///
/// 各問の `choices` は先頭を正解として書く。表示順はセッションごとに入れ替わるため、
/// ここでの並びが学習者に見える順序になることはない。
/// 誤答は無作為に作らず、音の類似・意味の近さ・場面違いのいずれかの理由を持たせる。
enum DemoLearningContent {
    /// 教材を差し替えたら版を上げる。版が変わると保存済みセッションは復帰せず破棄される。
    static let version = "demo-2026-08-v5"

    static var pack: LearningContentPack {
        LearningContentPack(version: version, questions: questions)
    }

    private struct Template: Sendable {
        let lines: [(speaker: Int, text: String)]
        let choices: [String]
        let explanation: String
        /// 生活図鑑のどのカテゴリで使う教材か。級別入口と共通のプールを保つ。
        let scenarios: [ScenarioID]
        let level: CertificationLevel
        let questionType: QuestionType
        /// この問題の誤答を作った理由。無作為な誤答を置かない。
        let distractorReason: DistractorReason
    }

    private static func single(
        _ text: String,
        _ choices: [String],
        _ explanation: String,
        _ scenarios: [ScenarioID],
        level: CertificationLevel = .e,
        type: QuestionType = .audioMeaningChoice,
        distractorReason: DistractorReason = .semanticNeighbor
    ) -> Template {
        Template(
            lines: [(0, text)],
            choices: choices,
            explanation: explanation,
            scenarios: scenarios,
            level: level,
            questionType: type,
            distractorReason: distractorReason
        )
    }

    private static func dialogue(
        _ first: String,
        _ second: String,
        _ choices: [String],
        _ explanation: String,
        _ scenarios: [ScenarioID],
        level: CertificationLevel = .e,
        type: QuestionType = .contentMatch,
        distractorReason: DistractorReason = .wrongContext
    ) -> Template {
        Template(
            lines: [(0, first), (1, second)],
            choices: choices,
            explanation: explanation,
            scenarios: scenarios,
            level: level,
            questionType: type,
            distractorReason: distractorReason
        )
    }

    /// D級の内容一致。旅行・買い物・移動の定型会話を聞き、内容と合うものを選ぶ。
    private static func contentMatchD(
        _ first: String,
        _ second: String,
        _ choices: [String],
        _ explanation: String,
        _ scenarios: [ScenarioID],
        distractorReason: DistractorReason = .semanticNeighbor
    ) -> Template {
        dialogue(first, second, choices, explanation, scenarios,
                 level: .d, type: .contentMatch, distractorReason: distractorReason)
    }

    /// D級の行動判断。案内を聞いて、その場で取るべき行動を選ぶ。
    private static func actionDecisionD(
        _ text: String,
        _ choices: [String],
        _ explanation: String,
        _ scenarios: [ScenarioID],
        distractorReason: DistractorReason = .wrongContext
    ) -> Template {
        single(text, choices, explanation, scenarios,
               level: .d, type: .actionDecision, distractorReason: distractorReason)
    }

    private static let templates: [Template] = [
        single("Selamat pagi.",
               ["おはようございます", "こんばんは", "おやすみなさい", "さようなら"],
               "selamat はあいさつの頭に付き、pagi は朝を指します。", [.airport, .convenience]),
        single("Terima kasih banyak.",
               ["本当にありがとうございます", "どういたしまして", "すみません", "お願いします"],
               "terima kasih が「ありがとう」、banyak が「たくさん」で感謝を強めます。", [.warung, .convenience]),
        single("Berapa harganya?",
               ["いくらですか", "どこですか", "何時ですか", "いくつありますか"],
               "berapa は数量や値段を尋ね、harganya は「その値段」です。", [.convenience]),
        single("Di mana toilet?",
               ["トイレはどこですか", "トイレは使えますか", "トイレは何時までですか", "トイレは新しいですか"],
               "di mana は場所を尋ねる表現です。", [.convenience, .airport]),
        single("Saya mau pesan nasi goreng.",
               ["ナシゴレンを注文したいです", "ナシゴレンを作りました", "ナシゴレンは辛いですか", "ナシゴレンが好きです"],
               "mau は「〜したい」、pesan は「注文する」です。", [.warung]),
        single("Tolong antar saya ke bandara.",
               ["空港まで送ってください", "空港で待っていてください", "空港はどこですか", "空港まで歩きます"],
               "tolong は依頼、antar は「送る」、ke bandara は「空港へ」です。", [.grab]),
        single("Saya tidak mengerti.",
               ["わかりません", "知っています", "聞こえています", "話せます"],
               "tidak は否定、mengerti は「理解する」です。", [.airport]),
        single("Bisa bicara pelan-pelan?",
               ["ゆっくり話してもらえますか", "大きい声で話してください", "もう一度書いてください", "英語で話せますか"],
               "pelan-pelan は「ゆっくり」。bisa は可能を尋ねます。", [.airport]),
        single("Ini terlalu mahal.",
               ["これは高すぎます", "これは安いです", "これは新しいです", "これは重いです"],
               "terlalu は「〜すぎる」、mahal は「高い」です。", [.convenience]),
        single("Boleh saya lihat?",
               ["見てもいいですか", "買ってもいいですか", "持って帰ってもいいですか", "使ってもいいですか"],
               "boleh は許可を尋ね、lihat は「見る」です。", [.convenience]),
        single("Tolong bungkus untuk dibawa pulang.",
               ["持ち帰り用に包んでください", "ここで食べます", "袋はいりません", "温めてください"],
               "bungkus は「包む」、dibawa pulang は「持ち帰る」です。", [.warung]),
        single("Saya alergi udang.",
               ["エビのアレルギーがあります", "エビが好きです", "エビを追加してください", "エビは高いです"],
               "alergi はアレルギー、udang はエビです。", [.warung]),
        single("Jam berapa sekarang?",
               ["今何時ですか", "何時に始まりますか", "どのくらいかかりますか", "いつ行きますか"],
               "jam berapa は時刻を尋ね、sekarang は「今」です。", [.airport]),
        single("Kartu saya tidak bisa dipakai.",
               ["私のカードが使えません", "私のカードをなくしました", "カードで払います", "カードはありますか"],
               "dipakai は「使われる」。tidak bisa で「〜できない」です。", [.convenience]),
        single("Tolong panggil taksi.",
               ["タクシーを呼んでください", "タクシーはどこですか", "タクシーで行きます", "タクシーは高いです"],
               "panggil は「呼ぶ」です。", [.grab]),
        single("Berapa lama perjalanannya?",
               ["移動はどのくらいかかりますか", "いくらかかりますか", "何時に着きますか", "どこへ行きますか"],
               "berapa lama は所要時間、perjalanan は「移動・道のり」です。", [.grab]),
        single("Saya menginap di hotel dekat sini.",
               ["この近くのホテルに泊まっています", "この近くのホテルを探しています", "ホテルは遠いです", "ホテルまで歩きます"],
               "menginap は「宿泊する」、dekat sini は「この近く」です。", [.grab]),
        single("Tolong tunggu sebentar.",
               ["少し待ってください", "急いでください", "また来てください", "先に行ってください"],
               "tunggu は「待つ」、sebentar は「少しの間」です。", [.airport]),
        single("Ada yang bisa berbahasa Inggris?",
               ["英語が話せる人はいますか", "英語で書いてください", "英語のメニューはありますか", "英語を勉強しています"],
               "ada yang bisa は「〜できる人がいる」です。", [.airport]),
        single("Saya mau bayar dengan kartu.",
               ["カードで払いたいです", "現金で払います", "領収書をください", "両替したいです"],
               "bayar は「払う」、dengan kartu は「カードで」です。", [.convenience]),
        single("Permisi, boleh numpang lewat?",
               ["すみません、通してもらえますか", "すみません、道を教えてください", "すみません、席は空いていますか", "すみません、手伝ってください"],
               "numpang lewat は「通して通る」で、人の前を通るときの定型です。", [.airport]),
        single("Tolong isi bensin penuh.",
               ["ガソリンを満タンにしてください", "ガソリンスタンドはどこですか", "ガソリンが切れました", "ガソリン代を払います"],
               "isi は「入れる」、penuh は「いっぱい」です。", [.grab]),
        single("Saya sudah pesan lewat aplikasi.",
               ["アプリで予約済みです", "アプリで予約したいです", "アプリが使えません", "アプリを消しました"],
               "sudah は完了、lewat aplikasi は「アプリ経由で」です。", [.grab]),
        single("Airnya tidak dingin.",
               ["水が冷たくないです", "水がありません", "水が熱いです", "水をください"],
               "dingin は「冷たい」。tidak で否定します。", [.warung]),
        single("Tolong tambah sambal.",
               ["サンバルを追加してください", "サンバルは要りません", "サンバルは辛いですか", "サンバルはどこですか"],
               "tambah は「追加する」です。", [.warung]),
        single("Kembaliannya kurang.",
               ["おつりが足りません", "おつりは要りません", "おつりをください", "おつりが多いです"],
               "kembalian は「おつり」、kurang は「足りない」です。", [.convenience]),
        single("Bisa pakai QRIS?",
               ["QRISは使えますか", "QRISで払いました", "QRISを登録したいです", "QRISは便利です"],
               "bisa pakai で「使えるか」を尋ねます。", [.convenience]),
        single("Tolong tulis alamatnya di sini.",
               ["ここに住所を書いてください", "住所を教えてください", "住所が分かりません", "ここが私の住所です"],
               "tulis は「書く」、alamat は「住所」です。", [.grab, .airport]),
        single("Saya baru pertama kali ke sini.",
               ["ここに来るのは初めてです", "ここには何度も来ています", "ここは初めての店です", "ここで待っています"],
               "baru pertama kali で「初めて」を表します。", [.airport]),
        single("Hati-hati di jalan.",
               ["道中お気をつけて", "道が混んでいます", "道を教えてください", "道で待っています"],
               "hati-hati は「気をつけて」、di jalan は「道で」です。別れ際の定型です。", [.grab]),
        dialogue("Mau pesan apa?", "Saya mau es teh manis.",
                 ["注文を聞かれ、甘いアイスティーを頼んだ", "注文を聞かれ、温かいお茶を頼んだ",
                  "会計を頼み、現金で払った", "席を尋ね、窓側を頼んだ"],
                 "es は氷、teh manis は甘い紅茶です。es teh manis で「甘いアイスティー」。", [.warung]),
        dialogue("Bapak mau ke mana?", "Ke stasiun, ya.",
                 ["行き先を聞かれ、駅までと答えた", "行き先を聞かれ、空港までと答えた",
                  "料金を聞かれ、値切った", "到着時刻を聞かれ、7時と答えた"],
                 "ke mana は「どこへ」、stasiun は駅です。", [.grab]),
        dialogue("Ada yang bisa saya bantu?", "Saya cari obat sakit kepala.",
                 ["用件を聞かれ、頭痛薬を探していると答えた", "用件を聞かれ、胃薬を探していると答えた",
                  "体調を聞かれ、熱があると答えた", "支払い方法を聞かれ、カードと答えた"],
                 "obat は薬、sakit kepala は頭痛です。", [.convenience]),
        dialogue("Totalnya lima puluh ribu.", "Saya bayar pakai kartu.",
                 ["合計5万ルピアと言われ、カードで払うと答えた", "合計1万5千ルピアと言われ、現金で払うと答えた",
                  "合計5万ルピアと言われ、高いと断った", "合計5万ルピアと言われ、割り勘にした"],
                 "lima puluh ribu は5万。lima belas ribu（1万5千）と聞き分けます。", [.convenience]),
        dialogue("Paspornya, Pak.", "Ini, silakan.",
                 ["パスポートを求められ、どうぞと渡した", "パスポートを求められ、無くしたと答えた",
                  "搭乗券を求められ、どうぞと渡した", "荷物を預けるか聞かれ、断った"],
                 "silakan は「どうぞ」。ini と一緒に手渡すときに使います。", [.airport]),
        dialogue("Mau pedas atau tidak?", "Jangan pedas, ya.",
                 ["辛さを聞かれ、辛くしないよう頼んだ", "辛さを聞かれ、とても辛くと頼んだ",
                  "量を聞かれ、少なめと頼んだ", "持ち帰りか聞かれ、店内と答えた"],
                 "jangan は「〜しないで」。pedas は辛いです。", [.warung]),
        dialogue("Kamarnya untuk berapa malam?", "Dua malam.",
                 ["何泊か聞かれ、2泊と答えた", "何名か聞かれ、2名と答えた",
                  "何泊か聞かれ、1泊と答えた", "何時に着くか聞かれ、2時と答えた"],
                 "malam は夜・泊、dua は2です。berapa malam で「何泊」。", [.grab]),
        dialogue("Sudah makan?", "Belum, nanti saja.",
                 ["食事を済ませたか聞かれ、まだで後にすると答えた", "食事を済ませたか聞かれ、もう食べたと答えた",
                  "空腹か聞かれ、大丈夫だと答えた", "何を食べるか聞かれ、後で決めると答えた"],
                 "sudah は完了、belum は「まだ」。nanti saja は「後でいい」です。", [.warung]),
        dialogue("Boleh minta struknya?", "Sebentar, ya.",
                 ["レシートを頼まれ、少し待つよう答えた", "レシートを頼まれ、出せないと答えた",
                  "袋を頼まれ、少し待つよう答えた", "会計を頼まれ、合計を伝えた"],
                 "struk はレシート、sebentar は「少し待って」です。", [.convenience]),
        dialogue("Jam berapa kita berangkat?", "Jam tujuh pagi.",
                 ["出発時刻を聞かれ、朝7時と答えた", "出発時刻を聞かれ、夜7時と答えた",
                  "到着時刻を聞かれ、朝7時と答えた", "集合場所を聞かれ、ロビーと答えた"],
                 "berangkat は「出発する」、pagi は朝です。malam なら夜になります。", [.airport]),

        // --- D級: 旅行・買い物・移動の定型会話（内容一致） ---
        contentMatchD("Maaf, penerbangan ke Surabaya ditunda satu jam.", "Kalau begitu saya menunggu di sini.",
                      ["1時間の遅れを知らされ、ここで待つと答えた", "1時間早まると知らされ、急ぐと答えた",
                       "欠航を知らされ、別の便に変えると答えた", "搭乗口の変更を知らされ、移動すると答えた"],
                      "ditunda は「遅らせる」。satu jam は1時間です。", [.airport]),
        contentMatchD("Kamarnya sudah siap. Atas nama siapa?", "Atas nama Tanaka, dua malam.",
                      ["部屋の準備ができ、田中名義で2泊と伝えた", "部屋がまだで、田中名義で2泊待つと伝えた",
                       "部屋の準備ができ、田中名義で2名と伝えた", "部屋を変更し、2泊延長すると伝えた"],
                      "atas nama は「〜名義で」、dua malam は2泊です。dua orang（2名）と聞き分けます。", [.grab]),
        contentMatchD("Mau ambil yang mana, yang merah atau yang biru?", "Yang biru saja, tapi ukuran L.",
                      ["青のLサイズを選んだ", "赤のLサイズを選んだ",
                       "青のMサイズを選んだ", "どちらも要らないと答えた"],
                      "biru は青、merah は赤。ukuran はサイズです。", [.convenience]),
        contentMatchD("Maaf, uang pasnya ada?", "Tidak ada. Saya bayar pakai seratus ribu.",
                      ["細かいお金が無く、10万ルピア札で払うと伝えた", "細かいお金があり、ちょうど払うと伝えた",
                       "1万ルピア札で払うと伝えた", "カードで払うと伝えた"],
                      "uang pas は「ちょうどのお金」。seratus ribu は10万です。", [.convenience]),
        contentMatchD("Lurus saja, nanti belok kiri di lampu merah.", "Setelah lampu merah, kiri ya?",
                      ["まっすぐ進み、信号を左折すると確認した", "まっすぐ進み、信号を右折すると確認した",
                       "信号の手前で左折すると確認した", "信号で引き返すと確認した"],
                      "lurus は直進、belok kiri は左折、lampu merah は信号です。", [.grab]),
        contentMatchD("Pesanannya sudah lengkap?", "Tambah satu es jeruk, ya.",
                      ["注文にオレンジジュースを1つ追加した", "注文を1つ取り消した",
                       "注文はこれで完了だと答えた", "オレンジジュースを2つ追加した"],
                      "lengkap は「そろっている」、tambah satu は「1つ追加」です。", [.warung]),
        contentMatchD("Bagasinya berapa kilo?", "Dua puluh tiga kilo, pas.",
                      ["荷物は23キロちょうどだと答えた", "荷物は32キロだと答えた",
                       "荷物は23キロを超えていると答えた", "荷物は預けないと答えた"],
                      "dua puluh tiga は23、tiga puluh dua は32です。pas は「ちょうど」。", [.airport]),
        contentMatchD("Maaf, ini sedang kosong. Besok baru ada.", "Baik, saya datang lagi besok.",
                      ["在庫切れと言われ、明日また来ると答えた", "在庫があると言われ、今日買うと答えた",
                       "在庫切れと言われ、別の店に行くと答えた", "取り置きを頼んだ"],
                      "kosong は「空・在庫なし」、besok baru ada は「明日入る」です。", [.convenience]),
        contentMatchD("Bisa tolong turunkan di depan minimarket?", "Bisa, tapi agak jauh sedikit ya.",
                      ["ミニマート前で降ろすよう頼み、少し先になると言われた", "ミニマート前で降ろすよう頼み、断られた",
                       "ミニマートで買い物を頼んだ", "ミニマートの場所を尋ねた"],
                      "turunkan は「降ろす」、agak jauh sedikit は「少し遠い」です。", [.grab]),
        contentMatchD("Sudah termasuk pajak?", "Belum. Nanti ditambah sepuluh persen.",
                      ["税は未込みで、あとで10%加算されると説明された", "税込みだと説明された",
                       "税は未込みで、あとで20%加算されると説明された", "税は不要だと説明された"],
                      "termasuk は「含む」、pajak は税、sepuluh persen は10%です。", [.convenience]),

        // --- D級: 行動判断 ---
        actionDecisionD("Mohon sabuk pengaman dipasang kembali.",
                        ["シートベルトを締め直す", "シートベルトを外す",
                         "座席を倒す", "荷物を頭上の棚に入れる"],
                        "sabuk pengaman はシートベルト、dipasang kembali は「再び装着する」です。", [.airport]),
        actionDecisionD("Silakan isi formulir ini dulu, lalu antre di loket dua.",
                        ["用紙に記入してから2番窓口に並ぶ", "先に2番窓口に並んでから記入する",
                         "用紙を記入して1番窓口に並ぶ", "用紙を係員に渡して待つ"],
                        "isi formulir は「用紙に記入する」、lalu は「そのあと」、loket は窓口です。", [.airport]),
        actionDecisionD("Maaf, kartunya tidak terbaca. Ada cara bayar lain?",
                        ["別の支払い方法を出す", "同じカードをもう一度渡す",
                         "会計をやめて店を出る", "レシートを見せる"],
                        "tidak terbaca は「読み取れない」、cara bayar lain は「別の支払い方法」です。", [.convenience]),
        actionDecisionD("Motornya tidak bisa masuk gang ini. Turun di sini ya.",
                        ["ここで降りて歩く", "そのまま路地へ入ってもらう",
                         "別の車を呼ぶ", "運転手に引き返してもらう"],
                        "gang は路地。tidak bisa masuk は「入れない」、turun は「降りる」です。", [.grab]),
        actionDecisionD("Tolong tunjukkan struk kalau mau tukar barang.",
                        ["レシートを見せる", "商品をそのまま持ち帰る",
                         "身分証を見せる", "袋を用意する"],
                        "tunjukkan は「見せる」、struk はレシート、tukar barang は「商品交換」です。", [.convenience]),
        actionDecisionD("Airnya jangan diminum langsung dari keran.",
                        ["水道水はそのまま飲まない", "水道水を沸かさずに飲む",
                         "水を買わずに済ませる", "水を止める"],
                        "jangan は禁止、langsung は「そのまま」、keran は蛇口です。", [.warung]),
        actionDecisionD("Antreannya di sebelah kanan. Yang kiri untuk kirim paket.",
                        ["右の列に並ぶ", "左の列に並ぶ",
                         "荷物を先に預ける", "窓口の人を呼ぶ"],
                        "antrean は列、sebelah kanan は右側です。kiri（左）と聞き分けます。", [.convenience]),
        actionDecisionD("Kalau hujan deras, lebih baik tunggu dulu di dalam.",
                        ["雨が弱まるまで屋内で待つ", "傘を買ってすぐ出発する",
                         "急いで外に出る", "配車をキャンセルする"],
                        "hujan deras は大雨、lebih baik は「〜した方がよい」、di dalam は屋内です。", [.grab]),
        actionDecisionD("Sandalnya dilepas dulu sebelum masuk.",
                        ["サンダルを脱いでから入る", "サンダルを履いたまま入る",
                         "サンダルを持って入る", "靴に履き替える"],
                        "dilepas は「脱ぐ」、sebelum masuk は「入る前に」です。", [.warung]),
        actionDecisionD("Pembayaran hanya bisa tunai, ya.",
                        ["現金を用意する", "カードを出す",
                         "QRISで払う", "後日払うと伝える"],
                        "hanya bisa tunai は「現金のみ」です。", [.warung])
    ]

    static let questions: [LearningQuestion] = templates.enumerated().compactMap { index, template in
        let number = index + 1
        let choices = template.choices.enumerated().map { choiceIndex, text in
            LearningChoice(
                id: ChoiceID(rawValue: "demo-question-\(number)-choice-\(choiceIndex + 1)"),
                text: text,
                isCorrect: choiceIndex == 0,
                distractorReason: choiceIndex == 0 ? nil : template.distractorReason
            )
        }

        guard let correctChoice = choices.first else { return nil }

        return LearningQuestion(
            id: QuestionID(rawValue: "demo-question-\(number)"),
            level: template.level,
            questionType: template.questionType,
            status: .published,
            utterances: template.lines.map { ScriptedUtterance(speakerIndex: $0.speaker, text: $0.text) },
            choices: choices,
            correctChoiceID: correctChoice.id,
            explanation: template.explanation,
            scenarioIDs: template.scenarios
        )
    }
}
