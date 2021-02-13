---
--- Generated by Luanalysis
--- Created by Lyr.
--- DateTime: 12/25/2020 2:22 PM actually started 01/06/21
---


-- I know code is literally everywhere, shush
-- Imma fix em soonish

--[[--   UTIL   --]]--

--region Utility functions

--- Fetches a value from persistent storage, or returns the supplied default.
---@param self ModsysBase
---@param key string
---@param default any
---@return any
local function storage_default(self, key, default)
  local value = self.storage[key]

  if type(default) == "table" then
    if next(default) == nil then  -- empty table, match if empty
      Modsys.storages._defaults[self._name][key] = {__empty = true}
    else
      Modsys.storages._defaults[self._name][key] = 0    -- always don't match
    end
    return value or default
  else
    Modsys.storages._defaults[self._name][key] = default    -- TODO if table then copy
    if value ~= nil then  -- (can't use and-or here, to respect false values)
      return value
    else
      return default
    end
  end
end

---@shape ModuleStorage

local _moduleId = 0   -- Upvalue use, incremented
---@type table<string,ModsysBase>
local _root = {}      -- TODO: fix this mess...
--- Used for ModsysBase classes.
---@param tb ModsysBase
local function Class(tb)
  tb.__index = tb
  tb.new = function()
    _root[_ENV._rootName] = setmetatable({}, tb)
    return _root[_ENV._rootName]
  end
  tb.newInstance = function(name, cfg)
    _moduleId = _moduleId + 1

    Modsys.storages[name] = Modsys.storages[name] or {}
    Modsys.storages._defaults[name] = {}

    local channels = cfg._channels or { 0 }
    local channelsInv = {}
    for i = 1, #channels do
      channelsInv[channels[i]] = true
    end

    cfg._channels = nil

    return setmetatable({
      _id = _moduleId,        -- self._id -- TODO not needed
      _name = name,           -- self._name
      _channels = channelsInv,-- self._channels
      cfg = cfg,              -- self.cfg
      storage = Modsys.storages[name],  -- self.storage
      storageDefault = storage_default  -- var = self:storageDefault(k,d)
    }, {__type = tb, __index = _root[_ENV._rootName]})
  end
end

---@shape CallableItem<T>
---@field [1] fun(self:T, ...:any)
---@field [2] T

---@param tb CallableItem<ModsysBase>[]
---@vararg any
local function callEach(tb,...)
  for i = 1, #tb do
    tb[i][1](tb[i][2], ...)
  end
end

local function CallableArray(tb)
  tb.__call = callEach
  setmetatable(tb, tb)
end

--- Just removed the metatable copy cause mts aren't needed in here
---@generic T
---@param v T
---@return T
local function copy(v)
  if type(v) ~= "table" then
    return v
  else
    local c = {}
    for k,r in pairs(v) do
      c[k] = copy(r)
    end
    return c
  end
end


--endregion Utility functions




--[[--   MODSYS   --]]--

--region ModSys base table


--- Modsys root to register statuseffect Events and Actions.
---@class Modsys
---@field globals table<string, any>
---@field inits CallableItem<ModsysBase>[]
---@field updates table
---@field uninits CallableItem<ModsysBase>[]
---@field onExpires CallableItem<ModsysBase>[]
---@field eventBus EventData[]
---@field filters Filter[]
---@field actions Action[]
---@field storages table<string, ModuleStorage>  @ Persistent storage for each module
local Modsys = {
  globals = {},
  inits = {}, updates = {events = {}, filters = {}, actions = {}}, uninits = {}, onExpires = {},
  eventBus = {}, filters = {}, actions = {}
}
CallableArray (Modsys.inits)
CallableArray (Modsys.updates.events)
CallableArray (Modsys.updates.filters)
CallableArray (Modsys.updates.actions)
CallableArray (Modsys.uninits)
CallableArray (Modsys.onExpires)

-- TODO!!! (Maybe?) Functions are pass-by-value, so store the module tables instead of the callbacks themselves... Might reduce readablility though


---@param tb ModsysBase
local function registerCallbacks(tb)
  Modsys.inits[#Modsys.inits + 1] = tb.init and {tb.init, tb}
  --( Modsys.updates need to be separate )--
  Modsys.uninits[#Modsys.uninits + 1] = tb.uninit and {tb.uninit, tb}
  Modsys.onExpires[#Modsys.onExpires + 1] = tb.onExpire and {tb.onExpire, tb}
end

--[[ TODO: make these registerX useful by doing stuff (that idk yet). The boolean returns are useless lol ]]--

--- Register an Event (Publisher) for the effect.
---@param event Event
---@return boolean
function Modsys.registerEvent(event)
  if not event then return false end
  if getmetatable(event).__type ~= Event then
    Modsys.logWarn("%s is not an instance of an Event.", _ENV._name)
    return false
  end
  registerCallbacks(event)
  Modsys.updates.events[#Modsys.updates.events + 1] = event.update and {event.update, event}
  return true
end

--- Register a Filter (Processor) that allows or gates events based on certain conditions.
---@param filter Filter
---@return boolean
function Modsys.registerFilter(filter)
  if not filter then return false end
  if getmetatable(filter).__type ~= Filter then
    Modsys.logWarn("%s is not an instance of a Filter.", _ENV._name)
    return false
  end
  registerCallbacks(filter)
  Modsys.updates.filters[#Modsys.updates.filters + 1] = filter.update and {filter.update, filter}
  Modsys.filters[#Modsys.filters + 1] = filter
  return true
end

--- Register an Action (Subscriber) that modifies the entity.
---@param action Action
---@return boolean
function Modsys.registerAction(action)
  if not action then return false end
  if getmetatable(action).__type ~= Action then
    Modsys.logWarn("%s is not an instance of an Action.", _ENV._name)
    return false
  end
  registerCallbacks(action)
  Modsys.updates.actions[#Modsys.updates.actions + 1] = action.update and {action.update, action}
  Modsys.actions[#Modsys.actions + 1] = action
  return true
end


-- Utility --

--- Utility to extract the module's real name ("module3" --> "module")
---@param name string
---@return string
function Modsys.rootName(name)
  return name:gsub("%d+$", "")
end

---@param moduleName string
---@return boolean
function Modsys.resetStorage(moduleName)
  local storage = Modsys.storages[moduleName]
  if not storage then return false end

  for key, def in pairs(Modsys.storages._defaults[moduleName] or {}) do
    storage[key] = def
  end
  return true
end

---@param format string
function Modsys.log(format, ...) if Modsys.isDebug then sb.logInfo("<Modsys> " .. format, ...) end end

---@param format string
function Modsys.logWarn(format, ...) sb.logWarn("<Modsys> WARN: " .. format, ...) end

---@param format string
function Modsys.debugMap(format, ...) if Modsys.isDebug then sb.setLogMap("modsys." .. self._name, format, ...) end end

--endregion ModSys base table




--region ModSys module types


-- TODO: Add callback function docs
-- TODO: Remove _id cause unused???

--- Base interface for below classes
---@class ModsysBase
---@field new fun():ModsysBase    @ New subclass function
---@field newInstance fun(name:string, config:table):ModsysBase  @ New implementation
---@field _id number              @ Sequential ID for the module.
---@field _name string            @ Name of the module, also the module's partial script name
---@field _channels table<number,boolean>   @ Array of channel numbers the module works on
---@field cfg table               @ JSON configuration for the module (_channels from JSON is removed)
---@field storage ModuleStorage   @ Persistent storage table
---@field storageDefault fun(self:self, key:string, default:any)
---@field init fun(self:self)
---@field update fun(self:self, dt:number)
---@field uninit fun(self:self)
---@field onExpire fun(self:self)

--- Table that gets emitted by Events, that optionally contains information about the event.
---@shape EventData
---@field _eventName string
---@field _channel number
---@field _skipFilters boolean    @ true if event is emitted by a filter, to prevent filters from processing it


--- Base class to be extended for emitting events in response to specific entity changes.
---@class Event : ModsysBase
---@field new fun() : Event
local Event = {}
Class(Event)

--- To be called when firing an event.
--- `self:emit()` or `self:emit({})`, safe to be called on each update
---@param data EventData | nil
function Event:emit(data)
  local v = data or {}
  v._eventName = self._name
  for ch in pairs(self._channels) do
    local n = copy(v)
    n._channel = ch
    Modsys.eventBus[#Modsys.eventBus + 1] = n
  end
end


--- Base class to be extended for filtering events according to conditions.
---@class Filter : ModsysBase
---@field new fun() : Filter
local Filter = {}
Class(Filter)   -- TODO: add emit. Also, parse emit `_from` parameter where in the stack to continue. Also action to emit an event in a stack

--- To be overridden by Filter subclasses.
--- Return the data itself when filter passes, return `data, true` to skip succeeding filters,
--- return nil to void the event.
---@generic T : EventData
---@param data T
---@return T | nil, true | nil
function Filter:process(data)
  return data
end

--- Allows a filter to defer events, etc. Events emitted thorugh this doesn't go through any filter.
--- Also event is only sent through the data's _channel, unless _channels (with s) is defined (keys are channel numbers)
--- `self:emit()` or `self:emit({})`, safe to be called on each update
---@param data EventData | nil
function Filter:emit(data)
  local v = data or {}
  v._eventName = self._name
  v._skipFilters = true
  for ch in pairs(data._channels or {[data._channel] = true}) do
    local n = copy(v)
    n._channel = ch
    Modsys.eventBus[#Modsys.eventBus + 1] = n
  end
end


--- Base class to be extended for actions to be done to the entity in response to `ModsysEvent`s.
---@class Action : ModsysBase
---@field new fun() : Action
local Action = {}
Class(Action)

--- To be overriden by Action subclasses.
--- Returning *anything* within this function makes it final, i.e. other actions after this action
--- won't get executed for the current event.
---@param data EventData
---@return any | nil
function Action:run(data) end


--endregion ModSys module types




--[[--   STATUSEFFECT SPECIFIC   --]]--


---@param data EventData
local function doFilters(data)
  Modsys.log("Event emitted! Pointer: [ %s ] data: %s", tostring(data), sb.print(data))
  if data._skipFilters then return data end   -- skip if present
  local halt
  for i = 1, #Modsys.filters do
    if Modsys.filters[i]._channels[data._channel] then
      data, halt = Modsys.filters[i]:process(data)
      if data == nil or halt then break end
    end
  end
  return data
end

local function doActions(data)
  Modsys.log("Event passed! Pointer: [ %s ]", tostring(data))
  for i = 1, #Modsys.actions do
    if Modsys.actions[i]._channels[data._channel] and Modsys.actions[i]:run(data) then break end
  end
end


function init()   -- TODO: Module ordering? nah just yeet across channels.
  _ENV.Modsys = Modsys

  self.effectName = config.getParameter("name")
  if not self.effectName then error("modsys: effectConfig has no name field.") end

  self.storeName = "kf.modsysStorage." .. self.effectName

  Modsys.isDebug = config.getParameter("debug", false)

  Modsys.storages = status.statusProperty(self.storeName)
  if type(Modsys.storages) ~= "table" then  -- prevent invalid data or empty
    Modsys.storages = {}
  end
  Modsys.storages._defaults = {}

  --- Load modules/event-<name>.lua into the script. Require won't do anything when file already required, don't worry.
  ---@param name string
  ---@param config table
  local function loadEvent(name, config)
    _ENV.Event = Event
    _ENV.cfg = config or {}
    _ENV._name = name
    name = Modsys.rootName(name)
    _ENV._rootName = name   -- only used once on require
    Modsys.log("Loading %s (module %s)...", _ENV._name, name)
    local success, msg = pcall(require, "/scripts/effects/modsys/modules/event-"..name..".lua")
    if not success then
      Modsys.logWarn("%s is not a valid Event. (event-%s.lua not found in modules, or errored, see below.)\n%s", name, name, msg)
    else
      Modsys.registerEvent(_root[name].newInstance(_ENV._name, _ENV.cfg))
    end
  end

  --- Load modules/filter-<name>.lua into the script.
  ---@param name string
  ---@param config table
  local function loadFilter(name, config)
    _ENV.Filter = Filter
    _ENV.cfg = config or {}
    _ENV._name = name
    name = Modsys.rootName(name)
    _ENV._rootName = name
    Modsys.log("Loading %s (module %s)...", _ENV._name, name)
    local success, msg = pcall(require, "/scripts/effects/modsys/modules/filter-"..name..".lua")
    if not success then
      Modsys.logWarn("%s is not a valid Filter. (filter-%s.lua not found in modules, or errored, see below.)\n%s", name, name, msg)
    else
      Modsys.registerFilter(_root[name].newInstance(_ENV._name, _ENV.cfg))
    end
  end

  --- Load modules/action-<name>.lua into the script.
  ---@param name string
  ---@param config table
  local function loadAction(name, config)
    _ENV.Action = Action
    _ENV.cfg = config or {}
    _ENV._name = name
    name = Modsys.rootName(name)
    _ENV._rootName = name
    Modsys.log("Loading %s (module %s)...", _ENV._name, name)
    local success, msg = pcall(require, "/scripts/effects/modsys/modules/action-"..name..".lua")
    if not success then
      Modsys.logWarn("%s is not a valid Action. (action-%s.lua not found in modules, or errored, see below.)\n%s", name, name, msg)
    else
      Modsys.registerAction(_root[name].newInstance(_ENV._name, _ENV.cfg))
    end
  end

  local function globReplace(cfg, globals)
    for k, v in pairs(cfg) do
      if type(v) == "string" and v:sub(1,1) == "%" and #v > 1 then
        local val = globals[v]
        if val == nil then Modsys.logWarn("Global \"%s\" does not exist.", v:sub(2)) end
        cfg[k] = val
      elseif type(v) == "table" then   -- recurse
        globReplace(v, globals)
      end
    end
    return cfg
  end

  local events  = config.getParameter("events", {})
  local filters = config.getParameter("filters", {})
  local actions = config.getParameter("actions", {})

  local tempGlobals = config.getParameter("globals", {})
  local globals = {}

  for k,v in pairs(tempGlobals) do globals["%" .. k] = v end    -- just append %

  for name, cfg in pairs(events) do loadEvent(name, globReplace(cfg, globals)) end
  for name, cfg in pairs(filters) do loadFilter(name, globReplace(cfg, globals)) end
  for name, cfg in pairs(actions) do loadAction(name, globReplace(cfg, globals)) end

  effect.addStatModifierGroup(config.getParameter("statModifiers", {}))

  Modsys.inits()
end


---@param dt number
function update(dt)
  Modsys.updates.events(dt)
  Modsys.updates.filters(dt)
  for id, data in pairs(Modsys.eventBus) do   -- pairs cause we're modifying eventBus while running (just don't let a filter process return nil and emit at the same time.)
    -- run doFilters only when data is not empty (eventData objects always have an _eventName field.)
    Modsys.eventBus[id] = next(data) and doFilters(data)
  end

  Modsys.updates.actions(dt)
  for _, data in pairs(Modsys.eventBus) do   -- pairs cause eventBus could be filled with nil-holes
    doActions(data)
  end
  Modsys.eventBus = --[[---@type EventData[] ]] {}
end


function uninit()
  Modsys.uninits()

  local toStore = {}
  for moduleName,store in pairs(Modsys.storages) do
    --Modsys.storages._defaults[self._name][key] = default
    local newStore = {}
    for key, def in pairs(Modsys.storages._defaults[moduleName] or {}) do
      if type(def) == "table" and def.__empty then
        if next(store[key]) ~= nil then
          newStore[key] = store[key]
        end
      else
        if store[key] ~= def then
          newStore[key] = store[key]
        end
      end
    end
    toStore[moduleName] = next(newStore) and newStore
  end

  -- todo, os.time comparator
  status.setStatusProperty(self.storeName, next(toStore) and toStore)
end


function onExpire()
  Modsys.onExpires()
end