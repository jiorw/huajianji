import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit

// MARK: - 响铃播放：循环 + 音量渐强 + 震动

@MainActor
final class RingPlayer: NSObject {
    static let shared = RingPlayer()

    private var player: AVAudioPlayer?
    private var fadeTimer: Timer?
    private var shakeTimer: Timer?
    private var targetVolume: Float = 1
    private(set) var isRinging = false

    private override init() { super.init() }

    /// 当前正在响时的实际音量读数，给界面上的音量条用
    var currentVolume: Float { player?.volume ?? targetVolume }

    func setVolume(_ value: Float) {
        targetVolume = min(max(value, 0), 1)
        player?.volume = targetVolume
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    func start(choice: SoundChoice, volume: Double, fadeInSeconds: Int, vibrate: Bool,
               loopWhileSilent: Bool) {
        stop()
        targetVolume = Float(min(max(volume, 0.05), 1))

        do {
            // .playback 让铃声绕过静音拨片；.duckOthers 让后台音乐让路
            let session = AVAudioSession.sharedInstance()
            var options: AVAudioSession.CategoryOptions = [.duckOthers, .allowBluetooth, .defaultToSpeaker]
            if !loopWhileSilent { options.insert(.mixWithOthers) }
            try session.setCategory(.playback, mode: .default, options: options)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            NSLog("响铃音频会话失败: \(error)")
        }

        guard let url = audioURL(for: choice) else {
            isRinging = true
            beginVibration(vibrate)
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.prepareToPlay()
            let startVolume = fadeInSeconds > 0 ? 0.05 : targetVolume
            player.volume = startVolume
            player.play()
            self.player = player
            if fadeInSeconds > 0 {
                let steps = max(1, fadeInSeconds * 5)
                var step = 0
                fadeTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(fadeInSeconds) / Double(steps),
                                                 repeats: true) { [weak player] timer in
                    guard let player else { timer.invalidate(); return }
                    step += 1
                    let ratio = Float(step) / Float(steps)
                    player.volume = min(self.targetVolume,
                                        startVolume + (self.targetVolume - startVolume) * ratio)
                    if step >= steps { timer.invalidate() }
                }
            }
        } catch {
            NSLog("响铃播放失败: \(error)")
        }
        isRinging = true
        beginVibration(vibrate)
    }

    func stop() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        shakeTimer?.invalidate()
        shakeTimer = nil
        player?.stop()
        player = nil
        if isRinging {
            isRinging = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func audioURL(for choice: SoundChoice) -> URL? {
        switch choice {
        case .builtIn(let file):
            return SoundCatalog.url(for: file)
        case .recording(let path, _):
            return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        case .musicLibrary(let itemID, _):
            return MusicFileExporter.cachedURL(itemId: itemID)
        case .silence:
            return nil
        }
    }

    private func beginVibration(_ enabled: Bool) {
        guard enabled else { return }
        shakeTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}

// MARK: - 从 Apple Music 库导出一份可播放的临时文件（DRM 曲目会失败）

enum MusicFileExporter {
    static func cachedURL(itemId: String) -> URL? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let file = dir?.appendingPathComponent("biqi-music-\(itemId).m4a")
        guard let file, FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }

    static func export(itemId: String, completion: @escaping (Bool) -> Void) {
        if cachedURL(itemId: itemId) != nil {
            completion(true)
            return
        }
        guard let idValue = Int64(itemId) else { completion(false); return }
        let predicate = MPMediaPropertyPredicate(value: idValue,
                                                forProperty: MPMediaItemPropertyPersistentID)
        let query = MPMediaQuery(filterPredicates: [predicate])
        guard let item = query.items?.first,
              let exporter = AVAssetExportSession(asset: item.asset,
                                                 presetName: AVAssetExportPresetAppleM4A) else {
            completion(false)
            return
        }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let dir else { completion(false); return }
        exporter.outputURL = dir.appendingPathComponent("biqi-music-\(itemId).m4a")
        exporter.outputFileType = .m4a
        exporter.exportAsynchronously {
            let ok = exporter.status == .completed
            DispatchQueue.main.async { completion(ok) }
        }
    }
}
