import SwiftUI
import AVFoundation

struct QRScanView: UIViewControllerRepresentable {
    let onScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRScanViewController {
        let vc = QRScanViewController()
        vc.onScanned = onScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScanViewController, context: Context) {}
}

final class QRScanViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScanned: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupStatusLabel()
        addCancelButton()
        requestCameraAndStart()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        // Lock orientation to portrait for the preview
        if let connection = previewLayer?.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    private func setupStatusLabel() {
        statusLabel.text = "Memuat kamera…"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func requestCameraAndStart() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.setupCamera() }
                    else { self?.showPermissionDenied() }
                }
            }
        case .denied, .restricted:
            showPermissionDenied()
        @unknown default:
            showPermissionDenied()
        }
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            statusLabel.text = "❌ Kamera tidak tersedia di perangkat ini"
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                statusLabel.text = "❌ Tidak bisa menambah input kamera"
                session.commitConfiguration()
                return
            }
            session.addInput(input)
        } catch {
            statusLabel.text = "❌ Gagal akses kamera: \(error.localizedDescription)"
            session.commitConfiguration()
            return
        }

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            statusLabel.text = "❌ Tidak bisa menambah output QR scanner"
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        session.commitConfiguration()

        // Preview layer
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        captureSession = session
        statusLabel.text = ""

        // Add scan area hint
        addScanFrameHint()

        // Start session di background thread (wajib di iOS 17+)
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func addScanFrameHint() {
        let box = UIView()
        box.layer.borderColor = UIColor.systemYellow.cgColor
        box.layer.borderWidth = 3
        box.layer.cornerRadius = 12
        box.backgroundColor = .clear
        box.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(box)

        let hint = UILabel()
        hint.text = "Arahkan ke QR Code Konfigurasi Ujian"
        hint.textColor = .white
        hint.font = .systemFont(ofSize: 14, weight: .medium)
        hint.textAlignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)

        NSLayoutConstraint.activate([
            box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            box.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            box.widthAnchor.constraint(equalToConstant: 250),
            box.heightAnchor.constraint(equalToConstant: 250),

            hint.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 16),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func showPermissionDenied() {
        statusLabel.text = """
        ❌ Akses Kamera Ditolak

        Buka Pengaturan iOS → AgreXambro → Izinkan Kamera, lalu coba lagi.
        """

        let btn = UIButton(type: .system)
        btn.setTitle("Buka Pengaturan", for: .normal)
        btn.setTitleColor(.systemYellow, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            btn.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        btn.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
    }

    @objc private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func addCancelButton() {
        var config = UIButton.Configuration.filled()
        config.title = "Batal"
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.6)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        var titleAttr = AttributeContainer()
        titleAttr.font = .systemFont(ofSize: 17, weight: .semibold)
        config.attributedTitle = AttributedString("Batal", attributes: titleAttr)

        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            btn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        btn.addTarget(self, action: #selector(cancel), for: .touchUpInside)
    }

    @objc private func cancel() { dismiss(animated: true) }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        // Stop session di background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
            DispatchQueue.main.async {
                self?.dismiss(animated: true) {
                    self?.onScanned?(value)
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession?.isRunning == true {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.stopRunning()
            }
        }
    }
}
