import Photos
import SwiftUI

struct ViewerItem: Identifiable {
    let id = UUID()
    let index: Int
}

struct ContentView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @AppStorage("columns") private var columns = 4
    @AppStorage("sortOrder") private var sortOrder = "newest"
    @State private var pinchStart: Int?
    @State private var viewer: ViewerItem?
    @State private var isSelecting = false
    @State private var selected = Set<String>()
    @State private var showAlbumPicker = false
    @State private var showCollections = false
    @State private var dragSelectStart: CGPoint?
    @State private var dragSelectCurrent: CGPoint?
    @State private var longPressScale: [String: CGFloat] = [:]
    @State private var trashBubbleVisible = false

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: columns)
    }

    private var thumbnailPixels: CGFloat {
        columns <= 2 ? 600 : (columns <= 4 ? 300 : 220)
    }

    private var selectedAssets: [PHAsset] {
        library.assets.filter { selected.contains($0.localIdentifier) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.authorized {
                    grid
                } else {
                    accessRequest
                }
            }
            .navigationTitle(isSelecting ? (selected.isEmpty ? "Sélectionner" : "\(selected.count) sélectionné(s)") : "Photos")
            .toolbar {
                toolbarContent
            }
        }
        .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
        .onAppear { library.checkAccess() }
        .onChange(of: sortOrder) { _, _ in library.reload() }
        .onChange(of: library.changeToken) { _, _ in
            let ids = Set(library.assets.map { $0.localIdentifier })
            selected = selected.filter { ids.contains($0) }
        }
        .fullScreenCover(item: $viewer) { item in
            PhotoViewer(assets: library.assets, library: library, startIndex: item.index)
        }
        .sheet(isPresented: $showAlbumPicker) {
            AlbumPicker(library: library, assets: selectedAssets) {
                finishSelection()
            }
        }
        .sheet(isPresented: $showCollections) {
            CollectionsView(library: library)
        }
        .overlay(alignment: .bottomTrailing) {
            if trashBubbleVisible {
                deleteBubble
                    .transition(.scale.combined(with: .opacity))
                    .padding(.trailing, 20)
                    .padding(.bottom, 70)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if library.authorized {
            ToolbarItem(placement: .topBarLeading) {
                if !isSelecting {
                    Button { showCollections = true } label: {
                        Image(systemName: "rectangle.stack").accessibilityLabel("Collections")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !isSelecting {
                    Menu {
                        Picker("Trier", selection: $sortOrder) {
                            Text("Plus récentes d'abord").tag("newest")
                            Text("Plus anciennes d'abord").tag("oldest")
                            Text("Modifiées récemment").tag("modified")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down").accessibilityLabel("Trier")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isSelecting {
                    Button { finishSelection() } label: {
                        Image(systemName: "xmark").accessibilityLabel("Fermer")
                    }
                } else {
                    Button("Sélectionner") { isSelecting = true }
                }
            }
        }
        if isSelecting {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { copySelected() } label: {
                    Image(systemName: "doc.on.doc").accessibilityLabel("Copier")
                }
                .disabled(selected.isEmpty)

                Button { duplicateSelected() } label: {
                    Image(systemName: "plus.square.on.square").accessibilityLabel("Dupliquer")
                }
                .disabled(selected.isEmpty)

                Button { hideSelected() } label: {
                    Image(systemName: "eye.slash").accessibilityLabel("Masquer")
                }
                .disabled(selected.isEmpty)

                Button { showAlbumPicker = true } label: {
                    Image(systemName: "rectangle.stack.badge.plus").accessibilityLabel("Ajouter à un album")
                }
                .disabled(selected.isEmpty)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        trashBubbleVisible = true
                    }
                } label: {
                    Image(systemName: "trash").accessibilityLabel("Supprimer")
                }
                .tint(.red)
                .disabled(selected.isEmpty)
            }
        }
    }

    private var deleteBubble: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    withAnimation { trashBubbleVisible = false }
                } label: {
                    Text("Annuler")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }

                Button {
                    withAnimation { trashBubbleVisible = false }
                    Haptics.medium()
                    library.trash(selectedAssets) { finishSelection() }
                } label: {
                    Text("Supprimer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            // Petite flèche vers la poubelle
            Image(systemName: "arrowtriangle.down.fill")
                .font(.caption)
                .foregroundStyle(.ultraThinMaterial)
                .offset(x: -8, y: -2)
        }
    }

    private var grid: some View {
        GeometryReader { geo in
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 2) {
                    ForEach(Array(library.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                        let id = asset.localIdentifier
                        ThumbnailView(
                            asset: asset,
                            targetPixels: thumbnailPixels,
                            isSelecting: isSelecting,
                            isSelected: selected.contains(id)
                        )
                        .scaleEffect(longPressScale[id] ?? 1)
                        .onTapGesture {
                            if isSelecting {
                                toggle(asset)
                            } else {
                                viewer = ViewerItem(index: index)
                            }
                        }
                        .onLongPressGesture(minimumDuration: 0.4, pressing: { pressing in
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                                longPressScale[id] = pressing ? 1.12 : 1.0
                            }
                        }) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                longPressScale[id] = 1.0
                                if !isSelecting {
                                    isSelecting = true
                                }
                                selected.insert(id)
                            }
                            // Retour haptique léger
                            Haptics.medium()
                        }
                        .background(
                            GeometryReader { cellGeo in
                                Color.clear
                                    .preference(
                                        key: CellFrameKey.self,
                                        value: [id: cellGeo.frame(in: .named("grid"))]
                                    )
                            }
                        )
                    }
                }
                .coordinateSpace(name: "grid")
                .onPreferenceChange(CellFrameKey.self) { frames in
                    cellFrames = frames
                }
            }
            .gesture(dragSelectGesture, including: isSelecting ? .all : .none)
        }
        .gesture(pinchGesture)
        .sensoryFeedback(trigger: selected.count) { _, _ in
            Haptics.enabled ? .selection : nil
        }
        .refreshable {
            // Pas d'actualisation pendant la sélection
            guard !isSelecting else { return }
            library.reload()
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    @State private var cellFrames: [String: CGRect] = [:]

    // Sélection par glissement (comme dans Photos / la vidéo)
    private var dragSelectGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragSelectStart == nil {
                    dragSelectStart = value.startLocation
                }
                dragSelectCurrent = value.location
                updateDragSelection()
            }
            .onEnded { _ in
                dragSelectStart = nil
                dragSelectCurrent = nil
            }
    }

    private func updateDragSelection() {
        guard let start = dragSelectStart, let current = dragSelectCurrent else { return }
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        for (id, frame) in cellFrames {
            if frame.intersects(rect) {
                selected.insert(id)
            }
        }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if pinchStart == nil { pinchStart = columns }
                let base = pinchStart ?? columns
                let newCount = Int((Double(base) / Double(scale)).rounded())
                columns = min(max(newCount, 1), 8)
            }
            .onEnded { _ in
                pinchStart = nil
            }
    }

    private var accessRequest: some View {
        VStack(spacing: 16) {
            Text("HoloPhotos a besoin d'accéder à tes photos et vidéos.")
                .multilineTextAlignment(.center)
            Button("Autoriser l'accès") {
                library.requestAccess()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func toggle(_ asset: PHAsset) {
        if selected.contains(asset.localIdentifier) {
            selected.remove(asset.localIdentifier)
        } else {
            selected.insert(asset.localIdentifier)
        }
    }

    private func finishSelection() {
        selected.removeAll()
        isSelecting = false
        trashBubbleVisible = false
    }

    private func copySelected() {
        library.loadImages(selectedAssets) { images in
            UIPasteboard.general.images = images
        }
    }

    private func duplicateSelected() {
        library.duplicate(selectedAssets) { finishSelection() }
    }

    private func hideSelected() {
        library.hide(selectedAssets) { finishSelection() }
    }
}

private struct CellFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct AlbumPicker: View {
    @ObservedObject var library: PhotoLibrary
    let assets: [PHAsset]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showNewAlbum = false
    @State private var newAlbumName = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    showNewAlbum = true
                } label: {
                    Label("Nouvel album", systemImage: "plus")
                }

                ForEach(library.albums, id: \.localIdentifier) { album in
                    Button(album.localizedTitle ?? "Album") {
                        library.add(assets, to: album) {
                            dismiss()
                            onDone()
                        }
                    }
                }
            }
            .navigationTitle("Ajouter à un album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .alert("Nouvel album", isPresented: $showNewAlbum) {
                TextField("Nom de l'album", text: $newAlbumName)
                Button("Créer") {
                    library.createAlbum(named: newAlbumName, adding: assets) {
                        dismiss()
                        onDone()
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }
}
