import AVFoundation
import SwiftUI

struct PairView: View {
    @Environment(AppModel.self) private var model
    @State private var scanning = false
    @State private var manual = false
    @State private var code = ""
    @State private var host = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            XMark(size: 72)
            Text("Claudex").font(.system(size: 34, weight: .semibold, design: .serif)).foregroundStyle(Theme.ink)
            Text("Pair with Claudex on your PC to follow and steer your sessions from here. Everything keeps running on the PC.")
                .font(.callout).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(.horizontal, 28)
            if let n = model.notice { Text(n).font(.footnote).foregroundStyle(Theme.bad).multilineTextAlignment(.center).padding(.horizontal, 28) }
            Spacer()
            VStack(spacing: 12) {
                Button { scanning = true } label: { Label("Scan the QR code", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(busy)
                Button("Enter the code by hand") { manual.toggle() }.font(.subheadline).foregroundStyle(Theme.muted)
                if manual {
                    TextField("Address on this PC, e.g. 100.64.0.1", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.numbersAndPunctuation).padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    TextField("Pairing code", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled().padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    Button("Pair") { go(AppModel.PairTarget(code: code.trimmingCharacters(in: .whitespaces), hosts: [host.trimmingCharacters(in: .whitespaces)], port: 18932)) }
                        .buttonStyle(.bordered).disabled(code.isEmpty || host.isEmpty || busy)
                }
                if busy { ProgressView() }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.bad).multilineTextAlignment(.center) }
                Text("On your PC: Claudex → Settings → Phone → Pair a phone.").font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 24).padding(.bottom, 32)
        }
        .fullScreenCover(isPresented: $scanning) {
            ScannerView { text in
                scanning = false
                if let t = AppModel.parse(text) { go(t) } else { error = "That isn't a Claudex pairing code." }
            } cancel: { scanning = false }
        }
        .task(id: model.pairLink) {
            guard let l = model.pairLink else { return }
            model.pairLink = nil
            if let t = AppModel.parse(l) { go(t) } else { error = "That isn't a Claudex pairing link." }
        }
    }

    private func go(_ t: AppModel.PairTarget) {
        busy = true; error = nil
        Task {
            do { try await model.pair(t) } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

struct ScannerView: View {
    var found: (String) -> Void
    var cancel: () -> Void
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Scanner(found: found).ignoresSafeArea()
            Button(action: cancel) { Image(systemName: "xmark.circle.fill").font(.title).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.5)) }
                .padding(20).accessibilityLabel("Close")
        }
    }
}

private struct Scanner: UIViewControllerRepresentable {
    var found: (String) -> Void
    func makeUIViewController(context: Context) -> ScanController { let c = ScanController(); c.found = found; return c }
    func updateUIViewController(_ c: ScanController, context: Context) {}
}

private final class ScanController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var found: (String) -> Void = { _ in }
    private let session = AVCaptureSession()
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async { if ok { self.setup() } }
        }
    }

    private func setup() {
        guard let dev = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) else { return }
        session.addInput(input)
        let out = AVCaptureMetadataOutput()
        guard session.canAddOutput(out) else { return }
        session.addOutput(out)
        out.setMetadataObjectsDelegate(self, queue: .main)
        out.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        DispatchQueue.global().async { self.session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.forEach { $0.frame = view.bounds }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !done, let s = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        done = true
        session.stopRunning()
        found(s)
    }
}
