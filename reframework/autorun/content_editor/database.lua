if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB.database then return _userdata_DB.database end

local core = require('content_editor.core')
local utils = require('content_editor.utils')
local internal = require('content_editor._internal')
local events = require('content_editor.events')
local typecache = require('content_editor.typecache')
local enums = require('content_editor.enums')
local type_settings = require('content_editor.definitions')

---@type table<DBEntity, EntityData>
local entity_tracker = {}

--- @class EntityTypeConfig
--- @field import fun(import_data: EntityImportData, instance: nil|DBEntity): DBEntity Method to import this type of entity into the game.
--- @field export fun(instance: DBEntity): EntityImportData Export the data into a serializable object; The core fields can be omitted (id, label, type) as they will be automatically before saving.
--- @field delete nil|fun(instance: DBEntity): status: nil|'ok'|'error'|'not_deletable'|'forget' Delete / disable the entity from the game's data; forget: entity may not be fully deleted or reverted to default state, we can remove the entity record for it but will show a prompt to restart the game
--- @field generate_label nil|fun(entity: DBEntity): string
--- @field root_types string[] Types to automatically generate type data for
--- @field replaced_enum string|nil
--- @field insert_id_range [integer, integer] This field should contain two [min, max] integers for allowed mod entity IDs; Will be used to define initial IDs for new bundles

--- @alias ImportActionType 'create'|'update'|'delete'

--- @type table<string, EntityTypeConfig>
local entity_types = {}

--- @type table<string, table<integer, DBEntity>>
local entities_by_id = {}

--- @type table<string, EnumSummary>
local entity_enums = {}

--- @type BundleRuntimeData[] List of non-disabled bundles sorted by load order
local activeBundles = {}

--- @type DataBundle[] List of all bundles sorted by load order
local allBundles = {}

local bundles_enum = enums.create_enum({}, 'UserdataBundles')

local db_ready = false
local db_failed = false

---Get a bundle by its name.
---@param name string
---@return BundleRuntimeData|nil
local function get_active_bundle_by_name(name)
    return activeBundles[utils.table_find_index(activeBundles, function (b) return b.info.name == name end)]
end

---Get a bundle by its name. Includes deactivated bundles.
---@param name string
---@return DataBundle|nil
local function get_bundle_by_name(name)
    return allBundles[utils.table_find_index(allBundles, function (b) return b.name == name end)]
end

--- @param entity DBEntity
--- @return BundleRuntimeData|nil bundle, integer bundleIndex
local function get_bundle_containing_entity(entity)
    -- iterating backwards so we find the latest load order bundle first
    for bundleIdx = #activeBundles, 1, -1 do
        local b = activeBundles[bundleIdx]
        for _, e in ipairs(b.entities) do
            if e == entity then
                return b, bundleIdx
            end
        end
    end
    return nil, 0
end

local databundle_dir = core.get_path('bundles/')

