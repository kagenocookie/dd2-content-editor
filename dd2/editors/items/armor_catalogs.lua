local core = require('content_editor.core')
local udb = require('content_editor.database')
local utils = require('content_editor.utils')
local import_handlers = require('content_editor.import_handlers')
local enums = require('content_editor.enums')

local CharacterEditManager = sdk.get_managed_singleton("app.CharacterEditManager") --- @type app.CharacterEditManager
local CharacterManager = sdk.get_managed_singleton('app.CharacterManager') --- @type app.CharacterManager
local PawnManager = sdk.get_managed_singleton('app.PawnManager') --- @type app.PawnManager

--- @class ArmorEntity : DBEntity
--- @field Mesh app.PrefabController|nil
--- @field Chain app.PrefabController|nil
--- @field Clsp app.PrefabController|nil
--- @field Gpuc app.PrefabController|nil

--- @class SkinEntity : DBEntity
--- @field Skin app.PrefabController|nil

local genders = {
    Female = 1910070090,
    Male = 2776536455,
}

local species = {
    Human = 2501532887,
    Beastren = 3666037007,
}

-- There are 2 distinct IDs per part
-- mesh ID: shared between mesh, chain, clsp and gpuc; there is always a mesh, the rest are optional
-- skin ID: standalone by itself

