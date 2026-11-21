import AppKit
import PetCore

@MainActor
final class MessageOutboxWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:540,height:350),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
    var onRetry: (() -> Void)?
    var onRemove: ((String) -> Void)?
    var onConnection: (() -> Void)?
    private let table=NSTableView()
    private let status=NSTextField(wrappingLabelWithString:"")
    private let remove=NSButton(title:"Remove from Outbox…",target:nil,action:nil)
    private var entries: [OutgoingMessage]=[]
    override init() {
        super.init(); window.title="Message Outbox"; window.isReleasedWhenClosed=false
        window.minSize=NSSize(width:440,height:300)
        let root=NSStackView(); root.orientation = .vertical; root.spacing=12
        root.translatesAutoresizingMaskIntoConstraints=false; window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:20),
            root.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-20),
            root.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:20),
            root.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-20)])
        status.font = .systemFont(ofSize:12); root.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("message")); column.title="Waiting to send"; column.width=450
        table.addTableColumn(column); table.delegate=self; table.dataSource=self; table.rowHeight=32
        table.setAccessibilityLabel("Queued messages")
        let scroll=NSScrollView(); scroll.documentView=table; scroll.hasVerticalScroller=true
        root.addArrangedSubview(scroll)
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalTo:root.widthAnchor),scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:120)])
        let retry=NSButton(title:"Retry Now",target:self,action:#selector(retryNow)); retry.bezelStyle = .rounded
        remove.target=self; remove.action=#selector(removeSelected); remove.bezelStyle = .rounded
        let connection=NSButton(title:"Connection…",target:self,action:#selector(connectionSettings)); connection.bezelStyle = .rounded
        root.addArrangedSubview(NSStackView(views:[retry,remove,connection]))
        remove.isEnabled=false
    }
    func show() { window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    func update(entries: [OutgoingMessage], status: String) {
        let selected=table.selectedRow>=0 && table.selectedRow<self.entries.count ? self.entries[table.selectedRow].id : nil
        self.entries=entries; self.status.stringValue=entries.isEmpty ? "No queued messages. \(status)" : "\(entries.count) waiting. \(status)"
        table.reloadData()
        if let selected, let row=entries.firstIndex(where:{ $0.id == selected }) { table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false) }
        remove.isEnabled=table.selectedRow>=0 && table.selectedRow<entries.count
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let entry=entries[row]
        let preview=entry.body.plainText.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"\n",with:" ")
        let prefix=entry.localAttachmentName == nil ? "" : "📎 "
        let label=NSTextField(labelWithString:prefix+(preview.isEmpty ? "Attachment" : String(preview.prefix(100))))
        label.lineBreakMode = .byTruncatingTail; return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) { remove.isEnabled=entries.indices.contains(table.selectedRow) }
    @objc private func retryNow() { onRetry?() }
    @objc private func connectionSettings() { onConnection?() }
    @objc private func removeSelected() {
        guard entries.indices.contains(table.selectedRow) else { return }
        let id=entries[table.selectedRow].id
        let alert=NSAlert(); alert.messageText="Remove this queued message?"
        alert.informativeText="It will stop retrying. If the server already accepted it before the connection failed, the recipient may still receive it."
        alert.addButton(withTitle:"Remove"); alert.addButton(withTitle:"Cancel")
        alert.beginSheetModal(for:window) { [weak self] response in
            if response == .alertFirstButtonReturn { MainActor.assumeIsolated { self?.onRemove?(id) } }
        }
    }
}
