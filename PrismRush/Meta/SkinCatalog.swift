import Foundation

/// A procedural character skin (no asset files). `bodyHex == 0` means "follow the live world accent"
/// (the default look); any other value is a fixed colour. `premium` skins unlock only via IAP.
struct Skin: Identifiable, Sendable {
    let id: String
    let name: String
    let cost: Int
    let bodyHex: UInt32
    let antennaHex: UInt32
    let premium: Bool

    var followsWorld: Bool { bodyHex == 0 }
}

enum SkinCatalog {
    static let all: [Skin] = [
        Skin(id: "default", name: "Prism",  cost: 0,    bodyHex: 0,        antennaHex: 0,        premium: false),
        Skin(id: "ember",   name: "Ember",  cost: 200,  bodyHex: 0xFF5E3A, antennaHex: 0xFFD23D, premium: false),
        Skin(id: "void",    name: "Void",   cost: 350,  bodyHex: 0xB26BFF, antennaHex: 0x00FFC8, premium: false),
        Skin(id: "toxic",   name: "Toxic",  cost: 500,  bodyHex: 0x39FF14, antennaHex: 0xFF2BD6, premium: false),
        Skin(id: "mono",    name: "Mono",   cost: 750,  bodyHex: 0xF4F8FF, antennaHex: 0x0A0A14, premium: false),
        Skin(id: "midas",   name: "Midas",  cost: 1500, bodyHex: 0xFFD23D, antennaHex: 0xFFFFFF, premium: false),
        Skin(id: "aurora",  name: "Aurora", cost: 0,    bodyHex: 0x00FFC8, antennaHex: 0xFF2BD6, premium: true),
    ]

    static func skin(_ id: String) -> Skin { all.first { $0.id == id } ?? all[0] }
}
