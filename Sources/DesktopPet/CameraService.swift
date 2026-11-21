import AppKit
import AVFoundation

/// Owns only still-photo capture. Construction and authorization never start a
/// capture session; preview starts only while the photo composer is open.
@MainActor
final class CameraService {
    struct Device: Equatable {
        let id: String
        let name: String
    }

    nonisolated static var startupPermission: StartupPermission {
        StartupPermission(name: "Camera", reason: "Take a photo when you choose Camera in a message.",
            isGranted: { AVCaptureDevice.authorizationStatus(for: .video) == .authorized },
            request: { completion in
                guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else {
                    completion(); return
                }
                AVCaptureDevice.requestAccess(for: .video) { _ in completion() }
            })
    }

    var onPhoto: ((URL) -> Void)?
    var onError: ((String) -> Void)?
    var onStateChanged: (() -> Void)?
    private(set) var isRunning = false
    private(set) var isCapturing = false
    private(set) var selectedDeviceID: String?

    var availableDevices: [Device] {
        Self.discoverDevices().map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    private let worker = CameraCaptureWorker()
    private let directory: URL
    private var generation = UUID()
    private weak var preview: CameraPreviewView?
    private var deviceObservers: [NSObjectProtocol] = []

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WatercolorDuck/Camera", isDirectory: true)
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            deviceObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onStateChanged?() }
            })
        }
    }

    /// Preview errors are reported via onError; callers can refresh controls via
    /// onStateChanged or inspect isRunning after awaiting this method.
    func startPreview(in host: NSView, deviceID: String? = nil) async {
        stop()
        let token = UUID(); generation = token
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
                onError?("Camera access is not configured in this build. Reopen the packaged sombrero app."); return
            }
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard token == generation else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            onError?("Allow Camera for sombrero in System Settings → Privacy & Security → Camera."); return
        }
        let devices = Self.discoverDevices()
        let chosen: AVCaptureDevice?
        if let deviceID { chosen = devices.first { $0.uniqueID == deviceID } }
        else if let preferred = AVCaptureDevice.systemPreferredCamera,
                devices.contains(where: { $0.uniqueID == preferred.uniqueID }) { chosen = preferred }
        else { chosen = devices.first }
        guard let chosen, chosen.isConnected else {
            onError?(deviceID == nil ? "No camera is available. Connect a camera and try again." : "That camera is no longer available. Choose another camera."); return
        }
        selectedDeviceID = chosen.uniqueID
        let result: Result<AVCaptureSession, Error> = await withCheckedContinuation { continuation in
            worker.start(device: chosen, token: token, onFailure: { [weak self] message in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.stop(); self.onError?(message)
                }
            }) { continuation.resume(returning: $0) }
        }
        guard token == generation else { return }
        switch result {
        case .success(let session):
            let view = CameraPreviewView(session: session)
            view.frame = host.bounds; view.autoresizingMask = [.width, .height]
            host.addSubview(view); preview = view
            isRunning = true; onStateChanged?()
        case .failure(let error):
            stop(); onError?(error.localizedDescription)
        }
    }

    func capture() {
        guard isRunning, !isCapturing else { return }
        isCapturing = true; onStateChanged?()
        let token = generation
        worker.capture(token: token, directory: directory) { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                // Freeze to the retained photo, not a live stream, after a shot.
                self.stop()
                switch result {
                case .success(let url): self.onPhoto?(url)
                case .failure(let error): self.onError?(error.localizedDescription)
                }
            }
        }
    }

    func stop() {
        generation = UUID()
        preview?.removeFromSuperview(); preview = nil
        worker.stop()
        isRunning = false; isCapturing = false; selectedDeviceID = nil
        onStateChanged?()
    }

    private nonisolated static func discoverDevices() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType]
        if #available(macOS 14, *) { types = [.builtInWideAngleCamera, .external, .continuityCamera] }
        else { types = [.builtInWideAngleCamera, .externalUnknown] }
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
    }

    deinit {
        for observer in deviceObservers { NotificationCenter.default.removeObserver(observer) }
        worker.stop()
    }
}

private final class CameraPreviewView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer
    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(previewLayer)
        setAccessibilityLabel("Live camera preview")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); previewLayer.frame = bounds }
}

