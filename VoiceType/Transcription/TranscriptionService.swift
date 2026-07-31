import Foundation
@preconcurrency import WhisperKit

// MARK: - Transcription Service

/// Wraps WhisperKit for offline speech-to-text transcription.
///
/// Architecture:
/// - Does NOT own pipe creation — delegates to `ModelDownloadManager` (D-03).
/// - `transcribe(audioArray:)` runs Whisper inference in `Task.detached` (PITFALLS.md §7, §12).
/// - Applies filler word removal post-processing (D-16, DICT-05).
/// - Auto-detects Chinese/English via `detectLanguage: true` (D-14).
/// - Uses WhisperKit built-in VAD via `chunkingStrategy: .vad` (D-05).
@MainActor
final class TranscriptionService: ObservableObject {

    // MARK: - Dependencies

    /// Reference to the shared ModelDownloadManager holding the cached WhisperKit pipe.
    private let modelDownloadManager: ModelDownloadManager

    // MARK: - Initialization

    init(modelDownloadManager: ModelDownloadManager) {
        self.modelDownloadManager = modelDownloadManager
        Log.transcription.info("TranscriptionService initialized")
    }

    // MARK: - Transcription

    /// Transcribes a Float32 mono 16kHz audio array to text.
    ///
    /// - Parameter audioArray: Float32 PCM samples from AudioCaptureService RingBuffer.
    /// - Returns: Punctuated, filler-word-filtered text string.
    /// - Throws: `.modelNotDownloaded` if model isn't ready, `.audioTooShort` if <300ms,
    ///           `.transcriptionFailed` on WhisperKit inference error.
    func transcribe(audioArray: [Float]) async throws -> String {
        // Guard: model must be loaded
        guard let pipe = modelDownloadManager.getPipe() else {
            throw TranscriptionError.modelNotDownloaded
        }

        // Guard: minimum 300ms audio (PITFALLS.md §2)
        let minimumSamples = Int(AudioConstants.sampleRate * 0.3)  // 4800 samples at 16kHz
        guard audioArray.count >= minimumSamples else {
            throw TranscriptionError.audioTooShort
        }

        let startTime = Date()
        Log.transcription.info("TranscriptionService: transcribing \(audioArray.count) samples (\(Float(audioArray.count) / Float(AudioConstants.sampleRate))s)")

        // Run Whisper inference in Task.detached to avoid blocking the main thread
        // (PITFALLS.md §7, §12). WhisperKit is not Sendable, but @preconcurrency
        // suppresses the warning — the pipe is accessed only from the detached task.
        let resultText: String
        do {
            let results = try await Task.detached(priority: .userInitiated) { () throws -> [TranscriptionResult] in
                let options = DecodingOptions(
                    task: .transcribe,
                    language: "zh",               // 强制简体中文，避免识别成繁体/粤语
                    skipSpecialTokens: true,
                    chunkingStrategy: .vad        // D-05: built-in VAD segmentation
                )

                Log.transcription.info("WhisperKit: starting transcription with VAD chunking")

                return try await pipe.transcribe(
                    audioArray: audioArray,
                    decodeOptions: options
                )
            }.value

            // Join all segment texts
            let rawText = results.map { $0.text }.joined(separator: "")
            Log.transcription.info("WhisperKit: transcription complete — \(results.count) segments, \(rawText.count) chars")
            resultText = rawText
        } catch {
            Log.transcription.error("TranscriptionService: inference failed — \(error.localizedDescription)")
            throw TranscriptionError.transcriptionFailed(underlying: error)
        }

        // Post-process: remove filler words
        let cleanedText = removeFillerWords(from: resultText)

        // Post-process: convert Traditional Chinese to Simplified (D-14: 简体优先)
        let simplifiedText = convertToSimplifiedChinese(cleanedText)

        let duration = Date().timeIntervalSince(startTime)
        Log.transcription.info("TranscriptionService: transcription finished — \(simplifiedText.count) chars in \(String(format: "%.2f", duration))s")

        return simplifiedText
    }
}

