# Tasks

## 1. Player in front

- [x] 1.1 `PlayerWindow.show`: order an existing player window front regardless (deminiaturize first); for a new window set a pending flag that `PlayerScreen` honours once on appear; verify on the demo server (`IPTV_MCP=1 IPTV_MCPTOKEN=test`) with another app frontmost (TextEdit opened via `open -a TextEdit`): MCP `play live:101` → the window list (`rows/wins`) shows the player above TextEdit's window and TextEdit stays the frontmost app (`lsappinfo front`); then bring TextEdit in front again and `play live:102` → player in front again; minimize test via a debug hook if needed (`IPTV_TESTMINIATURIZE`), with PiP (`IPTV_TESTPIP`) no player window comes forward
- [x] 1.2 Siri's open action takes the same path: `IPTV_TESTINTENT=open:102` with TextEdit frontmost → player in front

## 2. Integration

- [x] 2.1 Build Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without warnings; `openspec validate --all --strict`
