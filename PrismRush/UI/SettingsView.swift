import SwiftUI
import UIKit

/// Settings sheet: music/SFX volume, haptics, reduced flashing, How to Play, Restore Purchases,
/// and the tappable version row (copies version+build to the pasteboard — support-mail ready,
/// uiux §5.9). Persists through `ProfileStore.mutate` and applies live to the engines
/// (`model.synth` / `model.haptics`). The flash toggle is consumed by EffectsOverlay + HUD rings.
struct SettingsView: View {
    let model: GameModel

    // Slider positions live locally so dragging doesn't hammer UserDefaults/iCloud; the profile is
    // written once per gesture (onEditingChanged) while the mixers update live per tick.
    @State private var music: Double        // in-game (run) music
    @State private var menuMusic: Double    // hub/splash music — tuned separately (owner request)
    @State private var sfx: Double
    @State private var showHowTo = false
    @State private var showPowerUps = false
    @State private var restoring = false
    @State private var restoreNote: String?
    @State private var versionCopied = false

    init(model: GameModel) {
        self.model = model
        let p = ProfileStore.shared.profile
        _music = State(initialValue: p.musicVolume)
        _menuMusic = State(initialValue: p.menuMusicVolume)
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
                    versionRow
                }
                .animation(.easeInOut(duration: 0.2), value: restoreNote)
                .animation(.easeInOut(duration: 0.2), value: versionCopied)
            }

            if showHowTo {
                HowToPlayView(onClose: { showHowTo = false })
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
            if showPowerUps {
                PowerUpsView(onClose: { showPowerUps = false })
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
        }
        .animation(.spring(duration: 0.3), value: showHowTo)
        .animation(.spring(duration: 0.3), value: showPowerUps)
        .onAppear {
            if ProcessInfo.processInfo.environment["PR_POWERUPS"] == "1" { showPowerUps = true }
        }
    }

    // MARK: audio

    private func audioCard(store: ProfileStore) -> some View {
        VStack(spacing: 14) {
            // Two separate music beds: the calm hub/splash ambience and the in-run track. Tuning
            // the menu bed down here changes it live while the hub plays, leaving gameplay untouched.
            sliderRow(symbol: "house.fill", label: "Menu music", value: $menuMusic) { final in
                store.mutate { $0.menuMusicVolume = final }
            }
            sliderRow(symbol: "gamecontroller.fill", label: "Game music", value: $music) { final in
                store.mutate { $0.musicVolume = final }
            }
            sliderRow(symbol: "speaker.wave.2.fill", label: "Sound effects", value: $sfx) { final in
                store.mutate { $0.sfxVolume = final }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12)))
        .onChange(of: menuMusic) { _, v in model.synth.menuMusicVolume = Float(v) }
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
        Button { showPowerUps = true } label: {
            navRow("bolt.circle.fill", "Power-Ups", Theme.color(0xFFD23D))
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("powerUpsRow")

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

    /// The version footer, promoted to a tappable row: copies "version (build)" to the pasteboard
    /// with a "Copied" confirmation — nothing on screen is display-only (uiux §5.9).
    private var versionRow: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return Button {
            UIPasteboard.general.string = "Prism Rush v\(version) (\(build))"
            versionCopied = true
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                versionCopied = false
            }
        } label: {
            HStack(spacing: 8) {
                Text("PRISM RUSH · v\(version) (\(build))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.35))
                Image(systemName: versionCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(versionCopied ? Theme.Role.interactive : .white.opacity(0.3))
                if versionCopied {
                    Text("Copied")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Role.interactive)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.neon)
        .padding(.top, 4)
        .accessibilityIdentifier("versionRow")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Version \(version), build \(build).")
        .accessibilityHint("Copies the version to the clipboard.")
    }
}
