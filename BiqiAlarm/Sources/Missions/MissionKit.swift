import AVFoundation
import CoreImage
import CoreMotion
import ImageIO
import Photos
import Speech
import SwiftUI
import UIKit
import Vision

// MARK: - 权限

@MainActor
enum PermissionCentre {
    static func cameraStatus() -> AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }
    static func microphoneStatus() -> AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }
    static func motionStatus() -> CMAuthorizationStatus { CMPedometer.authorizationStatus() }
    static func speechStatus() -> SFSpeechRecognizerAuthorizationStatus { SFSpeechRecognizer.authorizationStatus() }

    static func ensureCamera() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    static func ensureMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    static func ensureSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async { continuation.resume(returning: status == .authorized) }
            }
        }
    }

    /// 第一次调用计步接口就是系统弹授权框的时机
    static func ensureMotion() async -> Bool {
        if CMPedometer.authorizationStatus() == .authorized { return true }
        guard CMPedometer.isStepCountingAvailable() else { return false }
        return await withCheckedContinuation { continuation in
            CMPedometer().queryPedometerData(from: Date().addingTimeInterval(-60), to: Date()) { _, error in
                DispatchQueue.main.async { continuation.resume(returning: error == nil) }
            }
        }
    }
}

// MARK: - 相机

final class CameraRunner: NSObject {
    enum Mode { case video, metadata }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "biqi.camera")
    private var photoOutput: AVCapturePhotoOutput?
    private var pendingCapture: ((CGImage?) -> Void)?
    private var useBackCamera = true

    /// 每帧回调（后台线程），用来做姿态/识别
    var onFrame: ((CGImage) -> Void)?
    /// 扫到码（后台线程）
    var onCode: ((String, String) -> Void)?
    private(set) var isReady = false

    func start(mode: Mode, backCamera: Bool = true) {
        useBackCamera = backCamera
        queue.async {
            guard !self.isReady else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = mode == .video ? .hd1280x720 : .high
            if let input = self.makeInput() { self.session.addInput(input) }

            switch mode {
            case .metadata:
                let output = AVCaptureMetadataOutput()
                if self.session.canAddOutput(output) {
                    self.session.addOutput(output)
                    output.setMetadataObjectsDelegate(self, queue: self.queue)
                    let wanted: [AVMetadataObject.ObjectType] =
                        [.qr, .microQR, .ean8, .ean13, .upce, .code128, .code39, .pdf417, .datamatrix, .aztec]
                    output.metadataObjectTypes = output.availableMetadataObjectTypes.filter { wanted.contains($0) }
                }
            case .video:
                let video = AVCaptureVideoDataOutput()
                video.alwaysDiscardsLateVideoFrames = true
                video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                if self.session.canAddOutput(video) {
                    self.session.addOutput(video)
                    video.setSampleBufferDelegate(self, queue: self.queue)
                }
                let photo = AVCapturePhotoOutput()
                if self.session.canAddOutput(photo) {
                    self.session.addOutput(photo)
                    self.photoOutput = photo
                }
            }
            self.session.commitConfiguration()
            guard !self.session.inputs.isEmpty else { return }
            self.session.startRunning()
            self.isReady = self.session.isRunning
        }
    }

    func stop() {
        queue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            self.isReady = false
        }
    }

    func captureStill(_ completion: @escaping (CGImage?) -> Void) {
        queue.async {
            guard let photo = self.photoOutput else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.pendingCapture = completion
            photo.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    private func makeInput() -> AVCaptureDeviceInput? {
        let position: AVCaptureDevice.Position = useBackCamera ? .back : .front
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return nil }
        return input
    }

    fileprivate func deliverCapture(_ image: CGImage?) {
        let handler = pendingCapture
        pendingCapture = nil
        DispatchQueue.main.async { handler?(image) }
    }
}

extension CameraRunner: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let image = SampleBufferConverter.image(from: sampleBuffer) else { return }
        onFrame?(image)
    }
}

extension CameraRunner: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let object = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              let value = object.stringValue, value.count > 1 else { return }
        onCode?(value, object.type.rawValue)
    }
}

