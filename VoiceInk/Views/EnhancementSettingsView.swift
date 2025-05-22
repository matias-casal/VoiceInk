import SwiftUI

extension CustomPrompt {
    func promptIcon(isSelected: Bool, onTap: @escaping () -> Void, onEdit: ((CustomPrompt) -> Void)? = nil, onDelete: ((CustomPrompt) -> Void)? = nil) -> some View {
        VStack(spacing: 8) {
            ZStack {
                // Dynamic background with blur effect
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            gradient: isSelected ?
                                Gradient(colors: [
                                    Color.accentColor.opacity(0.9),
                                    Color.accentColor.opacity(0.7)
                                ]) :
                                Gradient(colors: [
                                    Color(NSColor.controlBackgroundColor).opacity(0.95),
                                    Color(NSColor.controlBackgroundColor).opacity(0.85)
                                ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        isSelected ?
                                            Color.white.opacity(0.3) : Color.white.opacity(0.15),
                                        isSelected ?
                                            Color.white.opacity(0.1) : Color.white.opacity(0.05)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: isSelected ?
                            Color.accentColor.opacity(0.4) : Color.black.opacity(0.1),
                        radius: isSelected ? 10 : 6,
                        x: 0,
                        y: 3
                    )
                
                // Decorative background elements
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                isSelected ?
                                    Color.white.opacity(0.15) : Color.white.opacity(0.08),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 1,
                            endRadius: 25
                        )
                    )
                    .frame(width: 50, height: 50)
                    .offset(x: -15, y: -15)
                    .blur(radius: 2)
                
                // Icon with enhanced effects
                Image(systemName: icon.rawValue)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isSelected ?
                                [Color.white, Color.white.opacity(0.9)] :
                                [Color.primary.opacity(0.9), Color.primary.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: isSelected ?
                            Color.white.opacity(0.5) : Color.clear,
                        radius: 4
                    )
                    .shadow(
                        color: isSelected ?
                            Color.accentColor.opacity(0.5) : Color.clear,
                        radius: 3
                    )
            }
            .frame(width: 48, height: 48)
            
            // Enhanced title styling
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ?
                    .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: 70)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .onTapGesture(perform: onTap)
        .contextMenu {
            if !isPredefined && (onEdit != nil || onDelete != nil) {
                if let onEdit = onEdit {
                    Button {
                        onEdit(self)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
                
                if let onDelete = onDelete {
                    Button(role: .destructive) {
                        onDelete(self)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }
}

struct EnhancementSettingsView: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @State private var isEditingPrompt = false
    @State private var isSettingsExpanded = true
    @State private var selectedPromptForEdit: CustomPrompt?
    @State private var isEditingTriggerWord = false
    @State private var tempTriggerWord = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Main Settings Sections
                VStack(spacing: 24) {
                    // Enable/Disable Toggle Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Enable Enhancement")
                                        .font(.headline)
                                    
                                    InfoTip(
                                        title: "AI Enhancement",
                                        message: "AI enhancement lets you pass the transcribed audio through LLMS to post-process using different prompts suitable for different use cases like e-mails, summary, writing, etc.",
                                        learnMoreURL: "https://www.youtube.com/@tryvoiceink/videos"
                                    )
                                }
                                
                                Text("Turn on AI-powered enhancement features")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $enhancementService.isEnhancementEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                                .labelsHidden()
                                .scaleEffect(1.2)
                        }
                        
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Clipboard Context", isOn: $enhancementService.useClipboardContext)
                                    .toggleStyle(.switch)
                                    .disabled(!enhancementService.isEnhancementEnabled)
                                Text("Use text from clipboard to understand the context")
                                    .font(.caption)
                                    .foregroundColor(enhancementService.isEnhancementEnabled ? .secondary : .secondary.opacity(0.5))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Screen Capture", isOn: $enhancementService.useScreenCaptureContext)
                                    .toggleStyle(.switch)
                                    .disabled(!enhancementService.isEnhancementEnabled)
                                Text("Learn what is on the screen to understand the context")
                                    .font(.caption)
                                    .foregroundColor(enhancementService.isEnhancementEnabled ? .secondary : .secondary.opacity(0.5))
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.windowBackgroundColor).opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    )
                    
                    // 1. AI Provider Integration Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("AI Provider Integration")
                            .font(.headline)
                        
                        APIKeyManagementView()
                            .background(Color(.windowBackgroundColor).opacity(0.4))
                            .cornerRadius(10)
                    }
                    .padding()
                    .background(Color(.windowBackgroundColor).opacity(0.4))
                    .cornerRadius(10)
                    
                    // 3. Enhancement Modes & Assistant Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Enhancement Modes & Assistant")
                            .font(.headline)
                        
                        // Modes Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Enhancement Modes")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Button(action: { isEditingPrompt = true }) {
                                    Image(systemName: "plus.circle.fill")
                                        .symbolRenderingMode(.hierarchical)
                                        .font(.system(size: 26, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Circle())
                                .help("Add new mode")
                            }
                            
                            if enhancementService.allPrompts.isEmpty {
                                Text("No modes available")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            } else {
                                let columns = [
                                    GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 36)
                                ]
                                
                                LazyVGrid(columns: columns, spacing: 24) {
                                    ForEach(enhancementService.allPrompts) { prompt in
                                        prompt.promptIcon(
                                            isSelected: enhancementService.selectedPromptId == prompt.id,
                                            onTap: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                enhancementService.setActivePrompt(prompt)
                                            }},
                                            onEdit: { selectedPromptForEdit = $0 },
                                            onDelete: { enhancementService.deletePrompt($0) }
                                        )
                                    }
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            }
                        }
                        
                        Divider()
                        
                        // Assistant Mode Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Assistant Mode")
                                    .font(.subheadline)
                                Image(systemName: "sparkles")
                                    .foregroundColor(.accentColor)
                            }
                            
                            Text("Configure how to trigger the AI assistant mode")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Current Trigger:")
                                        .font(.subheadline)
                                    Text("\"\(enhancementService.assistantTriggerWord)\"")
                                        .font(.system(.subheadline, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                }
                                
                                if isEditingTriggerWord {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            TextField("New trigger word", text: $tempTriggerWord)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(maxWidth: 200)
                                            
                                            Button("Save") {
                                                enhancementService.assistantTriggerWord = tempTriggerWord
                                                isEditingTriggerWord = false
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(tempTriggerWord.isEmpty)
                                            
                                            Button("Cancel") {
                                                isEditingTriggerWord = false
                                                tempTriggerWord = enhancementService.assistantTriggerWord
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                        
                                        Text("Default: \"hey\"")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Button("Change Trigger Word") {
                                        tempTriggerWord = enhancementService.assistantTriggerWord
                                        isEditingTriggerWord = true
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            
                            Text("Start with \"\(enhancementService.assistantTriggerWord), \" to use AI assistant mode")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Instead of enhancing the text, VoiceInk will respond like a conversational AI assistant")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.windowBackgroundColor).opacity(0.4))
                    .cornerRadius(10)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $isEditingPrompt) {
            PromptEditorView(mode: .add)
        }
        .sheet(item: $selectedPromptForEdit) { prompt in
            PromptEditorView(mode: .edit(prompt))
        }
    }
}
