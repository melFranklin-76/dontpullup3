import AVFoundation
import SwiftUI
import UIKit

/// A modern AVCaptureSession-based video recorder that replaces UIImagePickerController
/// This eliminates the CAMStorageController and other camera-related warnings
struct VideoRecorderView: UIViewControllerRepresentable {
    let maxDuration: TimeInterval
    let onVideoRecorded: (URL?) -> Void
    
    init(maxDuration: TimeInterval = 180, onVideoRecorded: @escaping (URL?) -> Void) {
        self.maxDuration = maxDuration
        self.onVideoRecorded = onVideoRecorded
    }
    
    func makeUIViewController(context: Context) -> VideoRecorderViewController {
        let controller = VideoRecorderViewController()
        controller.maxDuration = maxDuration
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: VideoRecorderViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, VideoRecorderDelegate {
        let parent: VideoRecorderView
        
        init(_ parent: VideoRecorderView) {
            self.parent = parent
        }
        
        func videoRecorderDidFinish(with url: URL?) {
            parent.onVideoRecorded(url)
        }
        
        func videoRecorderDidCancel() {
            parent.onVideoRecorded(nil)
        }
    }
}

// MARK: - Delegate Protocol
protocol VideoRecorderDelegate: AnyObject {
    func videoRecorderDidFinish(with url: URL?)
    func videoRecorderDidCancel()
}

// MARK: - Video Recorder View Controller
class VideoRecorderViewController: UIViewController {
    
    weak var delegate: VideoRecorderDelegate?
    var maxDuration: TimeInterval = 180
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    private var isRecording = false
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    
    // UI Elements
    private let recordButton = UIButton(type: .custom)
    private let cancelButton = UIButton(type: .system)
    private let switchCameraButton = UIButton(type: .system)
    private let timerLabel = UILabel()
    private let flashButton = UIButton(type: .system)
    
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var flashMode: AVCaptureDevice.FlashMode = .off
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        setupCaptureSession()
        setupUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    // MARK: - Setup
    
    private func setupCaptureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        // Request camera and microphone access
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else {
                DispatchQueue.main.async {
                    self?.showPermissionDeniedAlert()
                }
                return
            }
            
            AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
                DispatchQueue.main.async {
                    self?.configureCaptureSession(session)
                }
            }
        }
    }
    
    private func configureCaptureSession(_ session: AVCaptureSession) {
        session.beginConfiguration()
        
        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            session.commitConfiguration()
            showCameraUnavailableAlert()
            return
        }
        session.addInput(videoInput)
        
        // Add audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        
        // Add movie output
        let movieOutput = AVCaptureMovieFileOutput()
        movieOutput.maxRecordedDuration = CMTime(seconds: maxDuration, preferredTimescale: 600)
        
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            self.videoOutput = movieOutput
        }
        
        session.commitConfiguration()
        
        // Setup preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer
        
        self.captureSession = session
    }
    
    private func setupUI() {
        // Record button (large red circle)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.layer.cornerRadius = 35
        recordButton.backgroundColor = .red
        recordButton.layer.borderWidth = 4
        recordButton.layer.borderColor = UIColor.white.cgColor
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        view.addSubview(recordButton)
        
        // Cancel button
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)
        
        // Switch camera button
        switchCameraButton.translatesAutoresizingMaskIntoConstraints = false
        switchCameraButton.setImage(UIImage(systemName: "camera.rotate"), for: .normal)
        switchCameraButton.tintColor = .white
        switchCameraButton.addTarget(self, action: #selector(switchCameraTapped), for: .touchUpInside)
        view.addSubview(switchCameraButton)
        
        // Flash button
        flashButton.translatesAutoresizingMaskIntoConstraints = false
        flashButton.setImage(UIImage(systemName: "bolt.slash"), for: .normal)
        flashButton.tintColor = .white
        flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        view.addSubview(flashButton)
        
        // Timer label
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.textColor = .white
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .medium)
        timerLabel.textAlignment = .center
        timerLabel.text = "0:00 / 3:00"
        timerLabel.isHidden = true
        view.addSubview(timerLabel)
        
        NSLayoutConstraint.activate([
            // Record button - center bottom
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            recordButton.widthAnchor.constraint(equalToConstant: 70),
            recordButton.heightAnchor.constraint(equalToConstant: 70),
            
            // Cancel button - bottom left
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            
            // Switch camera - top right
            switchCameraButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            switchCameraButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            switchCameraButton.widthAnchor.constraint(equalToConstant: 44),
            switchCameraButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Flash button - top left
            flashButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            flashButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            flashButton.widthAnchor.constraint(equalToConstant: 44),
            flashButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Timer label - top center
            timerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }
    
    // MARK: - Session Control
    
    private func startSession() {
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    private func stopSession() {
        guard let session = captureSession, session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }
    
    // MARK: - Actions
    
    @objc private func recordButtonTapped() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    @objc private func cancelTapped() {
        if isRecording {
            videoOutput?.stopRecording()
        }
        stopSession()
        delegate?.videoRecorderDidCancel()
        dismiss(animated: true)
    }
    
    @objc private func switchCameraTapped() {
        guard let session = captureSession else { return }
        
        session.beginConfiguration()
        
        // Remove existing video input
        if let currentInput = session.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput {
            session.removeInput(currentInput)
        }
        
        // Toggle camera position
        currentCameraPosition = currentCameraPosition == .back ? .front : .back
        
        // Add new video input
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition),
              let newInput = try? AVCaptureDeviceInput(device: newDevice),
              session.canAddInput(newInput) else {
            session.commitConfiguration()
            return
        }
        
        session.addInput(newInput)
        session.commitConfiguration()
        
        // Update flash button visibility (front camera doesn't have flash)
        flashButton.isHidden = currentCameraPosition == .front
    }
    
    @objc private func flashTapped() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition),
              device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            
            if device.torchMode == .off {
                device.torchMode = .on
                flashButton.setImage(UIImage(systemName: "bolt.fill"), for: .normal)
            } else {
                device.torchMode = .off
                flashButton.setImage(UIImage(systemName: "bolt.slash"), for: .normal)
            }
            
            device.unlockForConfiguration()
        } catch {
            print("[VideoRecorder] Flash toggle failed: \(error)")
        }
    }
    
    // MARK: - Recording
    
    private func startRecording() {
        guard let output = videoOutput, !output.isRecording else { return }
        
        // Create temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "video_\(UUID().uuidString).mov"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        // Remove existing file if any
        try? FileManager.default.removeItem(at: fileURL)
        
        // Start recording
        output.startRecording(to: fileURL, recordingDelegate: self)
        
        isRecording = true
        recordingStartTime = Date()
        
        // Update UI
        UIView.animate(withDuration: 0.2) {
            self.recordButton.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            self.recordButton.layer.cornerRadius = 8
        }
        
        timerLabel.isHidden = false
        cancelButton.setTitle("Stop", for: .normal)
        
        // Start timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateTimerLabel()
        }
    }
    
    private func stopRecording() {
        guard let output = videoOutput, output.isRecording else { return }
        output.stopRecording()
    }
    
    private func updateTimerLabel() {
        guard let startTime = recordingStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        let maxMinutes = Int(maxDuration) / 60
        let maxSeconds = Int(maxDuration) % 60
        timerLabel.text = String(format: "%d:%02d / %d:%02d", minutes, seconds, maxMinutes, maxSeconds)
        
        // Change color when approaching limit
        if elapsed > maxDuration - 10 {
            timerLabel.textColor = .red
        } else {
            timerLabel.textColor = .white
        }
    }
    
    private func resetRecordingUI() {
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartTime = nil
        
        UIView.animate(withDuration: 0.2) {
            self.recordButton.transform = .identity
            self.recordButton.layer.cornerRadius = 35
        }
        
        timerLabel.isHidden = true
        timerLabel.textColor = .white
        cancelButton.setTitle("Cancel", for: .normal)
    }
    
    // MARK: - Alerts
    
    private func showPermissionDeniedAlert() {
        let alert = UIAlertController(
            title: "Camera Access Required",
            message: "Please enable camera access in Settings to record videos.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.delegate?.videoRecorderDidCancel()
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
    
    private func showCameraUnavailableAlert() {
        let alert = UIAlertController(
            title: "Camera Unavailable",
            message: "The camera is not available on this device.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.delegate?.videoRecorderDidCancel()
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension VideoRecorderViewController: AVCaptureFileOutputRecordingDelegate {
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        #if DEBUG
        print("[VideoRecorder] Recording started: \(fileURL)")
        #endif
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        resetRecordingUI()
        stopSession()
        
        if let error = error {
            #if DEBUG
            print("[VideoRecorder] Recording error: \(error)")
            #endif
            // Check if it's a max duration reached error (which is not really an error)
            let nsError = error as NSError
            if nsError.domain == AVFoundationErrorDomain && nsError.code == AVError.maximumDurationReached.rawValue {
                // Max duration reached - this is expected, proceed with the video
                delegate?.videoRecorderDidFinish(with: outputFileURL)
            } else {
                delegate?.videoRecorderDidFinish(with: nil)
            }
        } else {
            #if DEBUG
            print("[VideoRecorder] Recording finished: \(outputFileURL)")
            #endif
            delegate?.videoRecorderDidFinish(with: outputFileURL)
        }
        
        dismiss(animated: true)
    }
}

