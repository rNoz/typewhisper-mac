import SwiftUI

struct PluginSettingsView: View {
    @ObservedObject private var pluginManager = PluginManager.shared

    var body: some View {
        Form {
            if pluginManager.loadedPlugins.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Text(String(localized: "No plugins installed."))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Place .bundle plugins in the Plugins folder to install them."))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }
            } else {
                Section(String(localized: "Plugins")) {
                    ForEach(pluginManager.loadedPlugins) { plugin in
                        PluginRow(plugin: plugin)
                    }
                }
            }

            Section {
                HStack {
                    Button(String(localized: "Open Plugins Folder")) {
                        pluginManager.openPluginsFolder()
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 500, minHeight: 300)
    }
}

private struct PluginRow: View {
    let plugin: LoadedPlugin
    @State private var showSettings = false

    var body: some View {
        HStack {
            Image(systemName: "puzzlepiece.extension")
                .font(.title2)
                .foregroundStyle(.purple)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.manifest.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text("v\(plugin.manifest.version)")
                    if let author = plugin.manifest.author {
                        Text(author)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if plugin.instance.settingsView != nil {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
            }

            Toggle("", isOn: Binding(
                get: { plugin.isEnabled },
                set: { enabled in
                    PluginManager.shared.setPluginEnabled(plugin.id, enabled: enabled)
                }
            ))
            .labelsHidden()
        }
        .sheet(isPresented: $showSettings) {
            if let view = plugin.instance.settingsView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(plugin.manifest.name)
                            .font(.headline)
                        Spacer()
                        Button {
                            showSettings = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding()

                    Divider()

                    view
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(minWidth: 500, minHeight: 400)
            }
        }
    }
}
