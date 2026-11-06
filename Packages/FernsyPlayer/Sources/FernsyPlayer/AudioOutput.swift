import AVFoundation
import CoreAudio
import FernsyCore

/// What the sound goes to: how many channels the output takes and, on Apple TV, iPhone and iPad,
/// how the system renders it (apple-tv-surround design 1). The player is the one owner of the
/// audio session there; the Mac asks the default output device.
public final class AudioOutput: ObservableObject {
    public static let shared = AudioOutput()

    /// The output's channels (the session's maximum, or the Mac's output device).
    @Published public private(set) var channels = 2
    /// The system's rendering mode in plain words ("Dolby Atmos", "Surround"); nil on the Mac.
    @Published public private(set) var renderingMode: String?

    /// The most PCM channels worth sending (2, 6 or 8), for the audio thread.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var channelsNow: Int32 = 2
    static var outputChannels: Int32 {
        lock.lock()
        defer { lock.unlock() }
        return channelsNow
    }

    private var observers: [NSObjectProtocol] = []
    /// The audio session's calls block (activation can take a moment, longer on a busy
    /// simulator): they run here, never on the main thread. Results go to the main thread.
    private let queue = DispatchQueue(label: "player.audio-session", qos: .userInitiated)
    private var isActive = false // queue only

    private init() {
        #if os(iOS) || os(tvOS)
        queue.async {
            // Playback keeps its sound in Picture in Picture and on AirPlay (ios-app design 5, 6).
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
            #else
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            #endif
        }
        let center = NotificationCenter.default
        for name in [AVAudioSession.routeChangeNotification, AVAudioSession.renderingCapabilitiesChangeNotification,
                     AVAudioSession.renderingModeChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.queue.async { self?.refresh() }
            })
        }
        #endif
    }

    /// Before a playback starts: activates the session (iOS, tvOS) and reads the output again,
    /// in the background. Not at launch, which would stop other apps' sound on an iPhone.
    func prepare() {
        queue.async { self.activateAndRefresh() }
    }

    private func activateAndRefresh() {
        #if os(iOS) || os(tvOS)
        if !isActive {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setActive(true)
                isActive = true
            } catch {
                AppLog.warning(.player, "audio session could not be activated: \(error.localizedDescription)")
            }
        }
        #endif
        refresh()
    }

    private func refresh() {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        // Not outputNumberOfChannels: it reports 2 after a stereo item (KSPlayer).
        let maximum = session.maximumOutputNumberOfChannels
        try? session.setSupportsMultichannelContent(true)
        if maximum > 2 { try? session.setPreferredOutputNumberOfChannels(maximum) }
        let mode = Self.describe(session.renderingMode)
        update(channels: maximum, mode: mode, log: "output \(maximum) ch, rendering \(mode ?? "–")")
        #else
        let channels = Self.defaultDeviceChannels()
        update(channels: channels, mode: nil, log: "output device \(channels) ch")
        #endif
    }

    private func update(channels: Int, mode: String?, log: String) {
        Self.lock.lock()
        Self.channelsNow = Int32(Self.pcmChannels(channels))
        Self.lock.unlock()
        DispatchQueue.main.async { [self] in
            if channels != self.channels || mode != renderingMode { AppLog.info(.player, "audio \(log)") }
            if self.channels != channels { self.channels = channels }
            if renderingMode != mode { renderingMode = mode }
        }
    }

    /// The PCM channel count worth sending to an output with `maximum` channels.
    static func pcmChannels(_ maximum: Int) -> Int {
        maximum >= 8 ? 8 : maximum >= 6 ? 6 : 2
    }

    #if os(iOS) || os(tvOS)
    /// nil when the system reports none (simulator, no output).
    private static func describe(_ mode: AVAudioSession.RenderingMode) -> String? {
        switch mode {
        case .dolbyAtmos: String(localized: "Dolby Atmos", bundle: .module)
        case .dolbyAudio: String(localized: "Dolby Audio", bundle: .module)
        case .surround: String(localized: "Surround", bundle: .module)
        case .spatialAudio: String(localized: "Spatial Audio", bundle: .module)
        case .monoStereo: String(localized: "Stereo", bundle: .module)
        default: nil
        }
    }
    #else
    /// Output channels of the Mac's default output device (2 when it cannot be read).
    private static func defaultDeviceChannels() -> Int {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return 2 }
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                             mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 2 }
        let list = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { list.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, list) == noErr else { return 2 }
        let buffers = UnsafeMutableAudioBufferListPointer(list.assumingMemoryBound(to: AudioBufferList.self))
        return max(2, buffers.reduce(0) { $0 + Int($1.mNumberChannels) })
    }
    #endif
}
