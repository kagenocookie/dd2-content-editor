if type(usercontent) == 'nil' then usercontent = {} end
if usercontent.events then return usercontent.events end

---@type table<string, function[]>
local events = {}

---@alias EventName 'get_existing_data'|'bundles_loaded'|'ready'|'enum_updated'|'bundle_created'|'data_imported'|'setup'

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

    local devmode = usercontent.__internal.config.data.editor.devmode
    for i, cb in ipairs(store) do
        if devmode then
            log.info('Invoking event listener ' .. name .. ' #' .. tostring(i))
            cb(...)
        else
            local success, ret = pcall(cb, ...)
            if not success then
                print('ERROR in event ' .. name .. ' callback ' .. tostring(i) .. ': ' .. tostring(ret))
                log.info('ERROR in event ' .. name .. ' callback ' .. tostring(i) .. ': ' .. tostring(ret))
            end
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

usercontent.events = {
    on = register_event_ext,
    off = remove_event_ext,
    emit = emit_event_ext,
}
usercontent.__internal = usercontent.__internal or {}
usercontent.__internal.emit = emit_event_internal
usercontent.__internal.on = register_event_internal
usercontent.__internal.off = remove_event_internal
return usercontent.events