local armorCatalogs = {
    TopsBdSkin = {
        { name = 'Skin', dict = '_TopsBdSkinCatalog', enum = 'app.CharacterEditDefine.TopsBdSkinID', styleField = {'_BdSkinID', '_BdSubSkinID'}, components = {} },
    },
    TopsBd = {
        { name = 'Mesh', dict = '_TopsBdMeshCatalog', enum = 'app.CharacterEditDefine.TopsBdMeshID', styleField = {'_BdMeshID', '_BdSubMeshID'} },
        { name = 'Chain', dict = '_TopsBdChainCatalog' },
        { name = 'Clsp', dict = '_TopsBdCollisionShapePresetCatalog' },
        { name = 'Gpuc', dict = '_TopsBdGpuClothCatalog' },
    },
    TopsBtSkin = {
        { name = 'Skin', dict = '_TopsBtSkinCatalog', enum = 'app.CharacterEditDefine.TopsBtSkinID', styleField = {'_BtSkinID', '_BtSubSkinID'} },
    },
    TopsBt = {
        { name = 'Mesh', dict = '_TopsBtMeshCatalog', enum = 'app.CharacterEditDefine.TopsBtMeshID', styleField = {'_BtMeshID', '_BtSubMeshID'} },
        { name = 'Chain', dict = '_TopsBtChainCatalog' },
        { name = 'Clsp', dict = '_TopsBtCollisionShapePresetCatalog' },
    },
    TopsWbSkin = {
        { name = 'Skin', dict = '_TopsWbSkinCatalog', enum = 'app.CharacterEditDefine.TopsWbSkinID', styleField = {'_WbSkinID', '_WbSubSkinID'} },
    },
    TopsWb = {
        { name = 'Mesh', dict = '_TopsWbMeshCatalog', enum = 'app.CharacterEditDefine.TopsWbMeshID', styleField = {'_WbMeshID', '_WbSubMeshID'} },
        { name = 'Chain', dict = '_TopsWbChainCatalog' },
        { name = 'Clsp', dict = '_TopsWbCollisionShapePresetCatalog' },
        { name = 'Gpuc', dict = '_TopsWbGpuClothCatalog' },
    },
    TopsAmSkin = {
        { name = 'Skin', dict = '_TopsAmSkinCatalog', enum = 'app.CharacterEditDefine.TopsAmSkinID', styleField = {'_AmSkinID', '_AmSubSkinID'} },
    },
    TopsAm = {
        { name = 'Mesh', dict = '_TopsAmMeshCatalog', enum = 'app.CharacterEditDefine.TopsAmMeshID', styleField = {'_AmMeshID', '_AmSubMeshID'} },
        { name = 'Chain', dict = '_TopsAmChainCatalog' },
        { name = 'Clsp', dict = '_TopsAmCollisionShapePresetCatalog' },
        { name = 'Gpuc', dict = '_TopsAmGpuClothCatalog' },
    },
    PantsWlSkin = {
        { name = 'Skin', dict = '_PantsWlSkinCatalog', enum = 'app.CharacterEditDefine.PantsWlSkinID', styleField = {'_WlSkinID', '_WlSubSkinID'} },
    },
    PantsWl = {
        { name = 'Mesh', dict = '_PantsWlMeshCatalog', enum = 'app.CharacterEditDefine.PantsWlMeshID', styleField = {'_WlMeshID', '_WlSubMeshID'} },
        { name = 'Chain', dict = '_PantsWlChainCatalog' },
        { name = 'Clsp', dict = '_PantsWlCollisionShapePresetCatalog' },
        { name = 'Gpuc', dict = '_PantsWlGpuClothCatalog' },
    },
    PantsLgSkin = {
        { name = 'Skin', dict = '_PantsLgSkinCatalog', enum = 'app.CharacterEditDefine.PantsLgSkinID', styleField = {'_LgSkinID', '_LgSubSkinID'} },
    },
    PantsLg = {
        { name = 'Mesh', dict = '_PantsLgMeshCatalog', enum = 'app.CharacterEditDefine.PantsLgMeshID', styleField = {'_LgMeshID', '_LgSubMeshID'} },
        { name = 'Chain', dict = '_PantsLgChainCatalog' },
        { name = 'Clsp', dict = '_PantsLgCollisionShapePresetCatalog' },
        { name = 'Gpuc', dict = '_PantsLgGpuClothCatalog' },
    },
    HelmSkin = {
        { name = 'Skin', dict = '_HelmSkinCatalog', enum = 'app.CharacterEditDefine.HelmSkinID', styleField = {'_SkinID', '_SubSkinID'} },
    },
    Helm = {
        { name = 'Mesh', dict = '_HelmMeshCatalog', enum = 'app.CharacterEditDefine.HelmMeshID', styleField = {'_MeshID', '_SubMeshID'} },
        { name = 'Chain', dict = '_HelmChainCatalog', speciesDict = true },
        { name = 'Clsp', dict = '_HelmCollisionShapePresetCatalog' },
        { name = 'Gpuc', dict = '_HelmGpuClothCatalog', speciesDict = true },
        { name = 'WrapDeformer', dict = '_HelmWrapDeformerCatalog', speciesGenderDict = true, hashCatalog = '_HelmWrapDeformerCatalogHash' },
    },
    MantleSkin = {
        { name = 'Skin', dict = '_MantleSkinCatalog', enum = 'app.CharacterEditDefine.MantleSkinID', styleField = {'_SkinID'} },
    },
    Mantle = {
        { name = 'Mesh', dict = '_MantleMeshCatalog', enum = 'app.CharacterEditDefine.MantleMeshID', styleField = {'_MeshID'} },
        { name = 'Chain', dict = '_MantleChainCatalog' },
        { name = 'Clsp', dict = '_MantleClspCatalog' },
        { name = 'Gpuc', dict = '_MantleGpuClothCatalog' },
        { name = 'ShellFur', dict = '_MantleShellFurCatalog' },
    },
    FacewearSkin = {
        { name = 'Skin', dict = '_FacewearSkinCatalog', enum = 'app.CharacterEditDefine.FacewearSkinID' },
    },
    Facewear = {
        { name = 'Mesh', dict = '_FacewearMeshCatalog', enum = 'app.CharacterEditDefine.FacewearMeshID' },
        { name = 'MeshBeast', dict = '_FacewearMeshBeastCatalog' },
    },
    UnderwearSkin = {
        { name = 'Skin', dict = '_UnderwearSkinCatalog', enum = 'app.CharacterEditDefine.UnderwearSkinID' },
    },
    Underwear = {
        { name = 'Mesh', dict = '_UnderwearMeshCatalog', enum = 'app.CharacterEditDefine.UnderwearMeshID' },
    },
    BackpackSkin = {
        { name = 'Skin', dict = '_BackpackSkinCatalog', enum = 'app.CharacterEditDefine.BackpackSkinID' },
    },
    Backpack = {
        { name = 'Mesh', dict = '_BackpackMeshCatalog', enum = 'app.CharacterEditDefine.BackpackMeshID' },
        { name = 'Chain', dict = '_BackpackChainCatalog' },
        { name = 'Clsp', dict = '_BackpackCollisionShapePresetCatalog' },
    },
}
local recordTypes = utils.get_sorted_table_keys(armorCatalogs)

