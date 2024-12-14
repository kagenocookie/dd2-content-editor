if type(usercontent) == 'nil' then usercontent = {} end
if usercontent.events then return usercontent.events end

---@type table<string, function[]>
local events = {}

---@alias EventName 'get_existing_data'|'bundles_loaded'|'ready'|'enum_updated'|'bundle_created'|'entities_created'|'entities_updated'|'setup'

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
    -- local t_start = os.clock()
    for i, cb in ipairs(store) do
        -- local t_start_single = os.clock()
        if devmode then
            log.info('Invoking event listener ' .. name .. ' #' .. tostring(i))
            cb(...)
            -- print(name, i, os.clock() - t_start_single)
        else
            local success, ret = pcall(cb, ...)
            if not success then
                print('ERROR in event ' .. name .. ' callback ' .. tostring(i) .. ': ' .. tostring(ret))
                log.info('ERROR in event ' .. name .. ' callback ' .. tostring(i) .. ': ' .. tostring(ret))
            end
        end
    end
    -- print(name, 'TOTAL', os.clock() - t_start)
end

---`setup`: Called at the start of the initial DB setup (before ready, bundles and type cache not yet loaded)
---
---`get_existing_data`: Called to request all active editors to fetch existing game data.
---<br>If editor is enabled: only ever called once on game start with whitelist = nil, in which case all data should be fetched
---<br>If editor disabled: whitelist is never null; called once on start and once whenever a new bundle gets enabled. Whitelist contains only entity IDs that are not yet known to the content editor database.
---<br><br>If the fetch is fast enough even for the full dataset, feel free to ignore the whitelist and just check if `next(udb.get_all_entities_map('entity_type'))`
---
---`bundles_loaded`: Called after all bundles have finished loading (on start or full database refresh)
---
---`entities_created`, `entities_updated`: Called to request an import of a set of entities into the game's data. Table keys represent entity types.
---<br>Intended as a bulk insert for cases where importing one by one in the entity's import handler directly is less performant.
---
---`ready`: Called after the initial DB setup is finished and bundles are all loaded
---@param name EventName
---@param fn function
---@overload fun(name: 'get_existing_data', fn: fun(whitelist: nil|table<string,table<integer,true>>))
---@overload fun(name: 'bundles_loaded', fn: fun())
---@overload fun(name: 'ready', fn: fun())
---@overload fun(name: 'setup', fn: fun())
---@overload fun(name: 'enum_updated', fn: fun(enum: EnumSummary))
---@overload fun(name: 'bundle_created', fn: fun(bundle: BundleRuntimeData))
---@overload fun(name: 'entities_created', fn: fun(entities: table<string,DBEntity[]>))
---@overload fun(name: 'entities_updated', fn: fun(entities: table<string,DBEntity[]>))
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
