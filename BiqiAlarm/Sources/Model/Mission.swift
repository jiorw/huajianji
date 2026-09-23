import Foundation

// MARK: - 使命类型（对齐原版 12 种解锁任务，全部免费开放）

enum MissionKind: String, Codable, CaseIterable, Identifiable {
    case photo          // 拍一张照片（可与参考图比对）
    case recognize      // 拍到指定类别的物体（图像识别）
    case barcode        // 扫二维码 / 条形码
    case math           // 数学题
    case memory         // 记忆翻牌
    case symbol         // 找出独特符号
    case shake          // 摇一摇
    case walk           // 走路计步
    case squat          // 深蹲计数
    case tap            // 点击挑战
    case typing         // 打字
    case wordbeat       // 朗读句子

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "拍照"
        case .recognize: return "识别拍照"
        case .barcode: return "扫码"
        case .math: return "数学题"
        case .memory: return "记忆翻牌"
        case .symbol: return "找不同"
        case .shake: return "摇一摇"
        case .walk: return "走够步数"
        case .squat: return "深蹲"
        case .tap: return "点击挑战"
        case .typing: return "打字"
        case .wordbeat: return "朗读"
        }
    }

    var subtitle: String {
        switch self {
        case .photo: return "拍一张照才能关，可要求与参考图相似"
        case .recognize: return "拍到指定的东西，比如牙刷、水槽、鞋"
        case .barcode: return "扫到你设定的那个码才算数"
        case .math: return "算对题，难度和题数自己定"
        case .memory: return "记住图案位置，配对成功才放行"
        case .symbol: return "在一堆符号里找出不一样的那个"
        case .shake: return "拿起手机摇够次数"
        case .walk: return "下床走到步数够为止"
        case .squat: return "用前置镜头数你做了几个深蹲"
        case .tap: return "在限定区域点够次数"
        case .typing: return "把句子一字不差打出来"
        case .wordbeat: return "对着手机把句子读出来"
        }
    }

    var icon: String {
        switch self {
        case .photo: return "camera.fill"
        case .recognize: return "brain.head.profile"
        case .barcode: return "qrcode.viewfinder"
        case .math: return "function"
        case .memory: return "rectangle.grid.3x3.fill"
        case .symbol: return "circle.dotted"
        case .shake: return "iphone.genesis"
        case .walk: return "figure.walk"
        case .squat: return "figure.fitstime.fill"
        case .tap: return "hand.tap.fill"
        case .typing: return "keyboard.fill"
        case .wordbeat: return "mic.fill"
        }
    }

    /// 需要哪些系统权限，用来在设置页和解锁页提示
    var permissions: [String] {
        switch self {
        case .photo, .recognize, .barcode, .squat: return ["相机"]
        case .wordbeat: return ["麦克风", "语音识别"]
        case .typing: return []
        case .shake, .walk, .squat: return ["运动与健身"]
        case .math, .memory, .symbol, .tap: return []
        }
    }

    var needsCamera: Bool {
        switch self {
        case .photo, .recognize, .barcode, .squat: return true
        default: return false
        }
    }

    var needsMotion: Bool {
        switch self {
        case .shake, .walk: return true
        default: return false
        }
    }
}

// MARK: - 单条使命的配置

struct MissionConfig: Codable, Hashable, Identifiable {
    var kind: MissionKind = .math
    var rounds: Int = 1            // 连做几轮
    var difficulty: Int = 2        // 1...5
    var targetCount: Int = 30      // 摇/步/蹲/点的数量，数学题的题数
    var phrase: String = ""        // 打字 / 朗读的句子
    var barcodeValue: String = ""  // 扫码目标
    var preferQR: Bool = true      // 扫码时优先二维码还是条形容
    var referenceName: String = "" // 识别拍照的目标类别名
    var referenceImage: Data? = nil  // 拍照比对用的参考图

    var id: UUID = UUID()

    var summary: String {
        switch kind {
        case .photo:
            return referenceImage == nil ? "随便拍一张" : "拍得像「\(referenceName.isEmpty ? "参考图" : referenceName)」"
        case .recognize:
            return "拍到\(referenceName.isEmpty ? "指定物体" : "「\(referenceName)」")"
        case .barcode:
            return barcodeValue.isEmpty ? "扫任意码" : "扫出 \(barcodeValue)"
        case .math:
            return "\(targetCount) 题 · \(Self.difficultyName(difficulty))"
        case .memory:
            return "\(memoryRows)×\(memoryCols) 格 · \(rounds) 轮"
        case .symbol:
            return "\(rounds) 轮 · \(Self.difficultyName(difficulty))"
        case .shake:
            return "摇 \(targetCount) 次"
        case .walk:
            return "走 \(targetCount) 步"
        case .squat:
            return "做 \(targetCount) 个"
        case .tap:
            return "点 \(targetCount) 次 · \(Self.difficultyName(difficulty))"
        case .typing:
            return phrase.isEmpty ? "默认短句" : "「\(phrase)」"
        case .wordbeat:
            return phrase.isEmpty ? "默认句子" : "「\(phrase)」"
        }
    }

    var memoryRows: Int { 2 + max(0, difficulty - 1) / 2 }
    var memoryCols: Int { 3 + (difficulty - 1) / 2 }

    static func difficultyName(_ value: Int) -> String {
        ["最简单", "简单", "普通", "困难", "地狱"][min(max(value - 1, 0), 4)]
    }

    static func `default`(_ kind: MissionKind) -> MissionConfig {
        var config = MissionConfig(kind: kind)
        switch kind {
        case .math:
            config.targetCount = 3
            config.difficulty = 2
        case .memory:
            config.rounds = 1
            config.difficulty = 2
        case .symbol:
            config.rounds = 2
            config.difficulty = 2
        case .shake:
            config.targetCount = 30
        case .walk:
            config.targetCount = 60
        case .squat:
            config.targetCount = 10
        case .tap:
            config.targetCount = 50
            config.difficulty = 3
        case .typing:
            config.phrase = ""
        case .wordbeat:
            config.phrase = ""
        case .recognize:
            config.referenceName = "牙刷"
        case .barcode:
            config.preferQR = true
        case .photo:
            break
        }
        return config
    }
}

// MARK: - 句子库（打字 / 朗读）

enum PhraseBook {
    static let morning = [
        "早上好，今天也是可以用来改变的一天",
        "我起床，因为我答应过自己要去看更远的地方",
        "先把今天的第一件事做完，再想剩下的",
        "起床不是惩罚，是给自己一次机会"
    ]

    static let love = [
        "我很健康，我很努力，我爱我自己",
        "谢谢昨晚没有放弃的那个我",
        "今天也要好好吃饭，好好睡觉",
        "我可以慢，但我不会停"
    ]

    static let study = [
        "今天的努力是为了以后有得选",
        "把书读薄，把人做厚",
        "慢就是快，少就是多",
        "重复是记忆之母，行动是信心之父"
    ]

    static let short = [
        "必起",
        "起床了",
        "我可以",
        "向前走"
    ]

    static func random(from pool: [String], excluding: String = "") -> String {
        let candidates = pool.filter { $0 != excluding }
        return candidates.randomElement() ?? pool[0]
    }
}
