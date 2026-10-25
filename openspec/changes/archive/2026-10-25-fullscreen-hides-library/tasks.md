# Tasks

## 1. Hide and restore

- [x] 1.1 `LibraryWindows` helper (hide visible library windows, remember them weakly, restore behind the player, hand out a hidden window); `PlayerScreen` calls it on entering and leaving full screen and when the player closes in full screen; verify on the demo server with `IPTV_AUTOPLAY=live:101 IPTV_TESTFS=1` (enter, leave, re-enter): the log shows the library hidden after "enter", visible again after "leave", hidden after "re-enter", and the window list (CGWindowList, Fernsy windows only) matches
- [x] 1.2 Activation lands on the player: with the player in full screen and TextEdit frontmost on the desktop, activate Fernsy (`NSRunningApplication.activate`, the same path as ⌘-Tab); Fernsy becomes frontmost with only the full-screen player listed, and the user confirmed on screen that it lands in the full-screen Space (CGWindowList and the Space-change notification could not tell Spaces apart here); then close the player in full screen (MCP `stop_playback`) and the library is back

## 2. Library requests while hidden

- [x] 2.1 `MenuBarSupport.showLibrary` and `PlayerWindow.showLibrary` use a hidden library window first; verify with the debug build in full screen: Siri's search action (`IPTV_TESTINTENT=search:<text>`) shows the hidden library window, and the count of library windows stays 1

## 3. Integration

- [x] 3.1 Quit while the library is hidden and launch again: a library window opens; `DEVELOPMENT.md` window notes; Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without warnings; `openspec validate --all --strict`