extension CameraRunner: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            deliverCapture(nil)
            return
        }
        deliverCapture(image)
    }
}

enum SampleBufferConverter {
    static func image(from sampleBuffer: CMSampleBuffer) -> CGImage? {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        return CIContext().createCGImage(CIImage(cvPixelBuffer: buffer),
                                        from: CIImage(cvPixelBuffer: buffer).extent)
    }
}

struct CameraPreview: UIViewRepresentable {
    let runner: CameraRunner

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.attach(runner.session)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.attach(runner.session)
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        func attach(_ session: AVCaptureSession) {
            guard let layer = layer as? AVCaptureVideoPreviewLayer, layer.session !== session else { return }
            layer.videoGravity = .resizeAspectFill
            layer.session = session
        }
    }
}

// MARK: - 动作

@MainActor
final class ShakeDetector {
    private let manager = CMMotionManager()
    private var lastPeak = Date.distantPast
    private(set) var count = 0
    var onCount: ((Int) -> Void)?

    var isAvailable: Bool { manager.isAccelerometerAvailable }

    func start() {
        guard manager.isAccelerometerAvailable else { return }
        manager.accelerometerUpdateInterval = 1.0 / 30.0
        manager.startAccelerometerUpdates(to: OperationQueue.main) { [weak self] data, _ in
            guard let self, let acceleration = data?.acceleration else { return }
            guard abs(acceleration.x) + abs(acceleration.y) + abs(acceleration.z) > 2.4 else { return }
            guard Date().timeIntervalSince(self.lastPeak) > 0.4 else { return }
            self.lastPeak = Date()
            self.count += 1
            self.onCount?(self.count)
        }
    }

    func stop() { manager.stopAccelerometerUpdates() }
}

@MainActor
final class StepTracker {
    private let pedometer = CMPedometer()
    private(set) var steps = 0
    var onSteps: ((Int) -> Void)?

    var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    func start() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let self, let data else { return }
            self.steps = data.numberOfSteps.intValue
            self.onSteps?(self.steps)
        }
    }

    func stop() { pedometer.stopUpdates() }
}

// MARK: - 图像相似度（感知哈希）

enum ImageHasher {
    /// 0...1，越大越像；真人实测 0.82 以上基本就是同一场景
    static func similarity(_ left: CGImage, _ right: CGImage) -> Double {
        let a = descriptor(of: left), b = descriptor(of: right)
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var hits = 0
        for (x, y) in zip(a, b) where x == y { hits += 1 }
        return Double(hits) / Double(a.count)
    }

    static func descriptor(of image: CGImage, size: Int = 9) -> [Bool] {
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [] }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let pointer = context.data else { return [] }
        let bytes = UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self),
                                        count: size * size)
        var flags: [Bool] = []
        for row in 0..<size {
            for column in 0..<(size - 1) {
                flags.append(bytes[row * size + column] > bytes[row * size + column + 1])
            }
        }
        return flags
    }

    static func jpegData(_ image: CGImage, quality: CGFloat = 0.7) -> Data? {
        let sink = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(sink, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return sink as Data
    }
}

// MARK: - Vision

enum VisionLab {
    static func classify(_ image: CGImage, completion: @escaping ([String: Double]) -> Void) {
        let request = VNClassifyImageRequest()
        perform(request, on: image) {
            var scores: [String: Double] = [:]
            for observation in request.results ?? [] {
                scores[observation.identifier.lowercased()] = Double(observation.confidence)
            }
            completion(scores)
        }
    }

    static func bodyPose(_ image: CGImage, completion: @escaping (BodyPose?) -> Void) {
        let request = VNDetectHumanBodyPoseRequest()
        perform(request, on: image) {
            completion(BodyPose(of: request.results?.first))
        }
    }

    private static func perform(_ request: VNImageRequest, on image: CGImage,
                                then body: @escaping () -> Void) {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
                DispatchQueue.main.async { body() }
            } catch {
                NSLog("Vision 失败: \(error)")
                DispatchQueue.main.async { body() }
            }
        }
    }
}

