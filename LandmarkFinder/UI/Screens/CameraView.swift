import SwiftUI
import PhotosUI

struct CameraView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var vm = CameraViewModel()
    @State private var pickerItem: PhotosPickerItem?

    // For feedback UI
    @State private var wrongLabelInput: String = ""
    @State private var feedbackComment: String = ""
    @State private var showWrongSheet: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewView(session: vm.session)
                .ignoresSafeArea()

            if vm.isLoading {
                VStack {
                    LoadingOverlay(text: "Recognizing...")
                        .padding(.top, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }

            VStack(spacing: 10) {
                Text(vm.statusText)
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let banner = vm.feedbackStatus {
                    Text(banner)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if vm.isUnknown {
                        Text("Unknown / Not sure")
                            .font(.title3)
                            .bold()
                            .foregroundStyle(.yellow)
                    } else if !vm.predictions.isEmpty {
                        Text("Top predictions")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(vm.predictions) { p in
                        HStack {
                            Text(p.label)
                            Spacer()
                            Text(String(format: "%.0f%%", p.confidence * 100))
                                .monospacedDigit()
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 12)

                // Feedback controls
                if let predictionId = vm.predictionId, !predictionId.isEmpty {
                    VStack(spacing: 8) {
                        HStack {
                            Button {
                                let top1 = vm.predictions.first?.label
                                vm.sendFeedback(isCorrect: true, selectedLabel: top1, comment: feedbackComment.isEmpty ? nil : feedbackComment)
                                feedbackComment = ""
                            } label: {
                                Label(vm.hasSentFeedback ? "Sent" : "Correct", systemImage: vm.hasSentFeedback ? "checkmark.circle" : "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(vm.isSendingFeedback || vm.hasSentFeedback)

                            Button {
                                showWrongSheet = true
                            } label: {
                                Label("Wrong", systemImage: "xmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(vm.isSendingFeedback || vm.hasSentFeedback)
                        }

                        TextField("Optional comment (for both)", text: $feedbackComment, axis: .vertical)
                            .lineLimit(1...3)
                            .textInputAutocapitalization(.sentences)
                            .padding(8)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .disabled(vm.isSendingFeedback || vm.hasSentFeedback)
                    }
                    .padding(.horizontal, 12)
                }

                HStack {
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Pick Photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .onChange(of: pickerItem) { _, newValue in
                        guard let item = newValue else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                vm.submit(image: image)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
        .onAppear {
            vm.onAuthFailure = { Task { await env.logout() } }
            vm.start()
        }
        .onDisappear { vm.stop() }
        .animation(.easeInOut, value: vm.isLoading)
        .animation(.easeInOut, value: vm.feedbackStatus)
        .sheet(isPresented: $showWrongSheet) {
            NavigationStack {
                Form {
                    Section("Correct landmark") {
                        TextField("Type the correct landmark", text: $wrongLabelInput)
                            .textInputAutocapitalization(.words)
                    }
                    Section("Optional comment") {
                        TextField("Add details (optional)", text: $feedbackComment, axis: .vertical)
                            .lineLimit(1...4)
                    }
                }
                .navigationTitle("Wrong prediction")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showWrongSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            let label = wrongLabelInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            vm.sendFeedback(isCorrect: false, selectedLabel: label.isEmpty ? nil : label, comment: feedbackComment.isEmpty ? nil : feedbackComment)
                            wrongLabelInput = ""
                            feedbackComment = ""
                            showWrongSheet = false
                        }
                        .disabled(vm.isSendingFeedback || vm.hasSentFeedback)
                    }
                }
            }
        }
    }
}