for armorMeshType, fieldData in pairs(armorCatalogs) do
    local sourceEnum = enums.get_enum(fieldData[1].enum).valueToLabel
    for i, entry in ipairs(fieldData) do
        local components = { dict = 'a' }
        if entry.speciesGenderDict then
            components[#components+1] = { dict = CharacterEditManager[entry.dict][species.Human][genders.Female], hashCatalog = entry.hashCatalog, name = entry.name .. '_Human_Female' }
            components[#components+1] = { dict = CharacterEditManager[entry.dict][species.Human][genders.Male], hashCatalog = entry.hashCatalog, name = entry.name .. '_Human_Male' }
            components[#components+1] = { dict = CharacterEditManager[entry.dict][species.Beastren][genders.Female], hashCatalog = entry.hashCatalog, name = entry.name .. '_Beastren_Female' }
            components[#components+1] = { dict = CharacterEditManager[entry.dict][species.Beastren][genders.Male], hashCatalog = entry.hashCatalog, name = entry.name .. '_Beastren_Male' }
        elseif entry.speciesDict then
            components[#components+1] = { dict = CharacterEditManager[entry.dict][species.Human], keys = { species.Human }, name = entry.name .. '_Human' }
            components[#components+1] = { dict = CharacterEditManager[entry.dict][species.Beastren], keys = { species.Beastren }, name = entry.name .. '_Beastren' }
        else
            components[#components+1] = { dict = CharacterEditManager[entry.dict], keys = {}, name = entry.name }
        end
        entry.components = components
        armorCatalogs[armorMeshType][i].components = components
    end

    udb.register_entity_type(armorMeshType, {
        insert_id_range = {1000, 360000},
        import = function (import_data, instance)
            for _, entry in ipairs(fieldData) do
                for _, comp in ipairs(entry.components) do
                    instance[comp.name] = import_handlers.import('app.PrefabController', import_data[comp.name], instance[comp.name])
                    if instance[comp.name] then
                        local entryId = comp.hashCatalog and CharacterEditManager[comp.hashCatalog][instance.id] or instance.id
                        comp.dict[entryId] = instance[comp.name]
                    end
                end
            end
        end,
        export = function (instance)
            local data = {}
            for _, entry in ipairs(fieldData) do
                for _, comp in ipairs(entry.components) do
                    data[comp.name] = import_handlers.export(instance[comp.name], 'app.PrefabController')
                end
            end

            return data
        end,
        delete = function (instance)
            if not udb.is_custom_entity_id(armorMeshType, instance.id) then return 'forget' end
            for _, entry in ipairs(fieldData) do
                -- NOTE: no need to deal with hashLookup-enabled entries here
                -- we never delete basegame entities, and custom ones don't have deformers
                for _, comp in ipairs(entry.components) do
                    comp.dict:Remove(instance.id)
                end
            end
            return 'ok'
        end,
        replaced_enum = fieldData[1].enum,
        root_types = {},
        generate_label = function (entity)
            if sourceEnum[entity.id] then
                return sourceEnum[entity.id] .. ' ' .. entity.id
            end
            return armorMeshType .. ' ' .. entity.id
        end
    })
end

udb.events.on('get_existing_data', function ()
    for armorMeshType, fieldData in pairs(armorCatalogs) do
        for _, fields in ipairs(fieldData) do
            if fields.hashCatalog then
                local hashLookup = CharacterEditManager[fields.hashCatalog]
                local styles = udb.get_all_entities_map(armorMeshType)--[[@as ArmorEntity]]
                local hashField = fields.name .. '_Hash'
                for _, entity in pairs(styles) do
                    if hashLookup:ContainsKey(entity.id) then
                        local deformerHash = hashLookup[entity.id]
                        entity[hashField] = deformerHash

                        for _, comp in ipairs(fields.components) do
                            local pfbCtrl = comp.dict[deformerHash]
                            if pfbCtrl then
                                entity[comp.name] = pfbCtrl
                            end
                        end
                    end
                end
            else
                for _, comp in ipairs(fields.components) do
                    for pair in utils.enumerate(comp.dict) do
                        local id = pair.key
                        local pfbCtrl = pair.value
                        local entity = udb.get_entity(armorMeshType, id)
                        if not entity then
                            entity = udb.register_pristine_entity({
                                id = id,
                                type = armorMeshType,
                            })
                        end
                        entity[comp.name] = pfbCtrl
                    end
                end
            end
        end
    end
end)

if core.editor_enabled then
    local ui = require('content_editor.ui')
    local editor = require('content_editor.editor')

    local styleMatchResults
    --- @param character app.Character
    local function forceUpdateSwapParts(character)
        local partSwapper = character:get_HumanPartSwapper()
        if partSwapper then
            partSwapper:swapTops()
            partSwapper:swapPants()
            partSwapper:swapMantle()
            partSwapper:swapHelm()
            partSwapper:swapUnderwear()
            partSwapper:swapFacewear()
        end
    end

    local function handle_pfb_ctrl_ui(container, name, id, dict)
        local pfbCtrl = container[name] --- @type app.PrefabController|nil
        local path = pfbCtrl and pfbCtrl.get_ResourcePath and pfbCtrl:get_ResourcePath()--[[@as string|nil]]
        local changed, newpath = imgui.input_text(name, path or '')
        if changed then
            if newpath and newpath ~= '' then
                if not pfbCtrl then
                    pfbCtrl = import_handlers.import('app.PrefabController', newpath)
                    container[name] = pfbCtrl
                    dict[id] = pfbCtrl
                    return true
                elseif newpath ~= path then
                    pfbCtrl._Item:set_Path(newpath)
                    return true
                end
            else
                container[name] = nil
                dict[id] = nil
                return true
            end
        end
        return false
    end

    local function showArmorEditor(selectedItem, state)
        --- @cast selectedItem ArmorEntity|SkinEntity
        if imgui.button('Force update meshes') then
            local player = CharacterManager:get_ManualPlayer()
            if player then forceUpdateSwapParts(player) end
            local it = PawnManager._PawnCharacterList:GetEnumerator()
            while it:MoveNext() do forceUpdateSwapParts(it._current) end
        end
        if imgui.is_item_hovered() then imgui.set_tooltip('Will force all mesh parts of the player and pawns to refresh based on the currently defined meshes') end
        imgui.text('ID: ' .. tostring(selectedItem.id))
        local recordData = armorCatalogs[selectedItem.type]
        for _, field in ipairs(recordData) do
            local changed = false
            for _, comp in ipairs(field.components) do
                changed = handle_pfb_ctrl_ui(selectedItem, comp.name, selectedItem.id, comp.dict) or changed
            end
            if changed then
                udb.mark_entity_dirty(selectedItem)
            end
        end
    end
    for armorMeshType, _ in pairs(armorCatalogs) do
        ui.editor.set_entity_editor(armorMeshType, showArmorEditor)
    end

    editor.define_window('armor_catalogs', 'Armor catalogs', function (state)
        _, state.part_type, state.part_type_filter = ui.basic.combo_filterable('Part type', state.part_type, recordTypes, state.part_type_filter or '')
        if state.part_type then
            local recordData = armorCatalogs[state.part_type]

            if editor.active_bundle and imgui.button('Create new') then
                local newEntity = udb.insert_new_entity(state.part_type, editor.active_bundle, {})
                ui.editor.set_selected_entity_picker_entity(state, state.part_type, newEntity)
            end

            local selectedItem = ui.editor.entity_picker(state.part_type, state)

            --- @cast selectedItem ArmorEntity|SkinEntity|nil
            if selectedItem then
                imgui.spacing()
                imgui.indent(8)
                imgui.begin_rect()
                ui.editor.show_entity_metadata(selectedItem)
                showArmorEditor(selectedItem, state)
                imgui.end_rect(4)
                imgui.unindent(8)
                imgui.spacing()

                if recordData[1].styleField and imgui.button('Find style references') then
                    local styleType
                    if state.part_type:sub(1, 4) == 'Tops' then
                        styleType = 'TopsStyle'
                    elseif state.part_type:sub(1, 5) == 'Pants' then
                        styleType = 'PantsStyle'
                    elseif state.part_type:sub(1, 4) == 'Helm' then
                        styleType = 'HelmStyle'
                    elseif state.part_type:sub(1, 6) == 'Mantle' then
                        styleType = 'MantleStyle'
                    end
                    if styleType then
                        local styles = udb.get_entities_where(styleType, function (entity)
                            for _, idField in ipairs(recordData[1].styleField) do
                                --- @cast entity StyleEntity
                                if entity.variants[tostring(genders.Female)] and entity.variants[tostring(genders.Female)][idField] == selectedItem.id
                                or entity.variants[tostring(genders.Male)] and entity.variants[tostring(genders.Male)][idField] == selectedItem.id then
                                    return true
                                end
                            end
                            return false
                        end)

                        styleMatchResults = 'Mesh is used by style matches: ' .. #styles
                        for _, e in ipairs(styles) do
                            styleMatchResults = styleMatchResults .. '\nID ' .. e.id .. ': ' .. e.label
                        end
                    end
                end
                if styleMatchResults then
                    imgui.text(styleMatchResults)
                end
            end
        end
    end)
end