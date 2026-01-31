import SwiftUI

// MARK: - Design System

extension Color {
    // Primary accent — deep indigo, confident and premium
    static let npAccent = Color(red: 0.36, green: 0.38, blue: 0.94)       // #5C61F0
    static let npAccentLight = Color(red: 0.48, green: 0.50, blue: 0.96)  // lighter hover
    static let npAccentSubtle = Color(red: 0.36, green: 0.38, blue: 0.94).opacity(0.08)

    // Semantic
    static let npGreen = Color(red: 0.22, green: 0.78, blue: 0.56)        // #38C78F — success
    static let npGreenSubtle = Color(red: 0.22, green: 0.78, blue: 0.56).opacity(0.10)

    // Surface layers
    static let npSurface = Color(nsColor: .windowBackgroundColor)
    static let npSurfaceRaised = Color.primary.opacity(0.03)
    static let npBorder = Color.primary.opacity(0.08)
}

// MARK: - Main View

struct MainView: View {
    @State private var appState = AppState()
    @State private var showSettings = false
    @State private var urlFieldFocused = false

    var body: some View {
        VStack(spacing: 0) {
            // URL input area
            VStack(spacing: 14) {
                // Mode picker
                HStack {
                    Picker("", selection: $appState.config.isBulkMode) {
                        Label("Single URL", systemImage: "globe")
                            .tag(false)
                        Label("Multiple URLs", systemImage: "list.bullet.rectangle")
                            .tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .disabled(appState.isRunning)
                    Spacer()
                }

                // URL input + scan button
                HStack(alignment: .top, spacing: 10) {
                    if appState.config.isBulkMode {
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $appState.config.bulkInput)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 90)
                                    .scrollContentBackground(.hidden)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(nsColor: .textBackgroundColor))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(Color.npBorder, lineWidth: 1)
                                    )
                                if appState.config.bulkInput.isEmpty {
                                    Text("Enter one URL per line:\nhttps://example1.com\nhttps://example2.com\nhttps://example3.com")
                                        .foregroundStyle(.tertiary)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(10)
                                        .allowsHitTesting(false)
                                }
                            }
                            .disabled(appState.isRunning)

                            let count = appState.config.urls.count
                            Text("\(count) URL\(count == 1 ? "" : "s") ready to scan")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 14))
                            TextField("https://example.com", text: $appState.config.url)
                                .textFieldStyle(.plain)
                                .disabled(appState.isRunning)
                                .onSubmit { if !appState.isRunning { appState.startScan() } }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.npBorder, lineWidth: 1)
                        )
                    }

                    Button {
                        if appState.isRunning { appState.stopScan() } else { appState.startScan() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: appState.isRunning ? "stop.fill" : "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                            Text(appState.isRunning ? "Stop" : "Scan")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(appState.isRunning
                                      ? AnyShapeStyle(Color.red.opacity(0.9))
                                      : AnyShapeStyle(
                                          LinearGradient(
                                              colors: [Color.npAccent, Color.npAccentLight],
                                              startPoint: .top,
                                              endPoint: .bottom
                                          )
                                      ))
                        )
                        .foregroundStyle(.white)
                        .shadow(color: appState.isRunning ? .red.opacity(0.2) : Color.npAccent.opacity(0.25), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .padding(.top, appState.config.isBulkMode ? 4 : 0)
                }

                // Scan presets
                ScanPresetPicker(config: appState.config, disabled: appState.isRunning, showSettings: $showSettings)
            }
            .padding(16)

            Divider().opacity(0.5)

            ScanProgressView(
                phase: appState.phase,
                pagesVisited: appState.pagesVisited,
                maxPages: appState.maxPages,
                domainCount: appState.domainCount,
                currentDepth: appState.currentDepth,
                domainsChecked: appState.domainsChecked,
                domainsToCheck: appState.domainsToCheck,
                progress: appState.progress,
                statusMessage: appState.statusMessage,
                pagesPerSecond: appState.pagesPerSecond,
                activityLog: appState.activityLog,
                currentScanIndex: appState.currentScanIndex,
                totalScans: appState.totalScans,
                currentScanURL: appState.currentScanURL
            )
            .animation(.easeInOut(duration: 0.3), value: appState.phase)

            if appState.phase != .idle {
                Divider().opacity(0.5).padding(.horizontal, 16)
            }

            ResultsTableView(
                results: appState.results,
                discoveredDomains: appState.discoveredDomains,
                phase: appState.phase,
                onExport: { CSVExporter.export(results: appState.results) }
            )
        }
        .frame(minWidth: 700, minHeight: 500)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showSettings.toggle()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .disabled(appState.isRunning)

                Button {
                    CSVExporter.export(results: appState.results)
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(appState.results.isEmpty)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(config: appState.config, isPresented: $showSettings)
        }
        .onKeyPress(.escape) {
            if appState.isRunning {
                appState.stopScan()
                return .handled
            }
            return .ignored
        }
    }
}

