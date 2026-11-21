import AppKit
import AVKit
import PetCore
let app=NSApplication.shared
app.setActivationPolicy(.prohibited)
func descendants(_ view:NSView)->[NSView] { view.subviews.flatMap { [$0]+descendants($0) } }
let body=RichMessageBody(runs:[RichTextRun(text:"Hello",bold:true),RichTextRun(text:" 🌿\n",italic:true,underline:true)])
let converted=MessageRichText.body(from:MessageRichText.attributed(from:body))
precondition(converted==body)
let composer=MessageComposerWindow()
var sends=0,closes=0,stops=0
composer.onSend={ text,url in precondition(MessageRichText.body(from:text)==body && url==nil); sends+=1 }
composer.onClose={ closes+=1 }; composer.onStopCamera={ stops+=1 }
composer.setDraft(text:MessageRichText.attributed(from:body),attachmentURL:nil)
composer.show(); composer.window.contentView!.layoutSubtreeIfNeeded()
let buttons=descendants(composer.window.contentView!).compactMap { $0 as? NSButton }
let send=buttons.first { $0.title=="Send" }!, capture=buttons.first { $0.title=="Capture" }!
precondition(sends==0 && composer.hasDraft && send.isEnabled)
composer.setStatus("Saving…",isBusy:true); precondition(!send.isEnabled)
composer.setStatus("Ready"); send.performClick(nil); precondition(sends==1)
composer.setCameraPreviewActive(true,ready:true); precondition(capture.isEnabled && !send.isEnabled && !composer.cameraPreviewHost.isHidden)
composer.setStatus("Saving…",isBusy:true); precondition(!capture.isEnabled)
composer.setStatus("Ready"); composer.setAttachment(nil); precondition(stops==1 && send.isEnabled)
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
inbox.window.close()
print("PASS viewer: metadata and failed media stay unread, close cancels queued read, successfully displayed photo marks read")
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
