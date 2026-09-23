import Foundation

// MARK: - 内置铃声清单（对齐原版 catalog 的分组结构，全部免费）

struct BuiltInSound: Identifiable, Hashable {
    let file: String        // bundle 里的 wav 文件名（不含扩展名）
    let title: String
    let note: String
    var id: String { file }
}

enum SoundCatalog {
    static let classic: [BuiltInSound] = [
        BuiltInSound(file: "DigitalAlarm", title: "数字闹铃", note: "经典电子钟的滴滴声"),
        BuiltInSound(file: "Classic", title: "老式铃铛", note: "机械打铃"),
        BuiltInSound(file: "Bell", title: "金属铃", note: "带泛音的一次敲铃"),
        BuiltInSound(file: "Beep", title: "蜂鸣", note: "短促蜂鸣循环")
    ]

    static let loud: [BuiltInSound] = [
        BuiltInSound(file: "Siren", title: "警笛", note: "来回扫频，最容易被叫醒"),
        BuiltInSound(file: "LoudPulse", title: "重低音冲击", note: "低频一下一下顶"),
        BuiltInSound(file: "Glock", title: "钟琴急奏", note: "四个音来回敲")
    ]

    static let gentle: [BuiltInSound] = [
        BuiltInSound(file: "Chime", title: "清晨鸟笛", note: "上行琶音，温和")
    ]

    static var all: [BuiltInSound] { classic + loud + gentle }

    static func sound(named file: String) -> BuiltInSound? {
        all.first { $0.file == file }
    }

    static func url(for file: String) -> URL? {
        Bundle.main.url(forResource: file, withExtension: "wav")
    }

    /// 通知能用的铃声文件名（系统限制：bundle 内、30 秒以内）
    static func notificationSoundName(for choice: SoundChoice) -> String? {
        switch choice {
        case .builtIn(let file): return url(for: file) == nil ? nil : file + ".wav"
        case .musicLibrary, .recording, .silence: return nil
        }
    }
}

// MARK: - 铃声展示条目（内置 + 自制录音 + 音乐库）

struct RingtoneItem: Identifiable, Hashable {
    enum Kind: Hashable { case builtIn, recording, music }
    let id: String
    let kind: Kind
    let title: String
    let note: String
    let choice: SoundChoice
}

enum RingtoneLibrary {
    static var builtInItems: [RingtoneItem] {
        SoundCatalog.all.map {
            RingtoneItem(id: "bi-" + $0.file, kind: .builtIn, title: $0.title, note: $0.note,
                         choice: .builtIn($0.file))
        }
    }

    /// 用户自己录的铃声，存在 Documents/Ringtones
    static var recordings: [RingtoneItem] {
        let dir = recordingDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                      includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { ["m4a", "caf", "wav", "aiff"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map {
                let name = $0.deletingPathExtension().lastPathComponent
                return RingtoneItem(id: "rec-" + name, kind: .recording,
                                    title: name, note: "我的录音",
                                    choice: .recording(url: $0.path, title: name))
            }
    }

    static let recordingDirectory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Ringtones", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}
