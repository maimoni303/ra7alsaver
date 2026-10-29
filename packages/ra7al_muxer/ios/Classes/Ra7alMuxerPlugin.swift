import AVFoundation
import Flutter

public class Ra7alMuxerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ra7al_muxer", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(Ra7alMuxerPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "remux",
          let args = call.arguments as? [String: Any],
          let inputs = args["inputs"] as? [String],
          let output = args["output"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    let wantVideo = (args["video"] as? Bool) ?? true
    let wantAudio = (args["audio"] as? Bool) ?? true
    DispatchQueue.global(qos: .userInitiated).async {
      Ra7alMuxerPlugin.remux(inputs: inputs, output: output, video: wantVideo, audio: wantAudio) { error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "remux", message: error, details: nil))
          } else {
            result(nil)
          }
        }
      }
    }
  }

  static func remux(inputs: [String], output: String, video: Bool, audio: Bool, done: @escaping (String?) -> Void) {
    let comp = AVMutableComposition()
    var duration = CMTime.invalid
    var videoTrack: AVAssetTrack?
    var audioTrack: AVAssetTrack?
    var videoAsset: AVURLAsset?
    for path in inputs {
      let asset = AVURLAsset(url: URL(fileURLWithPath: path))
      if videoTrack == nil, let t = asset.tracks(withMediaType: .video).first {
        videoTrack = t
        videoAsset = asset
      }
      if audioTrack == nil, let t = asset.tracks(withMediaType: .audio).first { audioTrack = t }
    }
    if video, let va = videoAsset { duration = va.duration }
    else if let at = audioTrack { duration = at.asset?.duration ?? at.timeRange.duration }
    if !duration.isValid { done("No usable track"); return }
    let range = CMTimeRange(start: .zero, duration: duration)
    do {
      if video {
        guard let vt = videoTrack,
              let ct = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { done("No video track"); return }
        try ct.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, vt.timeRange.duration)), of: vt, at: .zero)
        ct.preferredTransform = vt.preferredTransform
      }
      if audio, let at = audioTrack,
         let ct = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
        try ct.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(range.duration, at.timeRange.duration)), of: at, at: .zero)
      } else if audio && !video {
        done("No audio track"); return
      }
    } catch {
      done(error.localizedDescription); return
    }
    let out = URL(fileURLWithPath: output)
    try? FileManager.default.removeItem(at: out)
    guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else {
      done("Export unavailable"); return
    }
    export.outputURL = out
    export.outputFileType = video ? .mp4 : .m4a
    export.shouldOptimizeForNetworkUse = true
    export.exportAsynchronously {
      if export.status == .completed {
        done(nil)
      } else {
        try? FileManager.default.removeItem(at: out)
        done(export.error?.localizedDescription ?? "Export failed")
      }
    }
  }
}
