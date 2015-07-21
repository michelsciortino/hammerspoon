--- === hs.hotkey ===
---
--- Create and manage global keyboard shortcuts

local hotkey = require "hs.hotkey.internal"
local keycodes = require "hs.keycodes"
local fnutils = require "hs.fnutils"
local alert = require'hs.alert'
local tonumber,pairs,ipairs,type,tremove,tinsert,tconcat = tonumber,pairs,ipairs,type,table.remove,table.insert,table.concat
local supper,slower,sfind=string.upper,string.lower,string.find

local function getKeycode(s)
  if type(s)~='string' then error('key must be a string',3) end
  local n
  if (s:sub(1, 1) == '#') then n=tonumber(s:sub(2))
  else n=keycodes.map[s:lower()] end
  if not n then error('Invalid key: '..s,3) end
  return n
end

local hotkeys,hkmap = {},{}

--- hs.hotkey:enable() -> hs.hotkey
--- Method
--- Enables a hotkey object
---
--- Parameters:
---  * None
---
--- Returns:
---  * The `hs.hotkey` object for method chaining
---
--- Notes:
---  * When you enable a hotkey that uses the same keyboard combination as another previously-enabled hotkey, the old
---    one will stop working as it's being "shadowed" by the new one. As soon as the new hotkey is disabled or deleted
---    the old one will trigger again.
local function enable(self,force)
  if not force and self.enabled then return self end --this ensures "nested shadowing" behaviour
  local idx = hkmap[self]
  if not idx or not hotkey[idx] then error('Internal error!') end
  local i = fnutils.indexOf(hotkey[idx],self)
  if not i then error('Internal error!') end
  tremove(hotkey[idx],i)
  for _,hk in ipairs(hotkey[idx]) do hk._hk:disable() end
  self.enabled = true
  self._hk:enable() --objc
  tinsert(hotkey[idx],self) -- bring to end
  return self
end

--- hs.hotkey:disable() -> hs.hotkey
--- Method
--- Disables a hotkey object
---
--- Parameters:
---  * None
---
--- Returns:
---  * The `hs.hotkey` object for method chaining
local function disable(self)
  if not self.enabled then return self end
  local idx = hkmap[self]
  if not idx or not hotkey[idx] then error('Internal error!') end
  self.enabled = nil
  self._hk:disable() --objc
  for i=#hotkey[idx],1,-1 do
    if hotkey[idx][i].enabled then hotkey[idx][i]._hk:enable() break end
  end
  return self
end

--- hs.hotkey:delete()
--- Method
--- Disables and deletes a hotkey object
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
local function delete(self)
  disable(self)
  local idx=hkmap[self]
  if not idx or not hotkey[idx] then error('Internal error!') end
  for i=#hotkey[idx],1,-1 do
    if hotkey[idx][i]==self then tremove(hotkey[idx],i) break end
  end
  hkmap[self]=nil
  for k in pairs(self) do self[k]=nil end --gc
end