--- Create a new entity
--- @param entity DBEntity
--- @param bundleName string|nil
--- @return DBEntity
local function create_entity(entity, bundleName, _skipResortEnum)
    local trackedEntity = entity_tracker[entity]
    if trackedEntity then
        if bundleName then
            -- during import, the new entity should have already overwritten the existing one
            -- all that's left here is to update the entity's primary bundle
            trackedEntity.bundle = bundleName
            trackedEntity.entity.label = entity.label
            local bundle = get_active_bundle_by_name(bundleName)
            if bundle then
                bundle.dirty = true
            end
        else
            print('Entity already tracked ', entity.type, entity.id)
        end
        entity_enums[entity.type].set_display_label(entity.id, entity.label)

        return trackedEntity.entity
    end
    local entType = entity_types[entity.type]
    if not entType then
        print('Unknown new entity type', entity.type, entity.id)
        return {}
    end
    local dupe_id_entity = entities_by_id[entity.type][entity.id]
    if dupe_id_entity then
        if dupe_id_entity ~= entity then
            -- TODO which one do we take?
            print('Entity already exists by id, oi', entity.type, entity.id)
        end

        return dupe_id_entity
    end

    local entityEnum = entity_enums[entity.type]
    if not entity.label or entity.label == '' then
        entity.label = entityEnum.valueToDisplayLabels[entity.id]
            or entType.generate_label and entType.generate_label(entity)
            or entity.type .. ' ' .. tostring(entity.id)
    end

    trackedEntity = {
        dirty = true,
        entity = entity,
        type = entity.type,
        bundle = bundleName,
    }
    if bundleName then
        local bundle = get_active_bundle_by_name(bundleName)
        if bundle then
            bundle.entities[#bundle.entities+1] = entity
            bundle.dirty = true
        end
    end

    entity_tracker[entity] = trackedEntity
    entities_by_id[entity.type][entity.id] = entity

    local enumLabel = entityEnum.valueToLabel[entity.id] or entity.label
    entityEnum.valueToDisplayLabels[entity.id] = entity.label
    entityEnum.labelToValue[enumLabel] = entity.id
    entityEnum.valueToLabel[entity.id] = enumLabel
    -- print('created entity inst', entity.type, entity.id, entity.label)

    if not _skipResortEnum then
        entity_enums[entity.type].resort()
    end
    return entity
end

--- @param entity DBEntity
--- @param dirty boolean|nil
local function mark_entity_dirty(entity, dirty)
    local trackedEntity = entity_tracker[entity]
    if not trackedEntity then
        print('Entity not tracked!! ', entity.type, entity.id)
        return
    end

    trackedEntity.dirty = dirty == nil and true or dirty or false
    if trackedEntity.bundle then
        local bundle = get_active_bundle_by_name(trackedEntity.bundle)
        if bundle then bundle.dirty = true end
    end
end

--- Store a new entity in the database and mark it as pristine (unchanged)
--- @param entity DBEntity
local function register_pristine_entity(entity)
    create_entity(entity, nil, true)
    mark_entity_dirty(entity, false)
    return entity
end

---@param obj DBEntity|nil
---@return boolean
local function entity_check_unsaved_changes(obj)
    if obj then
        local ent = entity_tracker[obj]
        return ent and ent.dirty
    else
        return utils.first_where(entity_tracker, entity_check_unsaved_changes) ~= nil
    end
end

---@param bundleName string
---@return boolean
local function bundle_check_unsaved_changes(bundleName)
    local bundle = get_active_bundle_by_name(bundleName)
    -- TODO do we want to verify if also any entities of the bundle are dirty?
    -- Or should that explicitly not be done because entities can be in multiple bundles?
    return bundle and bundle.dirty or false
end

---@param bundleName string
---@return string[]
local function get_bundle_entity_types(bundleName)
    local bundle = get_active_bundle_by_name(bundleName)
    if not bundle then return {} end
    local list = {}
    for _, e in ipairs(bundle.entities) do
        if not utils.table_contains(list, e.type) then
            list[#list+1] = e.type
        end
    end
    return list
end

---@param bundleName string
---@param entityType string|nil
---@return DBEntity[]
local function get_bundle_entities(bundleName, entityType)
    local bundle = get_active_bundle_by_name(bundleName)
    if not bundle then return {} end
    local list = {}
    for _, e in ipairs(bundle.entities) do
        if not entityType or entityType == e.type then
            list[#list+1] = e
        end
    end
    return list
end

---@return boolean
local function check_any_unsaved_changes()
    return utils.first_where(entity_tracker, entity_check_unsaved_changes) ~= nil
        or utils.first_where(activeBundles, function(ab) return ab.dirty end) ~= nil
end

local function generate_random_initial_insert_id(entity_type)
    local et = entity_types[entity_type]
    if et then
        return math.floor(math.random(et.insert_id_range[1], et.insert_id_range[2])/100)*100
    end
    return 9999
end

--- @param entity_cfg EntityTypeConfig
--- @param data EntityImportData
--- @param instance DBEntity|nil
local function import_entity(entity_cfg, data, instance)
    local entity = entity_cfg.import(data, instance)
    entity.id = data.id
    entity.type = data.type
    entity.label = data.label or (instance and instance.label)
    return entity
end

--- @param entity DBEntity
--- @return EntityImportData|nil
local function export_entity(entity)
    local tt = entity_types[entity.type]
    if tt then
        local exportedEntity = tt.export(entity)
        if exportedEntity then
            exportedEntity.type = entity.type
            exportedEntity.id = entity.id
            exportedEntity.label = entity.label
        else
            print('ERROR: Failed to export entity ' .. entity.id .. ' of type ' .. entity.type)
            hasErrors = true
        end
        return exportedEntity
    end
    return nil
end

--- @param bundle DataBundle
local function load_single_bundle(bundle, bundleImports)
    local bundleEntities = {}
    for _, data in ipairs(bundle.data or {}) do
        local loader = entity_types[data.type]
        if not loader then
            print('ERROR: No known loader for entity type ' .. data.type)
            return false
        end

        local previousInstance = entities_by_id[data.type][data.id]
        local newEntity = import_entity(loader, data, previousInstance)
        newEntity = create_entity(newEntity, bundle.name, true)
        entity_tracker[newEntity].dirty = false
        if newEntity ~= previousInstance then
            bundleImports[data.type] = bundleImports[data.type] or {}
            bundleImports[data.type][#bundleImports[data.type]+1] = newEntity
        end
        bundleEntities[#bundleEntities+1] = newEntity
    end

    --- @type BundleRuntimeData
    local newBundle = {
        info = {
            name = bundle.name,
            author = bundle.author,
            description = bundle.description,
            created_at = bundle.created_at,
            updated_at = bundle.updated_at,
        },
        dirty = false,
        modifications = {},
        entities = bundleEntities,
        initial_insert_ids = bundle.initial_insert_ids or {},
        next_insert_ids = {},
    }
    for t, et in pairs(entity_types) do
        if not newBundle.initial_insert_ids[t] then
            newBundle.initial_insert_ids[t] = generate_random_initial_insert_id(t)
        end
        newBundle.next_insert_ids[t] = newBundle.initial_insert_ids[t]
    end
    activeBundles[#activeBundles+1] = newBundle
    if utils.table_find_index(allBundles, function (b) return b.name == bundle.name end) == 0 then
        allBundles[#allBundles+1] = bundle
    end
    return true
end

local function load_single_bundle_safe(bundle, bundleImports)
    load_single_bundle(bundle, bundleImports) if true then return true end
    local success, result = pcall(function () load_single_bundle(bundle, bundleImports) end)
    if success then
        print('Loaded bundle', bundle.name)
        return true
    elseif result then
        print('ERROR while loading bundle ' .. bundle.name .. ':')
        print(tostring(result))
        re.msg('Failed to load data bundle ' .. bundle.name .. ':\n\n' .. tostring(result))
        return false
    else
        print('ERROR: bundle ' .. bundle.name .. ' failed to load.')
        re.msg('Failed to load data bundle ' .. bundle.name .. ': unknown error')
        return false
    end
end

local function refresh_bundles_enum()
    local bundleEnumItems = {
        { 0, '', '<no bundle>' }
    }
    for idx, bundle in ipairs(activeBundles) do
        bundleEnumItems[#bundleEnumItems+1] = { idx, bundle.info.name }
    end
    enums.replace_items(bundles_enum, bundleEnumItems, false)
end

local function refresh_enums()
    refresh_bundles_enum()
    for _, enum in pairs(entity_enums) do
        enum.resort()
    end
end

local function load_data_bundles()
    local storedBundles = fs.glob(core.get_glob_regex('bundle'))
    local configData = internal.config.data
    local orders = configData.bundle_order
    enums.replace_items(bundles_enum, {}, false)
    local orderedBundles = {} --- @type DataBundle[]
    local unorderedBundles = {} --- @type DataBundle[]
    for _, bundlePath in ipairs(storedBundles) do
        local bundle = json.load_file(bundlePath) --- @type DataBundle
        if bundle and bundle.name then
            local orderIdx = utils.table_index_of(orders, bundle.name)
            if orderIdx == 0 then
                unorderedBundles[#unorderedBundles+1] = bundle
            else
                orderedBundles[#orderedBundles+1] = bundle
            end
        else
            if bundle ~= nil then
                -- invalidBundles[#invalidBundles+1] = bundlePath
                print('ERROR: invalid data bundle: ' .. bundlePath)
            end
        end
    end

    table.sort(orderedBundles, function (a, b) return utils.table_index_of(orders, a.name) > utils.table_index_of(orders, b.name) end)

    for _, bundle in ipairs(unorderedBundles) do
        orderedBundles[#orderedBundles + 1] = bundle
        configData.bundle_order[#configData.bundle_order + 1] = bundle.name
    end

    if #unorderedBundles > 0 then
        internal.config.save()
    end

    local bundleImports = {}
    for _, bundle in ipairs(orderedBundles) do
        allBundles[#allBundles+1] = bundle
        local settings = configData.bundle_settings[bundle.name]
        if not settings or not settings.disabled then
            load_single_bundle_safe(bundle, bundleImports)
        end
    end

    refresh_enums()
    events.emit('data_imported', bundleImports)
end

--- @param entityData EntityImportData
--- @param bundleName string
--- @return DBEntity|nil
local function load_entity(entityData, bundleName)
    local bundle = get_active_bundle_by_name(bundleName)
    if not bundle then
        print('ERROR: Data bundle not found: ' .. bundleName)
        return nil
    end
    local importer = entity_types[entityData.type]
    if bundle and importer then
        local newEntity = create_entity(import_entity(importer, entityData), bundleName)
        events.emit('data_imported', { [entityData.type] = {newEntity} })
        entity_enums[entityData.type].resort()
        return newEntity
    end
    return nil
end

local function get_bundle_save_path(bundleName)
    return databundle_dir .. bundleName .. '.json'
end

---@param bundleName string
local function save_bundle(bundleName)
    local bundle = get_active_bundle_by_name(bundleName)
    if not bundle then
        print("Can't save unknow bundle " .. bundleName)
        return
    end

    bundle.info.updated_at = utils.get_irl_timestamp(true)

    --- @type DataBundle
    local outBundle = {
        author = bundle.info.author,
        description = bundle.info.description,
        name = bundle.info.name,
        enums = {},
        data = {},
        created_at = bundle.info.created_at,
        updated_at = bundle.info.updated_at,
        initial_insert_ids = bundle.initial_insert_ids,
        game_version = core.game.version,
    }
    local hasErrors = false
    for _, entity in ipairs(bundle.entities) do
        local entType = entity_types[entity.type]

        local exportedEntity = entType.export(entity)
        if exportedEntity then
            exportedEntity.type = entity.type
            exportedEntity.id = entity.id
            exportedEntity.label = entity.label
            outBundle.data[#outBundle.data+1] = exportedEntity
        else
            print('ERROR: Failed to export entity ' .. entity.id .. ' of type ' .. entity.type)
            hasErrors = true
        end
    end

    if not hasErrors then
        json.dump_file(get_bundle_save_path(outBundle.name), outBundle)
        for _, e in ipairs(bundle.entities) do
            mark_entity_dirty(e, false)
        end
        bundle.dirty = false
    else
        print('ERROR: aborting bundle save due to errors')
    end
end

--- @param name string
---@return BundleRuntimeData|nil
local function create_bundle(name)
    local exists = get_bundle_by_name(name)
    if exists then
        re.msg('Bundle with name ' .. name .. ' already exists!')
        return
    end

    --- @type BundleRuntimeData
    local bundle = {
        info = {
            name = name,
            author = internal.config.data.editor.author_name,
            description = internal.config.data.editor.author_description,
            is_revertable = false,
            created_at = utils.get_irl_timestamp(true),
            updated_at = utils.get_irl_timestamp(true),
        },
        dirty = false,
        entities = {},
        modifications = {},
        next_insert_ids = {},
        initial_insert_ids = {},
    }
    for t, et in pairs(entity_types) do
        bundle.initial_insert_ids[t] = generate_random_initial_insert_id(t)
        bundle.next_insert_ids[t] = bundle.initial_insert_ids[t]
    end
    activeBundles[#activeBundles+1] = bundle
    allBundles[#allBundles+1] = {
        author = bundle.info.author,
        created_at = bundle.info.created_at,
        updated_at = bundle.info.updated_at,
        name = name,
        initial_insert_ids = bundle.initial_insert_ids,
        data = {},
        enums = {},
        game_version = core.game.version,
    }
    save_bundle(name)
    internal.config.data.bundle_order[#internal.config.data.bundle_order + 1] = name
    internal.config.save()
    refresh_bundles_enum()

    events.emit('bundle_created', bundle)
    return bundle
end

--- @param name string
local function set_active_bundle(name)
    if get_bundle_by_name(name) then
        internal.config.data.editor.active_bundle = name
        _userdata_DB.editor.active_bundle = name
        internal.config.save()
    end
end

local function get_entity_types()
    return entity_types
end

--- @param name string
--- @param config EntityTypeConfig
local function register_entity_type(name, config)
    entity_types[name] = config
    entities_by_id[name] = entities_by_id[name] or {}
    local enum = config.replaced_enum and enums.get_enum(config.replaced_enum, true) or enums.create_enum({ ['<unset>'] = -1 }, name)
    if not enum.labelToValue['<unset>'] and not enum.valueToLabel[-1] then
        enum.labelToValue['<unset>'] = -1
    else
        enum.set_display_label(-1, '<unset>')
    end
    if not enum.valueToDisplayLabels then enum.valueToDisplayLabels = {} end
    entity_enums[name] = enum
    -- print('Registered entity type ', name)
end

--- Remove an entity from a bundle.
--- If that bundle is the entity's sole bundle, it will get deleted from the game as well if it's not a basegame one.
--- If another bundle contains the entity, it will be retained and tranferred to that one.
--- @param obj DBEntity
--- @param bundleName string
local function delete_entity(obj, bundleName)
    local entity = entity_tracker[obj]

    if not entity then
        print('entity not found', obj.id, obj.type)
        return
    end

    local type = entity_types[entity.type]

    -- if it's the active bundle for the entity then mark the next one in order as its main bundle and re-import
    -- if it isn't the active bundle, just remove from bundle
    -- if there is no other bundle, delete entity

    local previousActiveBundle = get_active_bundle_by_name(entity.bundle)
    local bundleToRemoveFrom = get_active_bundle_by_name(bundleName)
    if bundleToRemoveFrom and utils.table_remove(bundleToRemoveFrom.entities, obj) then
        bundleToRemoveFrom.dirty = true
    else
        print('ERROR: Bundle ' .. tostring(bundleName) .. ' does not contain entity ' .. entity.type .. ' ' .. obj.id)
        return
    end

    local nextBundle = get_bundle_containing_entity(obj)

    if not nextBundle then
        if type.delete then
            local deleteStatus = type.delete(obj)
            if deleteStatus == nil or deleteStatus == 'ok' then
                print('Deleted entity ', entity.type, obj.id, obj.label)
                entities_by_id[entity.type][obj.id] = nil
                local label = entity_enums[entity.type].valueToLabel[obj.id]
                entity_enums[entity.type].labelToValue[label or obj.label] = nil
                entity_enums[entity.type].valueToLabel[obj.id] = nil
                entity_enums[entity.type].valueToDisplayLabels[obj.id] = nil
                entity_tracker[obj] = nil
                entity_enums[entity.type].resort()
            elseif deleteStatus == 'forget' then
                print('Forgetting entity ', entity.type, obj.id, obj.label)
                internal.need_restart_for_clean_data = true
                entity.bundle = nil
                entities_by_id[entity.type][obj.id] = nil
                local label = entity_enums[entity.type].valueToLabel[obj.id]
                entity_enums[entity.type].labelToValue[label or obj.label] = nil
                entity_enums[entity.type].valueToLabel[obj.id] = nil
                entity_enums[entity.type].valueToDisplayLabels[obj.id] = nil
                entity_tracker[obj] = nil
                entity_enums[entity.type].resort()
            elseif deleteStatus == 'error' then
                print("ERROR: entity " .. entity.type .. ': ' .. obj.label .. " failed to delete ")
                internal.need_restart_for_clean_data = true
                entity.bundle = nil
                re.msg('Failed to cleanly delete entity ' .. entity.type .. ':  ' .. obj.label .. '. Restart the game to revert any changes to the basegame data.')
            elseif deleteStatus == 'not_deletable' then
                print("Entity " .. entity.type .. ': ' .. obj.label .. " is not deletable")
                internal.need_restart_for_clean_data = true
                entity.bundle = nil
            end
        else
            entity.bundle = nil
            internal.need_restart_for_clean_data = true
            re.msg('Entity ' .. entity.type .. ': ' .. obj.label .. ' is not dynamically deletable. Restart the game to revert any changes to the basegame data.')
        end
    elseif previousActiveBundle == bundleToRemoveFrom then
        -- TODO re-import entity from nextBundle's data (if we had the previous data stored somewhere separate, or well from disk)
        entity.bundle = nextBundle.info.name
    end
end

--- @return table<integer, DBEntity>
local function get_all_entities_map(entityType)
    return entities_by_id[entityType] or {}
end

--- @param entityType string
--- @param entityId integer
--- @return DBEntity|nil
--- @overload fun(entityType: 'message_group', entityId: number): MessageGroupEntity|nil
--- @overload fun(entityType: 'quest', entityId: number): QuestDataSummary|nil
--- @overload fun(entityType: 'quest_processor', entityId: number): QuestProcessorData|nil
--- @overload fun(entityType: 'quest_reward', entityId: number): QuestRewardData|nil
--- @overload fun(entityType: 'talk_event', entityId: number): TalkEventData|nil
--- @overload fun(entityType: 'quest_dialogue_pack', entityId: number): QuestDialogueEntity|nil
--- @overload fun(entityType: 'event', entityId: number): Event|nil
--- @overload fun(entityType: 'event_context', entityId: number): EventContext|nil
--- @overload fun(entityType: 'custom_script', entityId: number): CustomScriptEntity|nil
local function get_entity(entityType, entityId)
    return entities_by_id[entityType] and entities_by_id[entityType][entityId]
end

--- @return DBEntity[]
local function get_all_entities(entityType)
    return utils.table_values(entities_by_id[entityType])
end

--- @param entityType string
--- @param filter fun(entity: DBEntity): boolean
--- @return DBEntity[]
--- @overload fun(entityType: 'message_group', filter: fun(e: DBEntity): boolean): MessageGroupEntity[]
--- @overload fun(entityType: 'quest', filter: fun(e: DBEntity): boolean): QuestDataSummary[]
--- @overload fun(entityType: 'quest_processor', filter: fun(e: DBEntity): boolean): QuestProcessorData[]
--- @overload fun(entityType: 'quest_reward', filter: fun(e: DBEntity): boolean): QuestRewardData[]
--- @overload fun(entityType: 'talk_event', filter: fun(e: DBEntity): boolean): TalkEventData[]
--- @overload fun(entityType: 'quest_dialogue_pack', filter: fun(e: DBEntity): boolean): QuestDialogueEntity[]
--- @overload fun(entityType: 'event', filter: fun(e: DBEntity): boolean): Event[]
--- @overload fun(entityType: 'event_context', filter: fun(e: DBEntity): boolean): EventContext[]
--- @overload fun(entityType: 'custom_script', filter: fun(e: DBEntity): boolean): CustomScriptEntity[]
local function get_entities_where(entityType, filter)
    local results = {}
    for _, ent in pairs(entities_by_id[entityType] or {}) do
        if filter(ent) then
            results[#results+1] = ent
        end
    end
    return results
end

--- @return EnumSummary
local function get_entity_enum(entityType)
    return entity_enums[entityType]
end

--- @param entity DBEntity
--- @return string|nil
local function get_entity_bundle(entity)
    local tracked = entity_tracker[entity]
    return tracked and tracked.bundle
end

--- @param entity DBEntity
--- @param newBundleName string
local function add_entity_to_bundle(entity, newBundleName)
    local tracked = entity_tracker[entity]
    if tracked.bundle == newBundleName then return end
    if newBundleName == '' or newBundleName == nil then return end

    local newBundle = get_active_bundle_by_name(newBundleName)
    if not tracked or not newBundle then
        print('ERROR: Untracked entity or unknown bundle')
        return
    end

    newBundle.entities[#newBundle.entities+1] = entity
    newBundle.dirty = true
    if tracked.bundle == nil then
        tracked.bundle = newBundleName
        tracked.dirty = true
    end
end

--- @param entity DBEntity
--- @param newBundleName string|nil
local function set_entity_bundle(entity, newBundleName)
    local tracked = entity_tracker[entity]
    if tracked.bundle == newBundleName then return end

    if newBundleName == '' or newBundleName == nil then
        local curBundle = get_active_bundle_by_name(tracked.bundle)
        if curBundle then
            curBundle.dirty = true
            utils.table_remove(curBundle.entities, entity)
            local nextBundle = get_bundle_containing_entity(entity)
            tracked.bundle = nextBundle and nextBundle.info.name or nil
        end
        return
    end
    local newBundle = get_active_bundle_by_name(newBundleName)
    if not tracked or not newBundle then
        print('ERROR: Untracked entity or unknown bundle')
        return
    end

    newBundle.entities[#newBundle.entities+1] = entity
    tracked.bundle = newBundleName
    newBundle.dirty = true
    tracked.dirty = true
end

--- comment
--- @param type string
--- @param id integer
local function reload_entity(type, id)
    local entity = entities_by_id[type][id]
    if not entity then
        re.msg('Unknown entity ' .. id .. ' of type ' .. type)
        return
    end

    local tracked = entity_tracker[entity]
    local bundle = get_active_bundle_by_name(tracked.bundle)
    if not bundle then
        return re.msg("Entity is not contained in a bundle, can't reload")
    end

    local bundleData = json.load_file(get_bundle_save_path(bundle.info.name)) --- @type DataBundle|nil
    if not bundleData then
        return re.msg("Bundle is empty or not yet saved to disk")
    end

    local storedEntity = utils.table_find(bundleData.data, function (item) return item.id == id and item.type == type end)
    if not storedEntity then
        return re.msg('Bundle ' .. bundle.info.name .. ' does not contain the entity')
    end

    local loader = entity_types[type]
    local newEntity = import_entity(loader, storedEntity, entity)
    newEntity = create_entity(newEntity, bundle.info.name, true)
    if newEntity ~= entity then
        print('WARNING received new entity instance on reloading entity... This might not be good?', type, id)
    end
    events.emit('data_imported', { [type] = {newEntity} })
    entity_tracker[newEntity].dirty = false
end

--- @param currentName string
--- @param newName string
local function rename_bundle(currentName, newName)
    local targetBundle = get_bundle_by_name(newName)
    if targetBundle then
        print("ERROR: Can't rename bundle - bundle already exists " .. newName)
        return
    end

    local bundle = get_active_bundle_by_name(currentName)
    if not bundle then
        print('ERROR: bundle does not exist: ' .. currentName)
        return
    end

    bundle.info.name = newName
    for _, ent in ipairs(bundle.entities) do
        local tracked = entity_tracker[ent]
        if tracked.bundle == currentName then
            tracked.bundle = newName
        end
    end
    -- TODO update load order and bundle settings
    save_bundle(newName)
    refresh_enums()
    fs.write(get_bundle_save_path(currentName), 'null')
end

--- Enable or disable a data bundle. When disabling, `delete_entity` will be called for all referenced entities.
--- @param bundleName string
--- @param enabled boolean
local function set_bundle_enabled(bundleName, enabled)
    local activeBundle = get_active_bundle_by_name(bundleName)
    local allBundleEntry = get_bundle_by_name(bundleName)
    if not allBundleEntry then
        re.msg('Bundle does not exists: ' .. bundleName)
        return
    end

    if (activeBundle ~= nil) == enabled then
        -- nothing to do here, it's already where we want it
        return
    end

    local settings = internal.config.data.bundle_settings[bundleName] or {}
    settings.disabled = not enabled
    internal.config.data.bundle_settings[bundleName] = settings
    internal.config.save()
    if enabled then
        local bundleImports = {}
        if load_single_bundle_safe(allBundleEntry, bundleImports) then
            refresh_enums()
            events.emit('data_imported', bundleImports)
        else
            re.msg('Failed to import re-enabled bundle ' .. bundleName)
        end
    elseif activeBundle then
        -- try remove bundle entities, doing shallow copy cause we're modifying it during iteration
        for _, e in ipairs(utils.table_assign({}, activeBundle.entities)) do
            delete_entity(e, bundleName)
        end

        utils.table_remove(activeBundles, activeBundle)
        refresh_enums()
    end
end

--- @param bundleName1 string
--- @param bundleName2 string
local function swap_bundle_load_order(bundleName1, bundleName2)
    local idx1 = utils.table_find_index(allBundles, function (b) return b.name == bundleName1 end)
    local idx2 = utils.table_find_index(allBundles, function (b) return b.name == bundleName2 end)
    if idx1 ~= 0 and idx2 ~= 0 then
        allBundles[idx1], allBundles[idx2] = allBundles[idx2], allBundles[idx1]
    end

    idx1 = utils.table_find_index(activeBundles, function (b) return b.info.name == bundleName1 end)
    idx2 = utils.table_find_index(activeBundles, function (b) return b.info.name == bundleName2 end)
    if idx1 ~= 0 and idx2 ~= 0 then
        activeBundles[idx1], activeBundles[idx2] = activeBundles[idx2], activeBundles[idx1]
    end

    idx1 = utils.table_index_of(internal.config.data.bundle_order, bundleName1)
    idx2 = utils.table_index_of(internal.config.data.bundle_order, bundleName2)
    if idx1 ~= 0 and idx2 ~= 0 then
        internal.config.data.bundle_order[idx1], internal.config.data.bundle_order[idx2] = internal.config.data.bundle_order[idx2], internal.config.data.bundle_order[idx1]
        internal.config.save()
    end
end

--- Delete a bundle and all its entities
--- @param bundleName string
local function delete_bundle(bundleName)
    local allBundleEntry = get_bundle_by_name(bundleName)
    set_bundle_enabled(bundleName, false)

    if allBundleEntry then
        utils.table_remove(allBundles, allBundleEntry)
        fs.write(get_bundle_save_path(bundleName), 'null')
        refresh_enums()
    end

    if utils.table_remove(internal.config.data.bundle_order, bundleName) then
        internal.config.save()
    end
end

local function reload_all_bundles()
    -- ideally we would like to unload all active bundles in reverse load order
    -- also check if there's any non-revertable ones active and figure out what to do in those cases
    utils.clear_table(activeBundles)
    utils.clear_table(allBundles)
    load_data_bundles()
    events.emit('bundles_loaded')
end

--- @param bundleName string
--- @return boolean enabled
local function get_bundle_enabled(bundleName)
    return get_active_bundle_by_name(bundleName) ~= nil
end

--- @param bundleName string
--- @param entityType string
--- @return integer
local function get_next_insert_id(bundleName, entityType)
    local bundle = get_active_bundle_by_name(bundleName)
    local nextId
    if bundle then
        nextId = bundle.next_insert_ids[entityType] or generate_random_initial_insert_id(entityType)
        while get_entity(entityType, nextId) do
            nextId = nextId + 1
        end
        bundle.next_insert_ids[entityType] = nextId
    else
        local type_config = entity_types[entityType]
        nextId = type_config.insert_id_range[1]
        while get_entity(entityType, nextId) do
            nextId = nextId + 1
        end
    end
    return nextId
end

---Create and if possible inject a new entity. A new ID will be automatically generated for the given data bundle.
---@param type string
---@param bundle string
---@param entityData table|nil
---@return DBEntity|nil
local function insert_new_entity(type, bundle, entityData)
    local id = entityData and entityData.id
    if id == nil then id = get_next_insert_id(bundle, type) end
    local entity = load_entity(utils.table_assign(entityData or {}, {
        id = id,
        type = type,
    }), bundle)
    -- print('created new entity', type, bundle, json.dump_string(entity))
    return entity
end

--- Triggers the import function of the entity, to force apply any changes made to the entity
--- @param entity DBEntity
--- @return boolean success
local function reimport_entity(entity)
    local tt = entity_types[entity.type]
    if tt then
        tt.import(tt.export(entity), entity)
        events.emit('data_imported', {[entity.type] = { entity }})
        return true
    end
    return false
end

--- Generate the label for a possibly still unregistered entity
--- @param entity DBEntity
--- @return string
local function generate_entity_label(entity)
    local tt = entity_types[entity.type]
    if tt then
        return tt.generate_label and tt.generate_label(entity) or entity.label or 'unlabeled'
    end
    return '<unknown>'
end

local function finish_database_init()
    print('Initializing content editor type info...')
    typecache.load()
    for _, et in pairs(entity_types) do
        for _, t in ipairs(et.root_types or {}) do
            typecache.get(t)
        end
    end

    print('Starting content import for pre-existing game data...')

    -- this event is intended for plugins to fetch any current pre-existing game state and initialize the already present instances
    events.emit('get_existing_data')

    print('All content entity types ready, starting load...')
    if core.editor_enabled then
        enums.refresh()
    end

    load_data_bundles()
    events.emit('bundles_loaded')

    typecache.save_if_invalid()
    db_ready = true
    events.emit('ready')
end

re.on_application_entry('UpdateBehavior', function ()
    if not db_ready and not db_failed and next(entity_types) and core.game.game_data_is_ready() then
        -- db_failed = true finish_database_init() if true then return end
        -- if we have at least one entity type registered, we should be confident that they're all there and ready
        -- if we wanted to allow a provider to delay, we can add a flag to the entity type later
        local success, msg = pcall(finish_database_init)
        if not success then
            re.msg("Heya!\n\nSo the content database failed to start up properly.\nMaybe there's some invalid data, maybe there's a code issue, who knows. There might've been more errors logged before this one.\nMaybe try disabling any content database related mods one by one and see which one causes issues. (and let the mod author know pls)\nError info:\n\n" .. tostring(msg))
            db_failed = true
        end
    end
end)

--- @class UserdataDB
_userdata_DB.database = {
    is_ready = function () return db_ready end,

    get_entity_types = get_entity_types,
    register_entity_type = register_entity_type,

    create_bundle = create_bundle,
    save_bundle = save_bundle,
    bundle_has_unsaved_changes = bundle_check_unsaved_changes,
    get_active_bundle_by_name = get_active_bundle_by_name,
    get_bundle_by_name = get_bundle_by_name,
    set_active_bundle = set_active_bundle,
    rename_bundle = rename_bundle,
    get_bundle_entity_types = get_bundle_entity_types,
    get_bundle_entities = get_bundle_entities,
    delete_bundle = delete_bundle,
    get_bundle_save_path = get_bundle_save_path,
    get_bundle_enabled = get_bundle_enabled,
    set_bundle_enabled = set_bundle_enabled,
    swap_bundle_load_order = swap_bundle_load_order,
    reload_all_bundles = reload_all_bundles,
    bundles_enum = bundles_enum,
    bundles_order_list = allBundles,

    get_entity = get_entity,
    create_entity = create_entity,
    load_entity = load_entity,
    insert_new_entity = insert_new_entity,
    reimport_entity = reimport_entity,
    export_entity = export_entity,
    generate_entity_label = generate_entity_label,
    get_next_insert_id = get_next_insert_id,
    delete_entity = delete_entity,
    reload_entity = reload_entity,
    mark_entity_dirty = mark_entity_dirty,
    register_pristine_entity = register_pristine_entity,
    entity_has_unsaved_changes = entity_check_unsaved_changes,
    get_entity_bundle = get_entity_bundle,
    set_entity_bundle = set_entity_bundle,
    add_entity_to_bundle = add_entity_to_bundle,

    check_any_unsaved_changes = check_any_unsaved_changes,
    get_all_entities = get_all_entities,
    get_all_entities_map = get_all_entities_map,
    get_entities_where = get_entities_where,
    get_entity_enum = get_entity_enum,

    events = events,
}

local load_order_handler = require('content_editor._load_order_handler')(_userdata_DB.database)
re.on_draw_ui(function ()
    if imgui.tree_node('Content database') then
        imgui.text('Version: ' .. table.concat(core.VERSION, '.'))

        if internal.need_restart_for_clean_data then
            imgui.text_colored('Some changes need a full game restart to apply.', core.get_color('danger'))
        elseif internal.need_script_reset then
            imgui.text_colored('Some changes need a script reset.', core.get_color('danger'))
        end

        if imgui.button('Editor: ' .. (internal.config.data.editor.enabled and 'enabled' or 'disabled')) then
            internal.config.data.editor.enabled = not internal.config.data.editor.enabled
            internal.config.save()
        end
        if internal.config.data.editor.enabled ~= core.editor_enabled then
            imgui.text_colored('Reset scripts to apply editor setting change!', core.get_color('warning'))
        end
        if core.editor_enabled and imgui.button('Toggle editor windows') then
            internal.config.data.editor.show_window = not internal.config.data.editor.show_window
            internal.config.save()
        end
        load_order_handler()
        imgui.tree_pop()
    end
end)

return _userdata_DB.database
