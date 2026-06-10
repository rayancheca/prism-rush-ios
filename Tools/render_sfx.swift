import Foundation

// Renders every synthesized SFX + 2 bars of each world's music to 44.1 kHz mono 16-bit WAVs for
// human review. Compile together with the pure-Foundation synth:
//   swiftc PrismRush/Audio/Synth.swift Tools/render_sfx.swift -o /tmp/render_sfx
//   /tmp/render_sfx reports/audio

func writeWAV(_ samples: [Float], to path: String) {
    let sr: UInt32 = 44_100
    var pcm = [Int16](); pcm.reserveCapacity(samples.count)
    for s in samples { pcm.append(Int16(max(-1, min(1, s)) * 32_767)) }
    let dataSize = pcm.count * 2

    var data = Data()
    func a32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
    func a16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
    data.append("RIFF".data(using: .ascii)!); a32(UInt32(36 + dataSize)); data.append("WAVE".data(using: .ascii)!)
    data.append("fmt ".data(using: .ascii)!); a32(16); a16(1); a16(1)
    a32(sr); a32(sr * 2); a16(2); a16(16)
    data.append("data".data(using: .ascii)!); a32(UInt32(dataSize))
    pcm.withUnsafeBytes { data.append(contentsOf: $0) }
    try? data.write(to: URL(fileURLWithPath: path))
}

func peak(_ s: [Float]) -> Float { s.reduce(0) { max($0, abs($1)) } }

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "reports/audio"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sfx: [(String, [Float])] = [
    ("gem0", Synth.gem(streak: 0)), ("gem10", Synth.gem(streak: 10)),
    ("jump", Synth.jump()), ("slide", Synth.slide()), ("crash", Synth.crash()),
    ("chime", Synth.chime()), ("worldSweep", Synth.worldSweep()),
    ("close", Synth.close()), ("startChime", Synth.startChime()),
]
for (name, s) in sfx {
    let path = "\(outDir)/\(name).wav"
    writeWAV(s, to: path)
    print("\(name): \(String(format: "%.3f", Double(s.count) / 44_100))s  peak=\(String(format: "%.3f", peak(s)))  -> \(path)")
}

for world in 0..<3 {
    var bar = [Float]()
    for beat in 0..<16 { bar += Synth.step(beat: beat, world: world) }
    let path = "\(outDir)/music_world\(world + 1).wav"
    writeWAV(bar, to: path)
    print("music_world\(world + 1): \(String(format: "%.2f", Double(bar.count) / 44_100))s  peak=\(String(format: "%.3f", peak(bar)))  -> \(path)")
}