local function getMods(mods)
  local r={}
  if not mods then return r end
  if type(mods)=='table' then mods=tconcat(mods,'-') end
  if type(mods)~='string' then error('mods must be a string or a table of strings',3) end
  mods=slower(mods)
  local function find(ps)
    for _,s in ipairs(ps) do
      if sfind(mods,s,1,true) then r[#r+1]=ps[#ps] return end
    end
  end
  find{'cmd','command','⌘'} find{'ctrl','control','⌃'}
  find{'alt','option','⌥'} find{'shift','⇧'}
  return r
end

local function getIndex(mods,keycode)
  return tconcat(getMods(mods))..'#'..keycode
end
--- hs.hotkey.new(mods, key, pressedfn, releasedfn, repeatfn, message, duration) -> hs.hotkey
--- Constructor
--- Creates a new hotkey
---
--- Parameters:
---  * mods - (optional) A string containing (as substrings, with any separator) the keyboard modifiers required, which should be zero or more of the following:
---   * "cmd", "command" or "⌘"
---   * "ctrl", "control" or "⌃"
---   * "alt", "option" or "⌥"
---   * "shift" or "⇧"
---  * key - A string containing the name of a keyboard key (as found in [hs.keycodes.map](hs.keycodes.html#map) ), or if the string begins with a `#` symbol, the remainder of the string will be treated as a raw keycode number
---  * pressedfn - (optional) A function that will be called when the hotkey has been pressed
---  * releasedfn - (optional) A function that will be called when the hotkey has been released
---  * repeatfn - (optional) A function that will be called when a pressed hotkey is repeating
---  * message - (optional) A string containing a message to be displayed via `hs.alert()` when the hotkey has been triggered
---  * duration - (optional) Duration of the alert message in seconds
---
--- Returns:
---  * A new `hs.hotkey` object
---
--- Notes:
---  * If you don't need `releasedfn` nor `repeatfn`, you can simply use `hs.hotkey.new(mods,key,fn,"message")`
---  * You can create multiple `hs.hotkey` objects for the same keyboard combination, but only one can be active
---    at any given time - see `hs.hotkey:enable()`

--local SYMBOLS = {cmd='⌘',ctrl='⌃',alt='⌥',shift='⇧',hyper='✧'}
local CONCAVE_DIAMOND='✧'
function hotkey.new(mods, key, pressedfn, releasedfn, repeatfn, message, duration)
  local keycode = getKeycode(key)
  mods = getMods(mods)
  if type(pressedfn)~='function' and type(releasedfn)~='function' and type(repeatfn)~='function' then
    error('At least one of pressedfn, releasedfn or repeatfn must be a function',2) end
  if type(releasedfn)=='string' then duration=repeatfn message=releasedfn repeatfn=nil releasedfn=nil
  elseif type(repeatfn)=='string' then duration=message message=repeatfn repeatfn=nil end
  if type(message)~='string' then message=nil end
  if type(duration)~='number' then duration=nil end
  local idx = getIndex(mods,keycode)
  local desc = tconcat(mods)
  if #mods>=4 then desc=CONCAVE_DIAMOND end
  desc=desc..supper(key)
  if message then
    if #message>0 then desc=desc..': '..message end
    local actualfn=pressedfn or releasedfn or repeatfn
    local fnalert=function()alert(desc,duration or 1)actualfn()end
    if pressedfn then pressedfn=fnalert
    elseif releasedfn then releasedfn=fnalert
    elseif repeatfn then repeatfn=fnalert end
  end
  local hk = {_hk=hotkey._new(mods, keycode, pressedfn, releasedfn, repeatfn),enable=enable,disable=disable,delete=delete,desc=desc}
  hkmap[hk] = idx
  local h = hotkey[idx] or {}
  h[#h+1] = hk
  hotkey[idx] = h
  return hk
end

--- hs.hotkey.disableAll(mods, key)
--- Function
--- Disables all previously set callbacks for a given keyboard combination
---
--- Parameters:
---  * mods - (optional) A string containing (as substrings, with any separator) the keyboard modifiers required, which should be zero or more of the following:
---   * "cmd", "command" or "⌘"
---   * "ctrl", "control" or "⌃"
---   * "alt", "option" or "⌥"
---   * "shift" or "⇧"
---  * key - A string containing the name of a keyboard key (as found in [hs.keycodes.map](hs.keycodes.html#map) ), or if the string begins with a `#` symbol, the remainder of the string will be treated as a raw keycode number
---
--- Returns:
---  * None
function hotkey.disableAll(mods,key)
  local idx=getIndex(mods,getKeycode(key))
  for _,hk in ipairs(hotkey[idx] or {}) do hk:disable() end
end

--- hs.hotkey.deleteAll(mods, key)
--- Function
--- Deletes all previously set callbacks for a given keyboard combination
---
--- Parameters:
---  * mods - (optional) A string containing (as substrings, with any separator) the keyboard modifiers required, which should be zero or more of the following:
---   * "cmd", "command" or "⌘"
---   * "ctrl", "control" or "⌃"
---   * "alt", "option" or "⌥"
---   * "shift" or "⇧"
---  * key - A string containing the name of a keyboard key (as found in [hs.keycodes.map](hs.keycodes.html#map) ), or if the string begins with a `#` symbol, the remainder of the string will be treated as a raw keycode number
---
--- Returns:
---  * None
function hotkey.deleteAll(mods,key)
  local idx=getIndex(mods,getKeycode(key))
  for _,hk in ipairs(hotkey[idx] or {}) do
    hk._hk:disable() --objc
    hkmap[hk]=nil
  end
  hotkey[idx]=nil
end

--- hs.hotkey.bind(mods, key, pressedfn, releasedfn, repeatfn, message, duration) -> hs.hotkey
--- Constructor
--- Creates a hotkey and enables it immediately
---
--- Parameters:
---  * mods - A string containing (as substrings, with any separator) the keyboard modifiers required, which should be zero or more of the following:
---   * "cmd", "command" or "⌘"
---   * "ctrl", "control" or "⌃"
---   * "alt", "option" or "⌥"
---   * "shift" or "⇧"
---  * key - (optional) A string containing the name of a keyboard key (as found in [hs.keycodes.map](hs.keycodes.html#map) ), or if the string begins with a `#` symbol, the remainder of the string will be treated as a raw keycode number
---  * pressedfn - (optional) A function that will be called when the hotkey has been pressed
---  * releasedfn - (optional) A function that will be called when the hotkey has been released
---  * repeatfn - (optional) A function that will be called when a pressed hotkey is repeating
---  * message - (optional) A string containing a message to be displayed via `hs.alert()` when the hotkey has been triggered
---  * duration - (optional) Duration of the alert message in seconds
---
--- Returns:
---  * A new `hs.hotkey` object for method chaining
---
--- Notes:
---  * This function is just a wrapper that performs `hs.hotkey.new(...):enable()`
function hotkey.bind(...)
  return hotkey.new(...):enable()
end

--- === hs.hotkey.modal ===
---
--- Create/manage modal keyboard shortcut environments
---
--- Usage:
--- k = hs.hotkey.modal.new("cmd-shift", "d")
--- function k:entered() hs.alert.show('Entered mode') end
--- function k:exited()  hs.alert.show('Exited mode')  end
--- k:bind('', 'escape', function() k:exit() end)
--- k:bind('', 'J', function() hs.alert.show("Pressed J") end)

hotkey.modal = {}
hotkey.modal.__index = hotkey.modal

--- hs.hotkey.modal:entered()
--- Method
--- Optional callback for when a modal is entered
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
---
--- Notes:
---  * This is a pre-existing function that you should override if you need to use it; the default implementation does nothing.
function hotkey.modal:entered()
end

--- hs.hotkey.modal:exited()
--- Method
--- Optional callback for when a modal is exited
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
---
--- Notes:
---  * This is a pre-existing function that you should override if you need to use it; the default implementation does nothing.
function hotkey.modal:exited()
end

--- hs.hotkey.modal:bind(mods, key, pressedfn, releasedfn, repeatfn, message, duration) -> hs.hotkey.modal
--- Method
--- Creates a hotkey that is enabled/disabled as the modal is entered/exited
---
--- Parameters:
---  * mods - (optional) A string containing (as substrings, with any separator) the keyboard modifiers required, which should be zero or more of the following:
---   * "cmd", "command" or "⌘"
---   * "ctrl", "control" or "⌃"
---   * "alt", "option" or "⌥"
---   * "shift" or "⇧"
---  * key - A string containing the name of a keyboard key (as found in [hs.keycodes.map](hs.keycodes.html#map) ), or if the string begins with a `#` symbol, the remainder of the string will be treated as a raw keycode number
---  * pressedfn - (optional) A function that will be called when the hotkey has been pressed
---  * releasedfn - (optional) A function that will be called when the hotkey has been released
---  * repeatfn - (optional) A function that will be called when a pressed hotkey is repeating
---  * message - (optional) A string containing a message to be displayed via `hs.alert()` when the hotkey has been triggered
---  * duration - (optional) Duration of the alert message in seconds
---
--- Returns:
---  * The `hs.hotkey.modal` object for method chaining
function hotkey.modal:bind(...)
  --  local k = hotkey.new(...)
  --  tinsert(self.keys, k._hk)
  tinsert(self.keys, hotkey.new(...))
  return self
end

--- hs.hotkey.modal:enter() -> hs.hotkey.modal
--- Method
--- Enters a modal state
---
--- Parameters:
---  * None
---
--- Returns:
---  * The `hs.hotkey.modal` object for method chaining
---
--- Notes:
---  * This method will enable all of the hotkeys defined in the modal state via `hs.hotkey.modal:bind()`,
---    and disable the hotkey that entered the modal state (if one was defined)
---  * If the modal state was created with a keyboard combination, this method will be called automatically
function hotkey.modal:enter()
  if (self.k) then
    --    self.k._hk:disable()
    disable(self.k)
  end
  --  fnutils.each(self.keys, hotkey.enable)
  fnutils.each(self.keys, enable)
  self:entered()
  return self
end

--- hs.hotkey.modal:exit() -> hs.hotkey.modal
--- Method
--- Exits a modal state
---
--- Parameters:
---  * None
---
--- Returns:
---  * The `hs.hotkey.modal` object
---
--- Notes:
---  * This method will disable all of the hotkeys defined in the modal state, and enable the hotkey for entering the modal state (if one was defined)
function hotkey.modal:exit()
  --  fnutils.each(self.keys, hotkey.disable)
  fnutils.each(self.keys, disable)
  if (self.k) then
    enable(self.k)
    --    self.k._hk:enable()
  end
  self:exited()
  return self
end

--- hs.hotkey.modal.new(mods, key, message, duration) -> hs.hotkey.modal
--- Constructor
--- Creates a new modal state, optionally with a global keyboard combination to trigger it
---
--- Parameters:
---  * mods - (optional) A string containing (as substrings, with any separator) the keyboard modifiers, which should be zero or more of the following:
---   * "cmd", "command" or "⌘"
---   * "ctrl", "control" or "⌃"
---   * "alt", "option" or "⌥"
---   * "shift" or "⇧"
---  * key - (optional) A string containing the name of a keyboard key (as found in [hs.keycodes.map](hs.keycodes.html#map) ), or if the string begins with a `#` symbol, the remainder of the string will be treated as a raw keycode number
---  * message - (optional) A string containing a message to be displayed via `hs.alert()` when the hotkey has been triggered
---  * duration - (optional) Duration of the alert message in seconds
---
--- Returns:
---  * A new `hs.hotkey.modal` object
---
--- Notes:
---  * If `key` is nil, no global hotkey will be registered (all other parameters will be ignored)
function hotkey.modal.new(mods, key, message, duration)
  local m = setmetatable({keys = {}}, hotkey.modal)
  if (key) then
    m.k = hotkey.bind(mods, key, function() m:enter() end, message, duration)
  end
  return m
end

return hotkey