private enum CameraCaptureError: LocalizedError {
    case unavailable, unsupported, notReady, noPhoto
    var errorDescription: String? {
        switch self {
        case .unavailable: return "The camera could not start. Close other camera apps or choose a different camera."
        case .unsupported: return "This camera does not support still-photo capture. Choose a different camera."
        case .notReady: return "The camera is not ready. Open Camera and try again."
        case .noPhoto: return "The camera did not return a photo. Open Camera and try again."
        }
    }
}

/// All session topology, blocking start/stop calls and JPEG writes are serialized
/// off the main thread. Tokens suppress obsolete camera/sleep/close callbacks.
private final class CameraCaptureWorker {
    private let queue = DispatchQueue(label: "com.desktop-pet.camera", qos: .userInitiated)
    private var session: AVCaptureSession?
    private var output: AVCapturePhotoOutput?
    private var generation: UUID?
    private var observers: [NSObjectProtocol] = []
    private var delegates: [Int64: StillPhotoDelegate] = [:]

    func start(device: AVCaptureDevice, token: UUID, onFailure: @escaping (String) -> Void,
               completion: @escaping (Result<AVCaptureSession, Error>) -> Void) {
        queue.async { [self] in
            stopCurrent()
            generation = token
            do {
                guard device.isConnected else { throw CameraCaptureError.unavailable }
                let session = AVCaptureSession()
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCapturePhotoOutput()
                session.beginConfiguration()
                if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration(); throw CameraCaptureError.unsupported
                }
                session.addInput(input); session.addOutput(output); session.commitConfiguration()
                guard output.availablePhotoCodecTypes.contains(.jpeg) else { throw CameraCaptureError.unsupported }
                self.session = session; self.output = output
                observe(session: session, device: device, token: token, onFailure: onFailure)
                session.startRunning()
                guard session.isRunning else { throw CameraCaptureError.unavailable }
                completion(.success(session))
            } catch {
                stopCurrent(); completion(.failure(error))
            }
        }
    }

    func capture(token: UUID, directory: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async { [self] in
            guard generation == token, let session, session.isRunning, let output else {
                completion(.failure(CameraCaptureError.notReady)); return
            }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            let id = settings.uniqueID
            let delegate = StillPhotoDelegate { [weak self] result in
                guard let self else { return }
                self.queue.async {
                    self.delegates.removeValue(forKey: id)
                    guard self.generation == token else { return }
                    self.stopCurrent()
                    do {
                        let bytes = try result.get()
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                                attributes: [.posixPermissions: 0o700])
                        let file = directory.appendingPathComponent("\(UUID().uuidString).jpg")
                        try bytes.write(to: file, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                        completion(.success(file))
                    } catch { completion(.failure(error)) }
                }
            }
            delegates[id] = delegate
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }

    func stop() { queue.async { [self] in stopCurrent() } }

    private func stopCurrent() {
        generation = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        session?.stopRunning(); session = nil; output = nil
        // Keep in-flight delegates until their terminal callback, including when
        // stopRunning canceled a photo. Their old token discards any result.
    }

    private func observe(session: AVCaptureSession, device: AVCaptureDevice, token: UUID,
                         onFailure: @escaping (String) -> Void) {
        let center = NotificationCenter.default
        let events: [(Notification.Name, AnyObject, String)] = [
            (AVCaptureDevice.wasDisconnectedNotification, device, "The camera disconnected. Reconnect it or choose another camera."),
            (AVCaptureSession.runtimeErrorNotification, session, "Camera capture stopped. Open Camera again to retry."),
            (AVCaptureSession.wasInterruptedNotification, session, "The camera is busy or was interrupted. Open Camera again to retry.")
        ]
        for (name, object, message) in events {
            observers.append(center.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    guard self.generation == token else { return }
                    self.stopCurrent(); onFailure(message)
                }
            })
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        session?.stopRunning()
    }
}

private final class StillPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private var result: Result<Data, Error>?
    private let completion: (Result<Data, Error>) -> Void
    init(completion: @escaping (Result<Data, Error>) -> Void) { self.completion = completion }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { result = .failure(error) }
        else if let data = photo.fileDataRepresentation() { result = .success(data) }
        else { result = .failure(CameraCaptureError.noPhoto) }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        completion(error.map { .failure($0) } ?? result ?? .failure(CameraCaptureError.noPhoto))
    }
}