/// Vision 的归一化坐标原点在左下角：站着时髋比膝高很多，蹲下时靠拢
struct BodyPose {
    let hipToKnee: Double
    let torso: Double

    init?(_ observation: VNHumanBodyPoseObservation?) {
        guard let observation else { return nil }
        func point(_ name: VNHumanBodyPoseObservation.JointsName) -> CGPoint? {
            guard let value = try? observation.recognizedPoint(name), value.confidence > 0.25
            else { return nil }
            return CGPoint(x: value.location.x, y: value.location.y)
        }
        let hip = point(.hipCenter) ?? point(.leftHip) ?? point(.rightHip)
        let knee = point(.kneeCenter) ?? point(.leftKnee) ?? point(.rightKnee)
        let neck = point(.neckCenter) ?? point(.leftShoulder) ?? point(.rightShoulder)
        guard let hip, let knee, let neck, neck.y > hip.y else { return nil }
        torso = max(0.08, neck.y - hip.y)
        hipToKnee = max(0, hip.y - knee.y)
    }

    var isSquatting: Bool { hipToKnee < torso * 0.52 }
}

// MARK: - 中文目标 → Vision 标签

enum VisionLabelMap {
    static let pairs: [(String, [String])] = [
        ("牙刷", ["toothbrush", "brush"]),
        ("杯子", ["cup", "mug", "glass", "drink"]),
        ("床", ["bed", "pillow", "bedroom"]),
        ("枕头", ["pillow", "bed", "cushion"]),
        ("鞋", ["shoe", "sneaker", "boot", "loafer"]),
        ("电脑", ["laptop", "desktop", "computer", "monitor", "keyboard"]),
        ("手机", ["cell phone", "mobile phone", "iphone"]),
        ("桌子", ["table", "desk", "counter", "dining table"]),
        ("椅子", ["chair", "armchair", "stool"]),
        ("水槽", ["sink", "basin", "lavatory"]),
        ("马桶", ["toilet", "water closet"]),
        ("毛巾", ["towel", "bath towel", "washcloth"]),
        ("镜子", ["mirror"]),
        ("门", ["door", "bedroom door", "sliding door", "glass door"]),
        ("冰箱", ["refrigerator", "icebox"]),
        ("书", ["book", "book jacket", "notebook"]),
        ("钥匙", ["key"]),
        ("钱包", ["wallet", "billfold", "purse"]),
        ("眼镜", ["sunglasses", "glasses", "eyeglass"]),
        ("猫", ["cat", "kitten", "tabby"]),
        ("狗", ["dog", "puppy", "retriever"]),
        ("食物", ["food", "produce", "vegetable", "fruit", "dish"]),
        ("面包", ["bread", "loaf", "baguette", "toast"]),
        ("药", ["pill", "medicine", "packet"]),
        ("洗衣机", ["washing machine", "automatic washer"]),
        ("灯", ["lamp", "desk lamp", "floor lamp"]),
        ("钟", ["clock", "wall clock", "digital clock", "analog clock"]),
        ("吉他", ["guitar", "acoustic guitar"]),
        ("球", ["ball", "sports ball", "basketball", "football"]),
        ("伞", ["umbrella", "parasol"]),
        ("花", ["flower", "bouquet", "rose"]),
        ("树", ["tree", "elm", "oak"]),
        ("车", ["car", "automobile", "sedan", "sports car"]),
        ("人", ["person", "man", "woman", "boy", "girl"])
    ]

    static var titles: [String] { pairs.map(\.0) }

    static func matches(target: String, scores: [String: Double], threshold: Double = 0.1) -> Bool {
        let keys = keywords(for: target)
        for (label, confidence) in scores where confidence >= threshold {
            if keys.contains(where: { key in label.contains(key) || key.contains(label) }) { return true }
        }
        return false
    }

    static func keywords(for target: String) -> [String] {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let hit = pairs.first(where: { trimmed.contains($0.0) || $0.0.contains(trimmed) }) {
            return hit.1
        }
        return trimmed.isEmpty ? [] : [trimmed]
    }
}
