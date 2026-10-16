# desktop_webview_window, as used by Hushdock

A copy of desktop_webview_window 0.2.3 (MIT) with one change, in
`macos/Classes/WebViewLayoutController.swift`: a navigation to a scheme other than
http, https or file is still cancelled, but Dart is told about it first
(`onUrlRequested`). The Spotify sign-in answer is a `hushdock://spotify-callback`
link; the original dropped it, so the Agree button seemed to do nothing.
