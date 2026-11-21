import AppKit
import AVKit
import PetCore
import PetAssets
let app=NSApplication.shared
app.setActivationPolicy(.prohibited)
func descendants(_ view:NSView)->[NSView] { view.subviews.flatMap { [$0]+descendants($0) } }
func snapshot(_ view:NSView, name:String) throws {
    view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
    let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
    view.cacheDisplay(in:view.bounds,to:bitmap)
    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:".build/message-windows-smoke/\(name).png"))
}
precondition(MessageArtwork.polaroid != nil && AppTypography.postScriptName != nil,"Bundle the actual frame and project font")
let body=RichMessageBody(runs:[RichTextRun(text:"Hello",bold:true),RichTextRun(text:" 🌿\n",italic:true,underline:true)])
let converted=MessageRichText.body(from:MessageRichText.attributed(from:body))
precondition(converted==body)
let composer=MessageComposerWindow()
var sends=0,closes=0,stops=0
composer.onSend={ text,url in precondition(MessageRichText.body(from:text)==body && url==nil); sends+=1 }
composer.onClose={ closes+=1 }; composer.onStopCamera={ stops+=1 }
composer.setDraft(text:MessageRichText.attributed(from:body),attachmentURL:nil)
composer.show(); composer.window.contentView!.layoutSubtreeIfNeeded()
precondition(composer.window.styleMask.contains(.resizable) && composer.window.parent == nil && composer.window.canBecomeKey)
let paper=composer.window.contentView as! PolaroidCanvas
let writing=descendants(paper).compactMap { $0 as? NSScrollView }.first!
precondition(writing.frame==paper.writingRect && writing.frame.minY>paper.mediaRect.maxY,"Writing belongs on the lower paper lip")
for width:CGFloat in [420,500,650] {
    composer.window.setContentSize(NSSize(width:width,height:width*1384/1140))
    paper.layoutSubtreeIfNeeded()
    precondition(paper.bounds.contains(writing.frame) && writing.frame==paper.writingRect)
    precondition(descendants(paper).compactMap { $0 as? NSButton }.allSatisfy { paper.bounds.contains(paper.convert($0.bounds,from:$0)) })
}
composer.window.setContentSize(PolaroidStyle.size); paper.layoutSubtreeIfNeeded()
composer.setCameraDevices([("built-in","FaceTime camera"),("continuity","iPhone camera")],selectedID:"built-in")
composer.setCameraPreviewActive(true,ready:true)
try snapshot(paper,name:"polaroid-camera")
composer.setCameraPreviewActive(false)
let buttons=descendants(composer.window.contentView!).compactMap { $0 as? NSButton }
let send=buttons.first { $0.title=="Send" }!, capture=buttons.first { $0.title=="Capture" }!
precondition(sends==0 && composer.hasDraft && send.isEnabled)
composer.setStatus("Saving…",isBusy:true); precondition(!send.isEnabled)
composer.setStatus("Ready"); send.performClick(nil); precondition(sends==1)
composer.setCameraPreviewActive(true,ready:true); precondition(capture.isEnabled && !send.isEnabled && !composer.cameraPreviewHost.isHidden)
composer.setStatus("Saving…",isBusy:true); precondition(!capture.isEnabled)
composer.setStatus("Ready"); composer.setAttachment(nil); precondition(stops==1 && send.isEnabled)
let editor=descendants(paper).compactMap { $0 as? NSTextView }.first!
editor.setSelectedRange(NSRange(location:0,length:5))
let bold=buttons.first { $0.title=="B" }!
bold.performClick(nil)
precondition(!MessageRichText.body(from:composer.draftText).runs.first!.bold)
bold.performClick(nil)
precondition(MessageRichText.body(from:composer.draftText)==body,"Project lettering must retain bold, italic and underline")
precondition((editor.attributedString().attribute(.font,at:0,effectiveRange:nil) as? NSFont)?.fontName == AppTypography.font(size:18).fontName)
composer.window.close(); precondition(closes==1 && sends==1)
let now=Date()
let message=ChatMessage(id:"one",pairID:"pair",senderID:"peer",recipientID:"self",clientRequestID:"request",body:body,attachment:nil,createdAt:now)
let inbox=MessageInboxWindow(currentDeviceID:"self")
var presented:[String]=[]
inbox.onPresented={ presented.append($0.id) }
inbox.show(messages:[message]); inbox.window.contentView!.layoutSubtreeIfNeeded()
RunLoop.main.run(until:Date().addingTimeInterval(0.05))
precondition(presented==["one"])
inbox.window.close()
print("PASS message windows: rich text roundtrip, explicit Send, busy controls, camera capture controls, preserved draft on close, and shown text read callback")
let attachment=ChatAttachment(id:UUID().uuidString,mediaType:"image/png",byteCount:68,sha256:String(repeating:"a",count:64),createdAt:now)
let photo=ChatMessage(id:"photo",pairID:"pair",senderID:"peer",recipientID:"self",clientRequestID:"photo-request",body:RichMessageBody(text:"Photo"),attachment:attachment,createdAt:now)
var needs=0
inbox.onAttachmentNeeded={ message in precondition(message.id=="photo"); needs+=1 }
inbox.show(messages:[photo]); RunLoop.main.run(until:Date().addingTimeInterval(0.02))
let keep=descendants(inbox.window.contentView!).compactMap { $0 as? NSButton }.first { $0.title=="Keep" }!
precondition(!keep.isEnabled,"Do not keep a card before its attachment has loaded")
precondition(presented==["one"] && needs==1,"Metadata must not count as reading a photo")
inbox.setAttachment(URL(fileURLWithPath:"/missing-photo-file"),for:"photo")
RunLoop.main.run(until:Date().addingTimeInterval(0.02)); precondition(presented==["one"],"Failed photos stay unread")
let imageURL=URL(fileURLWithPath:".build/message-windows-smoke/photo.png")
let image=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
try image.representation(using:.png,properties:[:])!.write(to:imageURL)
inbox.setAttachment(imageURL,for:"photo"); inbox.window.close()
RunLoop.main.run(until:Date().addingTimeInterval(0.02)); precondition(presented==["one"],"Closing invalidates queued receipt")
inbox.show(messages:[photo]); inbox.setAttachment(imageURL,for:"photo")
RunLoop.main.run(until:Date().addingTimeInterval(0.02)); precondition(presented==["one","photo"])
var kept=0
inbox.onKeep={ kept+=1 }
precondition(keep.isEnabled && inbox.window.parent==nil)
keep.performClick(nil)
precondition(kept==1 && inbox.isKept && inbox.window.isVisible && keep.isHidden,"Keep retains an independent visible Polaroid")
let other=MessageInboxWindow(currentDeviceID:"self")
other.show(messages:[message]); other.window.close()
precondition(inbox.window.isVisible,"Opening/closing another viewer must not dismiss a kept card")
inbox.window.setContentSize(NSSize(width:600,height:600*1384/1140))
inbox.window.contentView!.layoutSubtreeIfNeeded()
try snapshot(inbox.window.contentView!,name:"polaroid-kept")
inbox.window.close()
print("PASS viewer: failed media stays unread, displayed photo marks read, Keep retains an independent resizable Polaroid, and Close dismisses it")
let videoURL=URL(fileURLWithPath:"Tests/Fixtures/message-video.mp4")
let videoAttachment=ChatAttachment(id:UUID().uuidString,mediaType:"video/mp4",byteCount:100,sha256:String(repeating:"0",count:64),createdAt:now)
let videoMessage=ChatMessage(id:"video",pairID:"pair",senderID:"peer",recipientID:"self",clientRequestID:"video-request",body:body,attachment:videoAttachment,createdAt:now)
inbox.onAttachmentNeeded={ message in precondition(message.id == "video") }
inbox.show(messages:[videoMessage]); inbox.setAttachment(videoURL,for:"video")
let deadline=Date().addingTimeInterval(5)
while !presented.contains("video") && Date()<deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.05)) }
if !presented.contains("video") {
    let error=inbox.lastMediaError as NSError?
    let underlying=error?.userInfo[NSUnderlyingErrorKey] as? NSError
    precondition(underlying?.domain == NSOSStatusErrorDomain && underlying?.code == -12911,
                 "Unexpected video load failure: \(String(describing:error))")
    print("SKIP positive video playback: native VideoToolbox decoder returned -12911 in this environment; failed video correctly stays unread. Verify playback from the desktop app.")
} else { print("PASS viewer: cached MP4 prepares successfully and emits read only after media is ready") }
inbox.window.close()
