import UIKit
import CoreML
import ImageIO
import StableDiffusion

/// All StableDiffusionPipeline calls are isolated here so no @available bleed happens
/// into the main FlutterPlugin class.
@available(iOS 16.2, *)
final class SDPipelineRunner {

    private var pipeline: StableDiffusionPipeline?
    var cancelled = false

    var isReady: Bool { pipeline != nil }

    // MARK: - Load

    func load(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let cfg = MLModelConfiguration()
        cfg.computeUnits = .cpuAndNeuralEngine
        let pl = try StableDiffusionPipeline(
            resourcesAt: url,
            controlNet: [],
            configuration: cfg,
            disableSafety: false,
            reduceMemory: true
        )
        try pl.loadResources()
        pipeline = pl
    }

    func unload() { pipeline = nil }

    // MARK: - Generate

    func generate(
        prompt: String,
        negativePrompt: String,
        steps: Int,
        guidanceScale: Float,
        seed: UInt32,
        frameCount: Int,
        startingImage: CGImage? = nil,
        strength: Float = 0.7,
        onProgress: @escaping (_ step: Int, _ total: Int, _ overall: Double) -> Void
    ) throws -> Data {
        guard let pl = pipeline else {
            throw SDRunnerError.notLoaded
        }

        var seeds: [UInt32] = [seed]
        for i in 1..<max(1, frameCount) {
            seeds.append(seed &+ UInt32(i) &* 17)
        }

        var frames: [CGImage] = []

        for (fi, frameSeed) in seeds.enumerated() {
            if cancelled { break }

            var cfg = StableDiffusionPipeline.Configuration(prompt: prompt)
            cfg.negativePrompt = negativePrompt
            cfg.stepCount = steps
            cfg.seed = frameSeed
            cfg.guidanceScale = guidanceScale
            cfg.schedulerType = .dpmSolverMultistepScheduler

            // img2img: use source image as starting point
            if let srcImg = startingImage {
                cfg.startingImage = srcImg
                cfg.strength = strength
            }

            let images = try pl.generateImages(
                configuration: cfg,
                progressHandler: { (p: StableDiffusionPipeline.Progress) -> Bool in
                    let overall = (Double(fi) + Double(p.step) / Double(steps))
                                  / Double(seeds.count)
                    onProgress(p.step, steps * seeds.count, overall)
                    return !self.cancelled
                }
            )
            if let cg = images.first.flatMap({ $0 }) {
                frames.append(cg)
            }
        }

        guard !frames.isEmpty else { throw SDRunnerError.noOutput }

        if frames.count == 1 {
            guard let data = UIImage(cgImage: frames[0]).pngData() else {
                throw SDRunnerError.encodeFailed
            }
            return data
        }
        guard let data = makeAPNG(frames: frames, frameDuration: 0.25) else {
            throw SDRunnerError.encodeFailed
        }
        return data
    }

    // MARK: - APNG

    private func makeAPNG(frames: [CGImage], frameDuration: Double) -> Data? {
        let buf = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            buf, "public.png" as CFString, frames.count, nil
        ) else { return nil }

        CGImageDestinationSetProperties(dest, [kCGImagePropertyAPNGLoopCount: 0] as CFDictionary)

        let pngDelay: [CFString: Any] = [kCGImagePropertyAPNGDelayTime: frameDuration]
        let frameProps = [kCGImagePropertyPNGDictionary: pngDelay] as CFDictionary
        for frame in frames {
            CGImageDestinationAddImage(dest, frame, frameProps)
        }
        return CGImageDestinationFinalize(dest) ? (buf as Data) : nil
    }
}

enum SDRunnerError: Error {
    case notLoaded, noOutput, encodeFailed
}
