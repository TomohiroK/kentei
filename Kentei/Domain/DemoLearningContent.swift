import Foundation

/// プロトタイプ用の教材パック。
///
/// 各問の `choices` は先頭を正解として書く。表示順はセッションごとに入れ替わるため、
/// ここでの並びが学習者に見える順序になることはない。
/// 誤答は無作為に作らず、音の類似・意味の近さ・場面違いのいずれかの理由を持たせる。
enum DemoLearningContent {
    /// 教材を差し替えたら版を上げる。版が変わると保存済みセッションは復帰せず破棄される。
    static let version = "demo-2026-08-v7"

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

    /// C級。生活手続きの説明を理解する。接辞と受動を含む文を扱う。
    private static func singleC(
        _ text: String,
        _ choices: [String],
        _ explanation: String,
        _ scenarios: [ScenarioID],
        type: QuestionType = .audioMeaningChoice,
        distractorReason: DistractorReason = .differentAffix
    ) -> Template {
        single(text, choices, explanation, scenarios,
               level: .c, type: type, distractorReason: distractorReason)
    }

    /// C級の会話。手続きのやりとりを聞き、内容と合うものを選ぶ。
    private static func contentMatchC(
        _ first: String,
        _ second: String,
        _ choices: [String],
        _ explanation: String,
        _ scenarios: [ScenarioID],
        distractorReason: DistractorReason = .semanticNeighbor
    ) -> Template {
        dialogue(first, second, choices, explanation, scenarios,
                 level: .c, type: .contentMatch, distractorReason: distractorReason)
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
                        "hanya bisa tunai は「現金のみ」です。", [.warung]),

        // --- C級: 病院 ---
        singleC("Silakan didaftarkan dulu di loket pendaftaran.",
                ["先に受付窓口で登録してください", "先に受付窓口で支払ってください",
                 "受付窓口で書類を受け取ってください", "受付窓口で順番を待ってください"],
                "didaftarkan は daftar（登録）の受動形。di- + -kan で「登録してもらう」を表します。", [.hospital]),
        contentMatchC("Sudah berapa lama demamnya?", "Sejak kemarin malam, disertai batuk.",
                      ["昨夜から熱があり、咳を伴うと答えた", "今朝から熱があり、頭痛を伴うと答えた",
                       "昨夜から咳だけがあると答えた", "熱は下がったが咳が残ると答えた"],
                      "disertai は sertai の受動で「〜を伴う」。sejak は「〜から」です。", [.hospital]),
        singleC("Obatnya harus diminum setelah makan.",
                ["薬は食後に飲む必要がある", "薬は食前に飲む必要がある",
                 "薬は食事と一緒に飲む必要がある", "薬は寝る前に飲む必要がある"],
                "diminum は minum の受動形。harus は義務、setelah makan は食後です。", [.hospital],
                type: .grammarFunctionChoice),

        // --- C級: 薬局 ---
        singleC("Resepnya bisa ditebus di apotek sebelah.",
                ["処方箋は隣の薬局で受け取れる", "処方箋は隣の薬局で書いてもらえる",
                 "処方箋は病院の窓口で受け取る", "処方箋は明日また持ってくる"],
                "ditebus は tebus（引き換える）の受動。処方箋を薬に換えることを指します。", [.pharmacy]),
        singleC("Jangan dikonsumsi bersamaan dengan alkohol.",
                ["アルコールと一緒に摂取しない", "アルコールの後に摂取する",
                 "アルコールの代わりに摂取する", "アルコールと一緒なら少量にする"],
                "dikonsumsi は konsumsi の受動。jangan で禁止、bersamaan dengan は「〜と同時に」。",
                [.pharmacy], type: .grammarFunctionChoice),
        contentMatchC("Ada efek sampingnya?", "Bisa mengantuk, jadi jangan menyetir.",
                      ["眠気が出るため運転しないよう言われた", "副作用は無いと言われた",
                       "眠気が出るため水を多く飲むよう言われた", "運転しても問題ないと言われた"],
                      "efek samping は副作用、mengantuk は「眠くなる」、menyetir は「運転する」です。", [.pharmacy]),

