# VideoToolbox HEVC Encoder Sample Code

Sample code that capture and encode video into HEVC (or H.264) with AVFoundation and VideoToolbox. The code is in Swift 5 and tested on XCode 11.5 / iOS 11.2.1 / iPhone X.

Based on [tomisacat's VideoToolboxCompression project](https://github.com/tomisacat/VideoToolboxCompression).

Brief instructions:
 1. Build and run on iPhone 7/7 Plus or up. Touch **Click Me** to begin recording. Touch again to finish.
 2. Download the result to Mac: XCode -> Window -> Devices and Simulators -> Select app and click the "gear" icon below -> Download Container.
 3. Among the container files, `tmp/temp.h265` is the raw HEVC data file.
 4. Add a container around the file: `mp4box -add temp.h265 temp.h265.mp4`
 5. Use QuickTime or VLC to play the mp4 file.
 6. For comparison, you could change `H265` to `false` in `ViewController.swift` to do H.264 instead of HEVC encoding.

