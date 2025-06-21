if type(usercontent) == 'nil' then usercontent = {} end
if usercontent._injection_cache then return usercontent._injection_cache end

local core = require('content_editor.core')
local config = require('content_editor._internal').config

local versionStr = core.game.version .. '; ' .. core.VERSION_STR

usercontent._injection_cache = {}

--- @type table<string, table<integer, InjectionCacheEntry>>
local cache = {}

--- @class InjectionCacheEntry
--- @field status InjectionCacheState
--- @field time integer

--- @enum InjectionCacheState
local injectionCacheState = {
    Uncached = 0,
    RuntimeInjected = 1,
    FileInjected = 2,
}

--- @enum InjectionType
local injectionType = {
    Static = 0,
    RuntimeLoaded = 1,
}

local cache_filepath = core.get_path('injection_cache.json')
local cache_dirty = false

--- @param entityType string
--- @param entityId integer
--- @return InjectionCacheState
function usercontent._injection_cache.get_state(entityType, entityId)
    local data = cache[entityType]
    if not data then return 0 end

    local entry = data[entityId]
    return entry and entry.status or 0
end

--- @param entityType string
--- @param entityId integer
--- @param bundleTime integer
--- @return boolean
function usercontent._injection_cache.is_entity_outdated(entityType, entityId, bundleTime)
    local data = cache[entityType]
    if not data then return true end
    if config.data.disable_injection_cache then return true end

    local entry = data[entityId]
    if not entry or bundleTime > entry.time then return true end

    if entry.status == 2 then
        return bundleTime > ce_utils.get_game_start_time()
    elseif entry.status == 1 then
        return entry.time < ce_utils.get_game_start_time()
    else
        return true
    end
end

--- @param entityType string
--- @param entityId integer
--- @param state InjectionCacheState
function usercontent._injection_cache.update_cache(entityType, entityId, state)
    local data = cache[entityType]
    if not data then data = {} cache[entityType] = data end
    data[entityId] = {
        status = state,
        time = os.time()
    }
    cache_dirty = true
end

function usercontent._injection_cache.clear_cache()
    cache = {}
    fs.write(cache_filepath, '{}')
end

function usercontent._injection_cache.save_cache_to_file()
    json.dump_file(cache_filepath, { version = versionStr, entries = cache})
end

local function load_state_cache()
    local data = json.load_file(cache_filepath)
    if type(data) ~= 'table' or not data.entries then return end

    -- disregard the cache if the game/CE version changed
    -- maybe show a warning popup to the user?
    local version = data.version
    if version ~= versionStr then
        log.info('Content editor was last used with a previous version. Ignoring injection cache.')
        return
    end

    local startTime = ce_utils.get_game_start_time()
    local timeNow = os.clock()

    for entityType, entries in pairs(data.entries) do
        local curcache = cache[entityType]
        if not curcache then curcache = {} cache[entityType] = curcache end

        for entityIdStr, entry in pairs(entries) do
             ---@cast entry InjectionCacheEntry
            local time = entry.time
            local status = entry.status
            local id = tonumber(entityIdStr)--[[@as integer]]

            if status == 2 then
                curcache[id] = entry
            elseif status == 1 and time > startTime then
                curcache[id] = entry
            else
                print('Ignoring outdated cache entry', entityType, id, time, status)
            end
        end
    end
    cache_dirty = false
end
load_state_cache()

re.on_application_entry('UpdateBehavior', function ()
    if cache_dirty then
        usercontent._injection_cache.save_cache_to_file()
        cache_dirty = false
    end
end)

return usercontent._injection_cache