        // --- C級: 銀行 ---
        singleC("Rekeningnya akan diaktifkan dalam dua hari kerja.",
                ["口座は2営業日以内に有効化される", "口座は2日以内に解約される",
                 "口座は2週間以内に有効化される", "口座は当日中に有効化される"],
                "diaktifkan は aktif の受動使役形。hari kerja は営業日です。", [.bank]),
        singleC("Transfer antarbank dikenakan biaya administrasi.",
                ["他行宛ての送金には手数料がかかる", "他行宛ての送金は手数料が無料になる",
                 "同じ銀行宛ての送金に手数料がかかる", "送金の上限額が決まっている"],
                "dikenakan は kena の受動使役で「課される」。antarbank は銀行間です。", [.bank]),
        contentMatchC("Duitnya belum masuk, ya?", "Dananya sedang diproses, Pak.",
                      ["入金がまだで、処理中だと説明された", "入金は完了したと説明された",
                       "入金が取り消されたと説明された", "入金額が違うと説明された"],
                      "duit は口語、dana は標準語で「お金・資金」。diproses は「処理される」です。",
                      [.bank], distractorReason: .registerConfusion),

        // --- C級: SIM・通信 ---
        singleC("Kartunya harus diregistrasi dengan nomor KTP.",
                ["SIMはKTP番号で登録する必要がある", "SIMはパスポート番号で登録する必要がある",
                 "SIMは登録しなくても使える", "SIMは店舗でしか買えない"],
                "diregistrasi は registrasi の受動。KTP はインドネシアの身分証です。", [.simCard]),
        singleC("Kuotanya habis, silakan diisi ulang.",
                ["データ容量が切れたので、チャージしてください", "データ容量はまだ残っている",
                 "電池が切れたので充電してください", "契約が切れたので更新してください"],
                "kuota はデータ容量、diisi ulang は「補充される」＝チャージです。", [.simCard]),
        contentMatchC("Paketnya berlaku berapa lama?", "Berlaku tiga puluh hari sejak diaktifkan.",
                      ["有効化から30日間有効だと答えた", "購入から13日間有効だと答えた",
                       "有効化から3日間有効だと答えた", "使い切るまで有効だと答えた"],
                      "berlaku は「有効である」。tiga puluh（30）と tiga belas（13）を聞き分けます。", [.simCard]),

        // --- C級: 配送 ---
        singleC("Paketnya akan dikirim ulang besok pagi.",
                ["荷物は明日の午前に再配達される", "荷物は明日の午後に再配達される",
                 "荷物は差出人へ返送される", "荷物は営業所で受け取る"],
                "dikirim ulang は「再び送られる」。kirim の受動に ulang（再び）が付きます。", [.delivery]),
        contentMatchC("Paketnya sudah sampai?", "Sudah, diterima oleh penjaga kos.",
                      ["下宿の管理人が受け取り済みだと答えた", "まだ届いていないと答えた",
                       "本人が受け取ったと答えた", "配達員が持ち帰ったと答えた"],
                      "diterima は terima の受動、oleh は行為者を示します。", [.delivery]),
        singleC("Nomor resinya bisa dilacak lewat aplikasi.",
                ["追跡番号はアプリで追跡できる", "追跡番号は電話でしか確認できない",
                 "追跡番号は発行されない", "追跡番号は配達完了後に届く"],
                "resi は送り状番号、dilacak は lacak（追跡する）の受動です。", [.delivery]),

        // --- C級: 家 ---
        singleC("Sewanya dibayarkan setiap tanggal lima.",
                ["家賃は毎月5日に支払う", "家賃は毎月15日に支払う",
                 "家賃は3か月ごとに支払う", "家賃は入居時に一括で支払う"],
                "dibayarkan は bayar の受動使役。tanggal lima は5日です。", [.housing]),
        singleC("AC-nya rusak, tolong diperbaiki secepatnya.",
                ["エアコンが壊れたので、早急に修理してほしい", "エアコンを新しく設置してほしい",
                 "エアコンの掃除をしてほしい", "エアコンの使い方を教えてほしい"],
                "diperbaiki は baik から派生した「修理される」。secepatnya は「できるだけ早く」。", [.housing]),
        singleC("Kontraknya diperpanjang otomatis kalau tidak dibatalkan.",
                ["解約しなければ契約は自動更新される", "解約しなければ契約は終了する",
                 "契約は毎回手続きが必要になる", "契約は自動で解約される"],
                "diperpanjang は panjang（長い）の受動使役で「延長される」。dibatalkan は「取り消される」。",
                [.housing], type: .grammarFunctionChoice),

