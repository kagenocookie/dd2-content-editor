if type(usercontent) == 'nil' then usercontent = {} end
if usercontent.prefabs and usercontent.prefabs.presets then return usercontent.prefabs.presets end

-- this may not be thread safe?

--- @class PrefabCacheData
--- @field pfb via.Prefab
--- @field loadCallbacks fun(pfb: via.Prefab)[]

--- @type table<string, PrefabCacheData>
local prefabContainer = {}

--- @type table<string, via.GameObject>
local sharedInstances = {}

local waitingPrefabs = {} ---@type table<string, true>

local vec3Zero = ValueType.new(sdk.find_type_definition('via.vec3'))--[[@as via.vec3]]

re.on_application_entry('UpdateBehavior', function ()
    for path, _ in pairs(waitingPrefabs) do
        local data = prefabContainer[path]
        if data then
            local pfb = data.pfb
            if pfb:get_Ready() then
                for _, cb in ipairs(data.loadCallbacks) do
                    local success, result = pcall(cb, pfb)
                    if not success then
                        print('ERROR: error in callback for prefab load', path)
                        print(tostring(result))
                    end
                end
                data.loadCallbacks = {}
                waitingPrefabs[path] = nil
            end
        end
    end
end)

--- Get a prefab that is already loaded and ready.
--- @param path string
--- @return via.Prefab|nil
local function get_loaded_prefab(path)
    local pfb = prefabContainer[path]
    return pfb and pfb.pfb:get_Ready() and pfb.pfb or nil
end

--- Queue a prefab load
--- @param path string
--- @param onload nil|fun(pfb: via.Prefab)
--- @return via.Prefab pfb The prefab that may or may not be ready to instantiate yet
local function load_prefab(path, onload)
    local data = prefabContainer[path]
    if not data then
        local pfb = sdk.create_instance('via.Prefab'):add_ref() --[[@as via.Prefab]]
        pfb:set_Path(path)
        if onload then
            data = { pfb = pfb, loadCallbacks = { onload } }
        else
            data = { pfb = pfb, loadCallbacks = {} }
        end
        prefabContainer[path] = data
        waitingPrefabs[path] = true
        return pfb
    end

    if onload then
        if data.pfb:get_Ready() then
            onload(data.pfb)
        else
            print('Adding to callback for prefab', path)
            data.loadCallbacks[#data.loadCallbacks + 1] = onload
            waitingPrefabs[path] = true
        end
    end
    return data.pfb
end

--- Instantiate a new instance from a prefab and execute the callback function. If the prefab is not loaded it, it will be queued and executed when it finishes.
--- @param path string
--- @param position via.vec3|{x: number, y: number, z: number}|nil
--- @param onload nil|fun(pfb: via.GameObject)
--- @return via.GameObject|nil
local function prefab_instantiate(path, position, onload)
    if not position or type(position) == 'table' then
        local vec3 = ValueType.new(sdk.find_type_definition('via.vec3'))--[[@as via.vec3]]
        vec3.x = position and position.x or 0
        vec3.y = position and position.y or 0
        vec3.z = position and position.z or 0
        position = vec3
    end

    if onload then
        load_prefab(path, function (pfb)
            local inst = pfb:instantiate(position)
            if inst then onload(inst) end
        end)
    else
        local pfb = load_prefab(path)
        if pfb:get_Ready() then
            return pfb:instantiate(position)
        end
    end
end

--- Instantiate a shared instance from a prefab and execute the callback function. The instance will be reused across all other calls to instantiate_shared and always instantiated at (0,0,0). If the prefab is not loaded it, it will be queued and executed when it finishes.
--- @param path string
--- @param onload nil|fun(pfb: via.GameObject)
--- @return via.GameObject|nil
local function prefab_instantiate_shared(path, onload)
    local instance = sharedInstances[path]
    if instance then
        if onload then onload(instance) end
        return instance
    end

    local loadedPfb = get_loaded_prefab(path)
    if loadedPfb then
        instance = loadedPfb:instantiate(vec3Zero):add_ref()--[[@as via.GameObject]]
        sharedInstances[path] = instance
        if onload then onload(instance) end
        return instance
    end

    if onload then
        load_prefab(path, function (pfb)
            instance = pfb:instantiate(vec3Zero):add_ref()--[[@as via.GameObject]]
            sharedInstances[path] = instance
            onload(instance)
        end)
    else
        load_prefab(path)
    end
end

usercontent.prefabs = {
    load = load_prefab,
    get_loaded = get_loaded_prefab,
    instantiate = prefab_instantiate,
    instantiate_shared = prefab_instantiate_shared,
}
return usercontent.prefabs