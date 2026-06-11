import SwiftUI

/// Settings sheet: music/SFX volume, haptics, reduced flashing, How to Play, Restore Purchases,
/// and the version footer. Persists through `ProfileStore.mutate` and applies live to the engines
/// (`model.synth` / `model.haptics`). The flash toggle is consumed by EffectsOverlay (wiring spec
/// in reports/AGENT_meta.md).
struct SettingsView: View {
    let model: GameModel

    // Slider positions live locally so dragging doesn't hammer UserDefaults/iCloud; the profile is
    // written once per gesture (onEditingChanged) while the mixers update live per tick.
    @State private var music: Double
    @State private var sfx: Double
    @State private var showHowTo = false
    @State private var restoring = false
    @State private var restoreNote: String?

    init(model: GameModel) {
        self.model = model
        let p = ProfileStore.shared.profile
        _music = State(initialValue: p.musicVolume)
        _sfx = State(initialValue: p.sfxVolume)
    }

    var body: some View {
        let store = ProfileStore.shared
        ZStack {
            MetaScreenScaffold(title: "Settings", coins: store.profile.coins, onClose: { model.closeSheet() }) {
                VStack(spacing: 14) {
                    audioCard(store: store)
                    feedbackCard(store: store)
                    rows
                    if let note = restoreNote {
                        Text(note)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .transition(.opacity)
                    }
                    footer
                }
                .animation(.easeInOut(duration: 0.2), value: restoreNote)
            }

            if showHowTo {
                HowToPlayView(onClose: { showHowTo = false })
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
        }
        .animation(.spring(duration: 0.3), value: showHowTo)
    }

    // MARK: audio

    private func audioCard(store: ProfileStore) -> some View {
        VStack(spacing: 14) {
            sliderRow(symbol: "music.note", label: "Music", value: $music) { final in
                store.mutate { $0.musicVolume = final }
            }
            sliderRow(symbol: "speaker.wave.2.fill", label: "Sound effects", value: $sfx) { final in
                store.mutate { $0.sfxVolume = final }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12)))
        .onChange(of: music) { _, v in model.synth.musicVolume = Float(v) }
        .onChange(of: sfx) { _, v in model.synth.sfxVolume = Float(v) }
    }

    private func sliderRow(symbol: String, label: String, value: Binding<Double>,
                           commit: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.color(0x00F5FF))
                .frame(width: 24)
            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Slider(value: value, in: 0...1) { editing in
                if !editing { commit(value.wrappedValue) }
            }
            .tint(Theme.color(0x00F5FF))
            .accessibilityLabel("\(label) volume")
            .accessibilityValue("\(Int(value.wrappedValue * 100)) percent")
        }
    }

    // MARK: feedback (haptics + flash)

    private func feedbackCard(store: ProfileStore) -> some View {
        VStack(spacing: 4) {
            toggleRow(symbol: "iphone.radiowaves.left.and.right", label: "Haptics",
                      isOn: Binding(get: { store.profile.hapticsEnabled },
                                    set: { v in
                                        store.mutate { $0.hapticsEnabled = v }
                                        model.haptics.enabled = v
                                    }))
            Divider().overlay(.white.opacity(0.1))
            toggleRow(symbol: "bolt.slash.fill", label: "Reduce flashing",
                      detail: "Tones down full-screen flash effects",
                      isOn: Binding(get: { store.profile.reduceFlash },
                                    set: { v in store.mutate { $0.reduceFlash = v } }))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12)))
    }

    private func toggleRow(symbol: String, label: String, detail: String? = nil,
                           isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.color(0x00F5FF))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
        }
        .tint(Theme.color(0x00F5FF))
        .padding(.vertical, 8)
    }

    // MARK: navigation rows

    @ViewBuilder private var rows: some View {
        Button { showHowTo = true } label: {
            navRow("questionmark.circle.fill", "How to Play", Theme.color(0x00F5FF))
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("howToPlayRow")

        Button {
            guard !restoring else { return }
            restoring = true
            Task {
                let ok = await IAPManager.shared.restorePurchases()
                restoring = false
                restoreNote = ok ? "Purchases restored." : (IAPManager.shared.lastError ?? "Restore failed.")
                try? await Task.sleep(for: .seconds(2.4))
                restoreNote = nil
            }
        } label: {
            navRow("arrow.clockwise", restoring ? "Restoring…" : "Restore Purchases", .white)
        }
        .buttonStyle(.neon)
        .disabled(restoring)
        .accessibilityIdentifier("restorePurchasesRow")
    }

    private func navRow(_ symbol: String, _ title: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint).frame(width: 24)
            Text(title).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
    }

    private var footer: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return Text("PRISM RUSH · v\(version) (\(build))")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(2)
            .foregroundStyle(.white.opacity(0.35))
            .padding(.top, 10)
    }
}