        // --- C級: 警察 ---
        singleC("Laporan kehilangan bisa dibuat di kantor polisi terdekat.",
                ["紛失届は最寄りの警察署で作成できる", "紛失届は大使館で作成する",
                 "紛失届は電話でのみ受け付ける", "紛失届は翌日以降に受け付ける"],
                "kehilangan は hilang の ke-an 名詞形で「紛失」。dibuat は「作られる」です。", [.police]),
        singleC("Surat keterangannya diperlukan untuk mengurus paspor baru.",
                ["新しいパスポートの手続きに証明書が必要になる", "証明書は不要になった",
                 "証明書は帰国後に提出する", "証明書はパスポートの代わりに使える"],
                "keterangan は terang の名詞形、diperlukan は perlu の受動で「必要とされる」。", [.police]),
        contentMatchC("Ada yang bisa dijadikan bukti?", "Ada rekaman CCTV-nya.",
                      ["証拠になるものとしてCCTVの記録があると答えた", "証拠は何も無いと答えた",
                       "目撃者がいると答えた", "レシートが残っていると答えた"],
                      "dijadikan は jadi の受動使役で「〜にされる」。bukti は証拠です。", [.police]),

        // --- C級: 行政 ---
        singleC("Perpanjangan visanya diurus di kantor imigrasi.",
                ["ビザの延長は入国管理局で手続きする", "ビザの延長は大使館で手続きする",
                 "ビザの延長は空港で手続きする", "ビザの延長は郵送で手続きする"],
                "perpanjangan は panjang の per-an 名詞形。diurus は urus の受動です。", [.government]),
        singleC("Dokumennya harus dilegalisasi terlebih dahulu.",
                ["書類は先に認証を受ける必要がある", "書類は後から提出すればよい",
                 "書類は翻訳するだけでよい", "書類は原本を保管しておく"],
                "dilegalisasi は「認証される」。terlebih dahulu は「まず先に」です。", [.government]),
        contentMatchC("Antrean online-nya dibuka jam berapa?", "Dibuka setiap pukul delapan pagi.",
                      ["オンライン受付は毎朝8時に開くと答えた", "オンライン受付は毎朝7時に開くと答えた",
                       "オンライン受付は不要だと答えた", "オンライン受付は夜8時に開くと答えた"],
                      "dibuka は buka の受動。pukul delapan pagi は朝8時です。", [.government]),

        // --- C級: 職場 ---
        singleC("Laporannya dikumpulkan paling lambat hari Jumat.",
                ["報告書は遅くとも金曜までに提出する", "報告書は金曜以降に提出する",
                 "報告書は月曜までに提出する", "報告書の提出は任意である"],
                "dikumpulkan は kumpul の受動使役で「集められる＝提出される」。paling lambat は「遅くとも」。",
                [.workplace]),
        singleC("Rapatnya diundur ke minggu depan.",
                ["会議は来週に延期された", "会議は今週に前倒しされた",
                 "会議は中止になった", "会議は来月に延期された"],
                "diundur は undur の受動で「後ろへずらされる」＝延期です。", [.workplace]),
        singleC("Bisa tolong dikirimkan datanya?",
                ["承知しました、夕方に送ります", "承知しました、データを消します",
                 "すみません、データは受け取れません", "承知しました、印刷しておきます"],
                "dikirimkan は kirim の受動使役。依頼に対する定型応答を選びます。",
                [.workplace], type: .responseChoice, distractorReason: .wrongContext),

