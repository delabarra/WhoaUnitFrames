---
name: reload
description: >-
  Adds or maintains the WoW slash command /rl that calls ReloadUI.
  Use when the user asks for /rl, reload UI slash command, or ReloadUI shortcut
  in WhoaUnitFrames or sibling WoW addons.
disable-model-invocation: true
---

# Reload slash command (`/rl`)

## Goal

Provide `/rl` as a short alias for `ReloadUI()`.

## WhoaUnitFrames pattern

Register next to other slash commands in `Core/WhoaUnitFrames.lua`, then flush the hash list (taint-safe):

```lua
SLASH_RL1 = "/rl"
SlashCmdList.RL = function()
	ReloadUI()
end
if ChatFrameUtil and ChatFrameUtil.ImportAllListsToHash then
	ChatFrameUtil.ImportAllListsToHash()
end
```

## Rules

- Do not put `/rl` in Settings / `Options.lua`
- Prefer the same file that already registers `/whoaui` (or the addon's existing slash block)
- Always call `ChatFrameUtil.ImportAllListsToHash()` after registering if that API exists
- Keep the handler a direct `ReloadUI()` call — no combat checks, no messages
