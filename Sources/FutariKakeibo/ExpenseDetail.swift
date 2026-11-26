import FutariDomain
import PhotosUI
import SwiftUI
import UIKit

@MainActor
struct ExpenseDetail: View {
    @ObservedObject var ledger: CloudLedger
    let book: Book
    let expenseID: UUID

    @State private var receipts: Set<Data> = []
    @State private var receiptLoaded = false
    @State private var selection: PhotosPickerItem?
    @State private var showPhoto = false
    @State private var viewedPhoto: Data?
    @State private var confirmDelete = false
    @State private var deleteCandidate: Set<Data>?
    @State private var failure: String?

    var body: some View {
        Group {
            if let snapshot = ledger.snapshot, snapshot.book == book,
               let expense = snapshot.expenses.first(where: { $0.id == expenseID }) {
                List {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(expense.label ?? snapshot.title(for: expense.category))
                        Text(expense.amount.yen)
                            .accessibilityLabel(expense.spokenAmount(names: snapshot.names))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    LabeledContent("日付", value: expense.date.formatted(japaneseDate.year().month().day()))
                    Text(expense.payerCaption(names: snapshot.names)).accessibilityHidden(true)
                    receiptSection(canEdit: snapshot.member != nil && !ledger.shareBusy)
                }
                .task(id: snapshot.revision) { loadReceipt() }
                .task(id: selection) {
                    if let selection { await importPhoto(selection) }
                }
            } else {
                Text("この支出を開けません")
            }
        }
        .navigationTitle("支出の詳細")
        .navigationBarTitleDisplayMode(.inline)
        .alert(deleteCandidate?.count ?? 0 > 1 ? "レシート写真をすべて削除しますか？" : "レシート写真を削除しますか？",
               isPresented: $confirmDelete) {
            Button("削除", role: .destructive) {
                if let deleteCandidate { save(nil, replacing: deleteCandidate) }
                deleteCandidate = nil
            }
            Button("キャンセル", role: .cancel) { deleteCandidate = nil }
        }
        .alert("レシート写真", isPresented: Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        .fullScreenCover(isPresented: $showPhoto) {
            if let viewedPhoto, let image = UIImage(data: viewedPhoto) {
                ReceiptViewer(image: image)
            }
        }
    }

    private func receiptSection(canEdit: Bool) -> some View {
        Section("レシート写真") {
            if receipts.count > 1 {
                Text("写真が同時に追加されました。確認して1枚に差し替えてください")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(receipts), id: \.self) { photo in
                if let image = UIImage(data: photo) {
                    Button {
                        viewedPhoto = photo
                        showPhoto = true
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .accessibilityLabel("レシート写真を拡大")
                    }
                    .buttonStyle(.borderless)
                } else {
                    Text("写真を表示できません").foregroundStyle(.secondary)
                }
            }
            if selection != nil {
                ProgressView("写真を読み込み中").frame(minHeight: 44)
            } else if !receiptLoaded {
                Button("写真を再読み込み", action: loadReceipt).frame(minHeight: 44)
            } else if canEdit {
                PhotosPicker(selection: $selection, matching: .images) {
                    Label(receipts.isEmpty ? "写真を追加" : "写真を差し替え", systemImage: "photo")
                        .frame(minHeight: 44)
                }
                if !receipts.isEmpty {
                    Button(receipts.count > 1 ? "写真をすべて削除" : "写真を削除", role: .destructive) {
                        deleteCandidate = receipts
                        confirmDelete = true
                    }
                    .frame(minHeight: 44)
                }
            } else if receipts.isEmpty {
                Text("写真がありません。追加するには共有の設定を確認してください")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadReceipt() {
        do {
            receipts = try ledger.receipts(for: expenseID, in: book)
            receiptLoaded = true
        } catch {
            receiptLoaded = false
            failure = "写真を取得できませんでした。"
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { if !Task.isCancelled && selection == item { selection = nil } }
        let previous = receipts
        do {
            let photo = try await item.loadTransferable(type: ReceiptPhoto.self)
            guard !Task.isCancelled, selection == item else { return }
            guard let photo else { throw ReceiptPhotoError.unreadable }
            save(photo, replacing: previous)
        } catch {
            guard !Task.isCancelled, selection == item else { return }
            failure = (error as? ReceiptPhotoError)?.errorDescription ?? "写真を読み込めませんでした。"
        }
    }

    private func save(_ photo: ReceiptPhoto?, replacing previous: Set<Data>) {
        do {
            try ledger.setReceipt(photo, replacing: previous, for: expenseID, in: book)
            receipts = photo.map { [$0.jpeg] } ?? []
        } catch ReceiptPhotoError.changed {
            loadReceipt()
            failure = "相手の変更が反映されました。写真を確認してからやり直してください"
        } catch {
            failure = "写真の変更を保存できませんでした。"
        }
    }
}

private struct ReceiptViewer: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    @State private var zoom: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let fit = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: image.size.width * fit * zoom, height: image.size.height * fit * zoom)
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                        .accessibilityLabel("レシート写真")
                }
                .defaultScrollAnchor(.center)
            }
            .navigationTitle("レシート写真")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(zoom == 1 ? "拡大" : "全体") { zoom = zoom == 1 ? 3 : 1 }
                }
            }
        }
    }
}