        // --- C級: 実戦チェック用の追加分 ---
        singleC("Silakan menunggu, nanti akan dipanggil namanya.",
                ["名前が呼ばれるまで待つ", "名前を書いてから待つ",
                 "呼ばれたら受付へ戻る", "名前を伝えてから座る"],
                "dipanggil は panggil の受動で「呼ばれる」。akan は未来を表します。", [.hospital]),
        contentMatchC("Ada alergi obat?", "Ada, saya alergi antibiotik tertentu.",
                      ["特定の抗生物質にアレルギーがあると答えた", "薬のアレルギーは無いと答えた",
                       "食物アレルギーがあると答えた", "以前あったが今は無いと答えた"],
                      "tertentu は「特定の」。alergi の対象を聞き取ります。", [.hospital]),
        singleC("Obat ini dijual bebas tanpa resep.",
                ["この薬は処方箋なしで買える", "この薬は処方箋が必要になる",
                 "この薬は在庫切れである", "この薬は無料で配られる"],
                "dijual bebas は「市販されている」。tanpa resep は処方箋なしです。", [.pharmacy]),
        singleC("Simpan obatnya di tempat yang tidak terkena sinar matahari.",
                ["薬は直射日光の当たらない場所に保管する", "薬は日の当たる場所に置く",
                 "薬は冷凍庫で保管する", "薬は開封後すぐ捨てる"],
                "terkena は kena の ter- 形で「当たってしまう」。sinar matahari は日光です。",
                [.pharmacy], type: .grammarFunctionChoice),
        singleC("Buku tabungannya akan dicetak sekarang.",
                ["通帳は今記帳される", "通帳は後日発行される",
                 "通帳は再発行が必要になる", "通帳はもう使えない"],
                "dicetak は cetak（印刷する）の受動。buku tabungan は通帳です。", [.bank]),
        contentMatchC("Kartunya tertelan mesin ATM.", "Nanti diblokir dulu, ya.",
                      ["カードがATMに飲み込まれ、まず利用停止にすると言われた", "カードが壊れたので再発行すると言われた",
                       "カードはすぐ返却されると言われた", "暗証番号を変更すると言われた"],
                      "tertelan は telan の ter- 形で「意図せず飲み込まれる」。diblokir は「停止される」。", [.bank]),
        singleC("Nomornya akan dinonaktifkan kalau tidak diisi selama tiga bulan.",
                ["3か月チャージしないと番号が停止される", "3か月使わないと料金が上がる",
                 "3日チャージしないと番号が停止される", "3か月ごとに番号が変わる"],
                "dinonaktifkan は「無効化される」。diisi は「補充される」＝チャージです。", [.simCard]),
        singleC("Sinyalnya lemah di daerah ini.",
                ["この地域は電波が弱い", "この地域は電波が強い",
                 "この地域では通話ができない", "この地域はデータ通信が無料になる"],
                "sinyal は電波、lemah は「弱い」。daerah は地域です。", [.simCard]),
        singleC("Barangnya dibungkus ulang karena kemasannya rusak.",
                ["梱包が壊れていたので再梱包された", "商品が壊れていたので交換された",
                 "梱包が大きすぎたので分けられた", "商品は返送された"],
                "dibungkus ulang は「再び包まれる」。kemasan は梱包です。", [.delivery]),
        singleC("Ongkos kirimnya dibayar di tempat.",
                ["送料は受け取り時に払う", "送料は事前に払う",
                 "送料は無料である", "送料は差出人が払う"],
                "ongkos kirim は送料、dibayar di tempat は着払いです。", [.delivery]),
        singleC("Listriknya dibayar terpisah dari sewa.",
                ["電気代は家賃とは別に払う", "電気代は家賃に含まれる",
                 "電気代は大家が払う", "電気代は年に一度払う"],
                "terpisah は pisah の ter- 形で「分かれている」。sewa は家賃です。", [.housing]),
        singleC("Kunci cadangannya dititipkan ke penjaga.",
                ["予備の鍵は管理人に預けてある", "予備の鍵は無くなった",
                 "予備の鍵は自分で保管する", "予備の鍵は大家が持っている"],
                "cadangan は予備、dititipkan は titip の受動使役で「預けられる」。", [.housing]),
        singleC("Barang temuan bisa diambil di bagian informasi.",
                ["落とし物は案内所で受け取れる", "落とし物は警察署で受け取る",
                 "落とし物は処分された", "落とし物は郵送される"],
                "temuan は temu の名詞形で「拾得物」。diambil は「取られる＝受け取れる」。", [.police]),
        singleC("Kejadiannya harus dilaporkan dalam dua puluh empat jam.",
                ["出来事は24時間以内に届け出る必要がある", "出来事は48時間以内に届け出る",
                 "出来事の届け出は任意である", "出来事は翌週までに届け出る"],
                "kejadian は jadi の名詞形で「出来事」。dilaporkan は「報告される」。", [.police]),
        singleC("Formulirnya diisi dengan huruf kapital.",
                ["用紙は大文字で記入する", "用紙は小文字で記入する",
                 "用紙は鉛筆で記入する", "用紙は係員が記入する"],
                "diisi は isi の受動で「記入される」。huruf kapital は大文字です。", [.government]),
        singleC("Biayanya dibayarkan lewat bank, bukan di loket.",
                ["費用は窓口ではなく銀行で払う", "費用は窓口で払う",
                 "費用はオンラインでのみ払える", "費用は不要である"],
                "dibayarkan は「支払われる」。bukan で「〜ではない」を示します。", [.government]),
        singleC("Cutinya harus diajukan seminggu sebelumnya.",
                ["休暇は1週間前に申請する必要がある", "休暇は当日に申請できる",
                 "休暇は1か月前に申請する", "休暇の申請は不要である"],
                "cuti は休暇、diajukan は aju の受動使役で「提出される」。", [.workplace]),
        contentMatchC("Hasilnya sudah dikirim?", "Sudah, tadi pagi dikirimkan ke klien.",
                      ["今朝クライアントへ送付済みだと答えた", "まだ送っていないと答えた",
                       "昨夜クライアントへ送ったと答えた", "上司へ送ったと答えた"],
                      "dikirimkan は「送られる」。tadi pagi は「今朝」です。", [.workplace])
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