// MARK: - Scan Preset Picker

struct ScanPresetPicker: View {
    @Bindable var config: ScanConfiguration
    let disabled: Bool
    @Binding var showSettings: Bool

    @State private var hoveredPreset: ScanPreset?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ScanPreset.allCases) { preset in
                let isSelected = config.preset == preset
                let isHovered = hoveredPreset == preset

                Button {
                    if preset == .custom {
                        config.preset = .custom
                        showSettings = true
                    } else {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            config.applyPreset(preset)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: preset.icon)
                            .font(.system(size: 10))
                        Text(preset.label)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isSelected
                                  ? Color.npAccent
                                  : isHovered
                                    ? Color.primary.opacity(0.08)
                                    : Color.primary.opacity(0.04))
                    )
                    .foregroundStyle(isSelected ? .white : .secondary)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredPreset = hovering ? preset : nil
                }
            }
            Spacer()
        }
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @Bindable var config: ScanConfiguration
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scan Settings")
                    .font(.title3)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 4)

            Form {
                Section("Crawl") {
                    settingRow("Max Pages", value: $config.maxPages)
                    settingRow("Max Depth", value: $config.maxDepth)
                    settingRow("Crawl Workers", value: $config.crawlWorkers)
                    settingRow("Check Workers", value: $config.checkWorkers)
                    HStack {
                        Text("Delay (seconds)")
                        Spacer()
                        TextField("0.1", value: $config.delay, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                    }
                    settingRow("Retries", value: $config.retries)
                }

                Section("Sources") {
                    Toggle("Sitemaps & RSS", isOn: $config.useSitemaps)
                        .tint(Color.npAccent)
                    Toggle("Wayback Machine & Common Crawl", isOn: $config.useWayback)
                        .tint(Color.npAccent)
                }

                Section {
                    Toggle("JavaScript Rendering", isOn: $config.jsRenderingEnabled)
                        .tint(Color.npAccent)

                    if config.jsRenderingEnabled {
                        Picker("Render Mode", selection: $config.jsRenderMode) {
                            ForEach(JSRenderMode.allCases) { mode in
                                Label(mode.label, systemImage: mode.icon)
                                    .tag(mode)
                            }
                        }

                        Text(config.jsRenderMode.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("JavaScript")
                } footer: {
                    Text("Renders pages in a browser to discover links added by JavaScript frameworks like React, Vue, and Angular.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Section("Exclude Domains") {
                    TextField("domain1.com, domain2.com", text: $config.excludedDomains)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .onChange(of: config.maxPages) { config.preset = .custom }
            .onChange(of: config.maxDepth) { config.preset = .custom }
            .onChange(of: config.crawlWorkers) { config.preset = .custom }

            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.npAccent)
            }
            .padding()
        }
        .frame(width: 400, height: 620)
    }

    private func settingRow(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
        }
    }
}
