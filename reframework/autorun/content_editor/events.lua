if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB.events then return _userdata_DB.events end

---@type table<string, function[]>
local events = {}

---@alias EventName 'get_existing_data'|'bundles_loaded'|'ready'|'enum_updated'|'bundle_created'|'data_imported'

---@param name string
---@param fn function
local function register_event(name, fn)
    local store = events[name]
    if not store then
        store = {}
        events[name] = store
    end
    table.insert(store, #store + 1, fn)
end

---@param name string
---@param fn function
local function remove_event(name, fn)
    local store = events[name]
    if not store then return end
    for i = 1, #store do
        if store[name] == fn then
            table.remove(store, i)
            return
        end
    end
end

---@param name string
local function emit_event(name, ...)
    local store = events[name]
    if not store then return end

    for i, cb in ipairs(store) do
        print('Emitting event ', name, ...)
        local success, ret = pcall(cb, ...)
        if not success then
            print('ERROR in event ' .. name .. ' callback ' .. tostring(i) .. ': ' .. tostring(ret))
        end
    end
end

---@param name EventName
---@param fn function
---@overload fun(name: 'get_existing_data', fn: fun())
---@overload fun(name: 'bundles_loaded', fn: fun())
---@overload fun(name: 'ready', fn: fun()) The content DB is all ready and all initial bundles loaded
---@overload fun(name: 'enum_updated', fn: fun(enum: EnumSummary)) An enum was updated
---@overload fun(name: 'bundle_created', fn: fun(bundle: BundleRuntimeData)) A new data bundle was created
---@overload fun(name: 'data_imported', fn: fun(entities: table<string,DBEntity[]>)) Entities have been (re-)imported. Table keys represent entity types.
local function register_event_ext(name, fn) register_event(name, fn) end

---@param name EventName
---@param fn function
local function remove_event_ext(name, fn) remove_event(name, fn) end

---@param name EventName
local function emit_event_ext(name, ...) emit_event(name, ...) end

---@param name string
---@param fn function
local function register_event_internal(name, fn) register_event(name, fn) end

---@param name string
---@param fn function
local function remove_event_internal(name, fn) remove_event(name, fn) end

---@param name string
local function emit_event_internal(name, ...) emit_event(name, ...) end

_userdata_DB.events = {
    on = register_event_ext,
    off = remove_event_ext,
    emit = emit_event_ext,
}
_userdata_DB.__internal = _userdata_DB.__internal or {}
_userdata_DB.__internal.emit = emit_event_internal
_userdata_DB.__internal.on = register_event_internal
_userdata_DB.__internal.off = remove_event_internal
return _userdata_DB.events