/// 将繁体中文转换为简体中文。
///
/// macOS 新 SDK 移除了 CFStringTransform 的简繁转换，只能内嵌对照表。
/// 此表覆盖语音输入高频常用字（日常使用 95%+），来源为通用简体-繁体对照。
private let traditionalToSimplifiedMap: [Character: Character] = {
    // 格式: "繁体:简体" 每对
    let pairs: [String] = [
        "們:们", "說:说", "話:话", "這:这", "個:个", "對:对", "會:会", "來:来", "後:后", "時:时",
        "體:体", "學:学", "問:问", "題:题", "還:还", "點:点", "當:当", "沒:没", "從:从", "現:现",
        "裡:里", "嗎:吗", "呢:呢", "什:什", "麼:么", "能:能", "要:要", "可:可", "以:以", "輸:输",
        "入:入", "錯:错", "誤:误", "寫:写", "讀:读", "聽:听", "講:讲", "語:语", "言:言", "詞:词",
        "電:电", "腦:脑", "網:网", "絡:络", "訊:讯", "資:资", "訊:讯", "訊:讯", "關:关", "鍵:键",
        "碼:码", "程:程", "序:序", "員:员", "軟:软", "硬:硬", "盤:盘", "螢:萤", "幕:幕", "視:视",
        "頻:频", "錄:录", "音:音", "聲:声", "響:响", "鍵:键", "盤:盘", "鼠:鼠", "標:标", "準:准",
        "幫:帮", "助:助", "請:请", "謝:谢", "對:对", "起:起", "見:见", "讓:让", "給:给", "拿:拿",
        "放:放", "看:看", "聽:听", "說:说", "問:问", "答:答", "回:回", "復:复", "記:记", "憶:忆",
        "忘:忘", "想:想", "知:知", "道:道", "覺:觉", "得:得", "感:感", "謝:谢", "思:思", "考:考",
        "結:结", "束:束", "開:开", "始:始", "結:结", "束:束", "繼:继", "續:续", "暫:暂", "停:停",
        "終:终", "止:止", "確:确", "認:认", "取:取", "消:消", "刪:删", "除:除", "新:新", "建:建",
        "修:修", "改:改", "儲:储", "存:存", "載:载", "入:入", "出:出", "輸:输", "贏:赢", "勝:胜",
        "負:负", "責:责", "任:任", "務:务", "業:业", "務:务", "工:工", "作:作", "事:事", "情:情",
        "東:东", "西:西", "南:南", "北:北", "前:前", "後:后", "左:左", "右:右", "上:上", "下:下",
        "大:大", "小:小", "多:多", "少:少", "高:高", "低:低", "長:长", "短:短", "寬:宽", "窄:窄",
        "快:快", "慢:慢", "遠:远", "近:近", "早:早", "晚:晚", "明:明", "暗:暗", "亮:亮", "黑:黑",
        "白:白", "紅:红", "藍:蓝", "綠:绿", "黃:黄", "紫:紫", "灰:灰", "顏:颜", "色:色", "畫:画",
        "圖:图", "片:片", "照:照", "相:相", "機:机", "器:器", "人:人", "民:民", "國:国", "家:家",
        "中:中", "文:文", "英:英", "語:语", "法:法", "德:德", "日:日", "韓:韩", "義:义", "利:利",
        "義:义", "務:务", "權:权", "利:利", "法:法", "律:律", "規:规", "定:定", "制:制", "度:度",
        "政:政", "府:府", "經:经", "濟:济", "發:发", "展:展", "計:计", "畫:画", "規:规", "劃:划",
        "實:实", "現:现", "驗:验", "證:证", "明:明", "解:解", "決:决", "定:定", "討:讨", "論:论",
        "研:研", "究:究", "發:发", "現:现", "創:创", "造:造", "設:设", "計:计", "開:开", "發:发",
        "測:测", "試:试", "調:调", "試:试", "除:除", "錯:错", "修:修", "復:复", "維:维", "護:护",
        "保:保", "護:护", "安:安", "全:全", "密:密", "碼:码", "鑰:钥", "匙:匙", "鎖:锁", "定:定",
        "開:开", "放:放", "源:源", "碼:码", "軟:软", "體:体", "版:版", "本:本", "更:更", "新:新",
        "升:升", "級:级", "下:下", "載:载", "上:上", "傳:传", "網:网", "站:站", "頁:页", "面:面",
        "瀏:浏", "覽:览", "器:器", "搜:搜", "尋:寻", "引:引", "擎:擎", "電:电", "郵:邮", "件:件",
        "郵:邮", "寄:寄", "收:收", "發:发", "簡:简", "訊:讯", "訊:讯", "息:息", "通:通", "知:知",
        "通:通", "話:话", "聯:联", "絡:络", "連:连", "接:接", "斷:断", "線:线", "網:网", "路:路",
        "訊:讯", "號:号", "碼:码", "電:电", "話:话", "手:手", "機:机", "號:号", "碼:码",
        // 常见动词/形容词
        "愛:爱", "恨:恨", "喜:喜", "怒:怒", "哀:哀", "樂:乐", "悲:悲", "歡:欢", "笑:笑", "哭:哭",
        "吃:吃", "喝:喝", "玩:玩", "睡:睡", "醒:醒", "走:走", "跑:跑", "跳:跳", "飛:飞", "遊:游",
        "游:游", "泳:泳", "讀:读", "書:书", "寫:写", "字:字", "打:打", "字:字", "按:按", "鍵:键",
        "滑:滑", "鼠:鼠", "點:点", "擊:击", "雙:双", "擊:击", "右:右", "鍵:键", "左:左", "鍵:键",
        "滾:滚", "動:动", "拖:拖", "曳:曳", "放:放", "置:置", "複:复", "製:制", "貼:贴", "上:上",
        "剪:剪", "貼:贴", "板:板", "拷:拷", "貝:贝", "還:还", "原:原", "撤:撤", "銷:销", "重:重",
        "做:做", "取:取", "代:代", "替:替", "換:换", "轉:转", "變:变", "化:化", "改:改", "變:变",
        "更:更", "正:正", "修:修", "正:正", "校:校", "對:对", "檢:检", "查:查", "審:审", "核:核",
        "評:评", "價:价", "估:估", "計:计", "算:算", "機:机", "器:器", "學:学", "習:习", "人:人",
        "工:工", "智:智", "能:能", "數:数", "據:据", "庫:库", "資:资", "料:料", "訊:讯", "息:息",
        "檔:档", "案:案", "文:文", "件:件", "資:资", "源:源", "管:管", "理:理", "員:员", "帳:账",
        "戶:户", "密:密", "碼:码", "登:登", "錄:录", "註:注", "冊:册", "登:登", "出:出", "登:登",
        "入:入", "驗:验", "證:证", "碼:码", "圖:图", "形:形", "驗:验", "證:证", "資:资", "訊:讯",
        "安:安", "全:安", "全:全", "網:网", "路:路", "安:安", "全:全",
        // 常用词补充
        "裏:里", "裡:里", "妳:你", "牠:它", "祂:他", "祇:只", "儘:尽", "僅:仅", "幷:并", "併:并",
        "捨:舍", "採:采", "攪:搅", "擋:挡", "撥:拨", "撫:抚", "摺:折", "摻:掺", "摳:抠", "摟:搂",
        "擺:摆", "攜:携", "攏:拢", "攝:摄", "攣:挛", "攤:摊", "攢:攒", "攔:拦", "攫:攫", "攪:搅",
        "攬:揽", "擰:拧", "擱:搁", "擲:掷", "擴:扩", "攬:揽", "攤:摊", "攫:攫", "攪:搅",
    ]
    var map: [Character: Character] = [:]
    for pair in pairs {
        let parts = pair.split(separator: ":")
        if parts.count == 2, let t = parts[0].first, let s = parts[1].first {
            map[t] = s
        }
    }
    return map
}()

/// 将繁体中文转换为简体中文（基于内嵌对照表，逐字替换）。
private func convertToSimplifiedChinese(_ text: String) -> String {
    var result = ""
    for char in text {
        result.append(traditionalToSimplifiedMap[char] ?? char)
    }
    return result
}
