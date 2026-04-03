import Foundation
import AVFoundation
import Photos
import Flutter

public protocol VideoGeneratorServiceInterface {
    func writeVideofile(srcPath:String, destPath:String, processing: [String: [String:Any]], inTime: Int64, outTime: Int64, result: @escaping FlutterResult, eventSink : FlutterEventSink?)
    func cancelCompression( result: @escaping FlutterResult)
}

public class VideoGeneratorService: VideoGeneratorServiceInterface {
        private var exporter: AVAssetExportSession? = nil
        private var exportProgressBarTimer:Timer? = nil // initialize timer
    public func writeVideofile(srcPath:String, destPath:String, processing: [String: [String:Any]], inTime: Int64, outTime: Int64, result: @escaping FlutterResult, eventSink : FlutterEventSink?) {
        let fileURL = URL(fileURLWithPath: srcPath)

        let composition = AVMutableComposition()
        let vidAsset = AVURLAsset(url: fileURL)

        // get video track
        guard let videoTrack = vidAsset.tracks(withMediaType: .video).first else {
            result(FlutterError(code: "video_processing_failed",
                                message: "No video track found in source file.",
                                details: nil))
            return
        }

        NSLog("[tapioca_v2] Video naturalSize: %@", NSCoder.string(for: videoTrack.naturalSize))
        NSLog("[tapioca_v2] Video preferredTransform: %@", NSCoder.string(for: videoTrack.preferredTransform))
        NSLog("[tapioca_v2] Processing entries: %d", processing.count)
        for (key, value) in processing {
            let bitmapSize = (value["bitmap"] as? FlutterStandardTypedData)?.data.count ?? 0
            let hasText = value["text"] != nil
            NSLog("[tapioca_v2]   [%@] bitmap=%dbytes text=%@", key, bitmapSize, hasText ? "true" : "false")
        }

        let time1 = CMTimeMake(value: inTime, timescale: 1000)
        let time2 = CMTimeMake(value: outTime, timescale: 1000)

        let vidTimerange = CMTimeRangeMake(start: time1, duration: time2)


        guard let compositionvideoTrack:AVMutableCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            result(FlutterError(code: "video_processing_failed",
                                message: "composition.addMutableTrack is failed.",
                                details: nil))
            return
        }
        do {
            try compositionvideoTrack.insertTimeRange(vidTimerange, of: videoTrack, at: .zero)
            if let audioAssetTrack = vidAsset.tracks(withMediaType: .audio).first,
               let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid) {
                try compositionAudioTrack.insertTimeRange(
                    vidTimerange,
                    of: audioAssetTrack,
                    at: .zero)
            }
        } catch {
            print(error)
            result(FlutterError(code: "video_processing_failed",
                                message: "compositionvideoTrack is failed.",
                                details: nil))
            return
        }

        compositionvideoTrack.preferredTransform = videoTrack.preferredTransform
        let size = videoTrack.naturalSize

        var handlerCallCount = 0
        let layercomposition = AVVideoComposition(asset: composition) { (filteringRequest) in
            handlerCallCount += 1
            if handlerCallCount <= 3 {
                NSLog("[tapioca_v2] Filter handler frame #%d at %.3fs", handlerCallCount, CMTimeGetSeconds(filteringRequest.compositionTime))
                NSLog("[tapioca_v2]   sourceImage.extent: %@", NSCoder.string(for: filteringRequest.sourceImage.extent))
            }

            var source = filteringRequest.sourceImage.clampedToExtent()
            let currentTimeSec = CMTimeGetSeconds(filteringRequest.compositionTime)
            let currentTimeMs = currentTimeSec * 1000.0

            for (key, value) in processing  {
                // Strip index suffix (e.g. "ImageOverlay_1" → "ImageOverlay")
                // to support multiple overlays of the same type.
                let baseKey = key.components(separatedBy: "_").count > 1 && key.last?.isNumber == true
                    ? key.components(separatedBy: "_").dropLast().joined(separator: "_")
                    : key

                switch baseKey {
                case "Filter":
                    guard let type = value["type"] as? String,
                       let alpha = value["alpha"] as? Double else {
                        print("not found value")
                        result(FlutterError(code: "processing_data_invalid",
                                            message: "one Filter member is not found.",
                                            details: nil))
                        return
                    }

                    let overlayColor = UIColor(hex: type.replacingOccurrences(of: "#", with: ""), alpha: alpha)
                    let c = CIColor(color: overlayColor)
                    guard let colorFilter = CIFilter(name: "CIConstantColorGenerator", parameters: [kCIInputColorKey: c]) else {
                        print("[tapioca_v2] Filter: failed to create CIConstantColorGenerator")
                        break
                    }
                    let parameters = [
                        kCIInputBackgroundImageKey: source,
                        kCIInputImageKey: colorFilter.outputImage!
                    ]
                    guard let filter = CIFilter(name: "CISourceOverCompositing", parameters: parameters),
                          let outputImage = filter.outputImage else {
                        print("[tapioca_v2] Filter: failed to create CISourceOverCompositing")
                        break
                    }
                    let cropRect = source.extent
                    source = outputImage.cropped(to: cropRect)

                case "TextOverlay":
                    guard let text = value["text"] as? String,
                          let x = value["x"] as? NSNumber,
                          let y = value["y"] as? NSNumber,
                          let textSize = value["size"] as? NSNumber,
                          let color = value["color"] as? String else {
                        print("not found text overlay")
                        result(FlutterError(code: "processing_data_invalid",
                                            message: "one TextOverlay member is not found.",
                                            details: nil))
                        return
                    }
                    let font = UIFont.boldSystemFont(ofSize: CGFloat(truncating: textSize))

                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: UIColor(hex:color.replacingOccurrences(of: "#", with: ""),alpha: 1),
                    ]

                    let attributedQuote = NSAttributedString(string: text, attributes: attributes)
                    let textGenerationFilter = CIFilter(name: "CIAttributedTextImageGenerator")!
                    textGenerationFilter.setValue(attributedQuote, forKey: "inputText")
                    let textImage = textGenerationFilter.outputImage!
                    let transform = CGAffineTransform(translationX: CGFloat(truncating: x), y: filteringRequest.sourceImage.extent.height - CGFloat(truncating: textSize) - CGFloat(truncating: y))

                    source = textImage
                            .transformed(by: transform)
                            .applyingFilter("CISourceAtopCompositing", parameters: [kCIInputBackgroundImageKey: source])

                case "ImageOverlay":
                    guard let bitmap = value["bitmap"] as? FlutterStandardTypedData,
                          let x = value["x"] as? NSNumber,
                          let y = value["y"] as? NSNumber else {
                        NSLog("[tapioca_v2] ImageOverlay guard FAILED for key '%@' — bitmap or x/y missing", key)
                        print("not found image overlay")
                        result(FlutterError(code: "processing_data_invalid",
                                            message: "one ImageOverlay member is not found.",
                                            details: nil))
                        return
                    }
                    // Explicitly specify sRGB color space so CIImage correctly
                    // applies the sRGB transfer function during compositing.
                    // Without this, PNG overlays generated by Flutter's dart:ui
                    // Canvas may appear darker/greyer because CIImage defaults
                    // to a generic or linear color space interpretation.
                    let overlayOptions: [CIImageOption: Any] = {
                        if let srgb = CGColorSpace(name: CGColorSpace.sRGB) {
                            return [.colorSpace: srgb]
                        }
                        return [:]
                    }()
                    guard let watermarkImage = CIImage(data: bitmap.data, options: overlayOptions) else {
                        NSLog("[tapioca_v2] CIImage(data:) FAILED for key '%@' — %d bytes", key, bitmap.data.count)
                        result(FlutterError(code: "video_processing_failed",
                                            message: "creating overlay image failed.",
                                            details: nil))
                        return
                    }

                    if handlerCallCount <= 2 {
                        let cs = watermarkImage.colorSpace?.name ?? "nil" as CFString
                        NSLog("[tapioca_v2] [%@] watermark extent: %@, colorSpace: %@, alpha will be %@",
                              key,
                              NSCoder.string(for: watermarkImage.extent),
                              cs as String,
                              value["startMs"] != nil ? "timed" : "static")
                    }

                    // Compute time-based alpha for fade-in/out
                    var overlayAlpha: Double = 1.0
                    let hasTimingParams = value["startMs"] != nil
                    if hasTimingParams {
                        let startMs = (value["startMs"] as? NSNumber)?.doubleValue ?? 0.0
                        let endMs = (value["endMs"] as? NSNumber)?.doubleValue ?? Double.greatestFiniteMagnitude
                        let fadeInMs = (value["fadeInMs"] as? NSNumber)?.doubleValue ?? 0.0
                        let fadeOutMs = (value["fadeOutMs"] as? NSNumber)?.doubleValue ?? 0.0

                        let currentTimeInSeconds = CMTimeGetSeconds(filteringRequest.compositionTime)
                        let currentTimeInMs = currentTimeInSeconds * 1000.0
                        let duration = endMs - startMs

                        if duration <= 0 || currentTimeInMs < startMs || currentTimeInMs >= endMs {
                            overlayAlpha = 0.0
                        } else {
                            let elapsed = currentTimeInMs - startMs
                            let remaining = endMs - currentTimeInMs
                            var alpha = 1.0
                            if fadeInMs > 0 && elapsed < fadeInMs {
                                alpha = elapsed / fadeInMs
                            }
                            if fadeOutMs > 0 && remaining < fadeOutMs {
                                let fadeOutAlpha = remaining / fadeOutMs
                                alpha = min(alpha, fadeOutAlpha)
                            }
                            alpha = max(0.0, min(1.0, alpha))
                            // Smoothstep easing: x² × (3 − 2x)
                            if alpha > 0.0 && alpha < 1.0 {
                                alpha = alpha * alpha * (3.0 - 2.0 * alpha)
                            }
                            overlayAlpha = alpha
                        }
                    }

                    // Skip compositing if fully transparent
                    if overlayAlpha <= 0.001 {
                        break
                    }

                    // Apply alpha fade to the watermark image using CIColorMatrix
                    var fadedWatermark = watermarkImage
                    if overlayAlpha < 0.999 {
                        let alphaFilter = CIFilter(name: "CIColorMatrix")!
                        alphaFilter.setValue(watermarkImage, forKey: kCIInputImageKey)
                        alphaFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                        alphaFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
                        alphaFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
                        alphaFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(overlayAlpha)), forKey: "inputAVector")
                        alphaFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
                        fadedWatermark = alphaFilter.outputImage ?? watermarkImage
                    }

                    // Position the overlay: convert Flutter top-left origin (x,y)
                    // to CIImage bottom-left origin.
                    // For full-frame overlays at (0,0) this is a no-op since
                    // watermark.extent == source.extent.
                    let xOffset = CGFloat(truncating: x)
                    let yOffset = filteringRequest.sourceImage.extent.height - fadedWatermark.extent.height - CGFloat(truncating: y)
                    if xOffset != 0 || CGFloat(truncating: y) != 0 {
                        fadedWatermark = fadedWatermark.transformed(by: CGAffineTransform(translationX: xOffset, y: yOffset))
                    }

                    // Composite the overlay onto the source frame
                    let imageFilter = CIFilter(name: "CISourceOverCompositing")!
                    imageFilter.setValue(source, forKey: "inputBackgroundImage")
                    imageFilter.setValue(fadedWatermark, forKey: "inputImage")
                    source = imageFilter.outputImage!

                default:
                    print("Not implement filter name")
                }
            }
            filteringRequest.finish(with: source, context: nil)
        }

        NSLog("[tapioca_v2] AVVideoComposition renderSize: %@", NSCoder.string(for: layercomposition.renderSize))
        NSLog("[tapioca_v2] AVVideoComposition frameDuration: %@", String(describing: layercomposition.frameDuration))
        NSLog("[tapioca_v2] AVVideoComposition instructions: %d", layercomposition.instructions.count)

        let movieDestinationUrl = URL(fileURLWithPath: destPath)
        let preset: String = AVAssetExportPresetHighestQuality
        NSLog("[tapioca_v2] Export preset: %@", preset)
        guard let assetExport = AVAssetExportSession(asset: composition, presetName: preset) else {
            print("assertExport error")
            result(FlutterError(code: "video_processing_failed",
                                message: "init AVAssetExportSession is failed.",
                                details: nil))
            return
        }
        assetExport.outputFileType = .mp4
        assetExport.videoComposition = layercomposition

        assetExport.outputURL = movieDestinationUrl
        if #available(iOS 10.0, *) {
            exportProgressBarTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            // Get Progress
            let progress = Float((assetExport.progress));
            if (progress < 0.99 && eventSink != nil) {
                eventSink!(progress * 100)
            }
            }
        }
        exporter = assetExport
        assetExport.exportAsynchronously{
            switch assetExport.status{
            case .completed:
                print("Movie complete")
                self.exporter = nil
                self.exportProgressBarTimer?.invalidate()
                self.exportProgressBarTimer = nil
                result(nil)
            case  .failed:
                self.exporter = nil
                self.exportProgressBarTimer?.invalidate()
                self.exportProgressBarTimer = nil
                let errorMsg = assetExport.error?.localizedDescription ?? "Unknown export error"
                print("failed: \(errorMsg)")
                result(FlutterError(code: "video_export_failed",
                                    message: errorMsg,
                                    details: nil))
            case .cancelled:
                self.exporter = nil
                self.exportProgressBarTimer?.invalidate()
                self.exportProgressBarTimer = nil
                print("cancelled")
                result(FlutterError(code: "video_export_cancelled",
                                    message: "Video export was cancelled.",
                                    details: nil))
            default:
                self.exporter = nil
                self.exportProgressBarTimer?.invalidate()
                self.exportProgressBarTimer = nil
                print("export ended with status: \(assetExport.status.rawValue)")
                result(nil)
                break
            }
        }
    }
     public func cancelCompression(result: FlutterResult) {
            exporter?.cancelExport()
            self.exporter = nil
            self.exportProgressBarTimer?.invalidate()
            self.exportProgressBarTimer = nil
            result(nil)
        }
}

extension UIColor {
    convenience init(hex: String, alpha: Double) {
        let v = Int("000000" + hex, radix: 16) ?? 0
        let r = CGFloat(v / Int(powf(256, 2)) % 256) / 255
        let g = CGFloat(v / Int(powf(256, 1)) % 256) / 255
        let b = CGFloat(v / Int(powf(256, 0)) % 256) / 255
        self.init(red: r, green: g, blue: b, alpha: min(max(alpha, 0), 1))
    }
}

struct Filter {
    let type: String
    let alpha: Double
}

struct ImageOverlay {
    let bitmap: Data
    let x: NSNumber
    let y: NSNumber
}

struct TextOverlay {
    let text: String
    let x: NSNumber
    let y: NSNumber
    let size: NSNumber
    let color: String
    let start: NSNumber
    let duration: NSNumber
}
