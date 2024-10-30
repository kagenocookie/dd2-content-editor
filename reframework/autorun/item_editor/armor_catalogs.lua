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

-- There are 2 distinct IDs per part
-- mesh ID: shared between mesh, chain, clsp and gpuc; there is always a mesh, the rest are optional
-- skin ID: standalone by itself

local armorCatalogs = {
    TopsBdSkin = {
        { name = 'Skin', id = 'SkinID', dict = '_TopsBdSkinCatalog', enum = 'app.CharacterEditDefine.TopsBdSkinID', styleField = {'_BdSkinID', '_BdSubSkinID'} },
    },
    TopsBd = {
        { name = 'Mesh', id = 'MeshID', dict = '_TopsBdMeshCatalog', enum = 'app.CharacterEditDefine.TopsBdMeshID', styleField = {'_BdMeshID', '_BdSubMeshID'} },
        { name = 'Chain', id = 'ChainID', dict = '_TopsBdChainCatalog' },
        { name = 'Clsp', id = 'ClspID', dict = '_TopsBdCollisionShapePresetCatalog' },
        { name = 'Gpuc', id = 'GpucID', dict = '_TopsBdGpuClothCatalog' },
    },
    TopsBtSkin = {
        { name = 'Skin', id = 'SkinID', dict = '_TopsBtSkinCatalog', enum = 'app.CharacterEditDefine.TopsBtSkinID', styleField = {'_BtSkinID', '_BtSubSkinID'} },
    },
    TopsBt = {
        { name = 'Mesh', id = 'MeshID', dict = '_TopsBtMeshCatalog', enum = 'app.CharacterEditDefine.TopsBtMeshID', styleField = {'_BtMeshID', '_BtSubMeshID'} },
        { name = 'Chain', id = 'ChainID', dict = '_TopsBtChainCatalog' },
        { name = 'Clsp', id = 'ClspID', dict = '_TopsBtCollisionShapePresetCatalog' },
    },
    TopsWbSkin = {
        { name = 'Skin', id = 'SkinID', dict = '_TopsWbSkinCatalog', enum = 'app.CharacterEditDefine.TopsWbSkinID', styleField = {'_WbSkinID', '_WbSubSkinID'} },
    },
    TopsWb = {
        { name = 'Mesh', id = 'MeshID', dict = '_TopsWbMeshCatalog', enum = 'app.CharacterEditDefine.TopsWbMeshID', styleField = {'_WbMeshID', '_WbSubMeshID'} },
        { name = 'Chain', id = 'ChainID', dict = '_TopsWbChainCatalog' },
        { name = 'Clsp', id = 'ClspID', dict = '_TopsWbCollisionShapePresetCatalog' },
        { name = 'Gpuc', id = 'GpucID', dict = '_TopsWbGpuClothCatalog' },
    },
    TopsAmSkin = {
        { name = 'Skin', id = 'SkinID', dict = '_TopsAmSkinCatalog', enum = 'app.CharacterEditDefine.TopsAmSkinID', styleField = {'_AmSkinID', '_AmSubSkinID'} },
    },
    TopsAm = {
        { name = 'Mesh', id = 'MeshID', dict = '_TopsAmMeshCatalog', enum = 'app.CharacterEditDefine.TopsAmMeshID', styleField = {'_AmMeshID', '_AmSubMeshID'} },
        { name = 'Chain', id = 'ChainID', dict = '_TopsAmChainCatalog' },
        { name = 'Clsp', id = 'ClspID', dict = '_TopsAmCollisionShapePresetCatalog' },
        { name = 'Gpuc', id = 'GpucID', dict = '_TopsAmGpuClothCatalog' },
    },
    PantsWlSkin = {
        { name = 'Skin', id = 'SkinID', dict = '_PantsWlSkinCatalog', enum = 'app.CharacterEditDefine.PantsWlSkinID', styleField = {'_WlSkinID', '_WlSubSkinID'} },
    },
    PantsWl = {
        { name = 'Mesh', id = 'MeshID', dict = '_PantsWlMeshCatalog', enum = 'app.CharacterEditDefine.PantsWlMeshID', styleField = {'_WlMeshID', '_WlSubMeshID'} },
        { name = 'Chain', id = 'ChainID', dict = '_PantsWlChainCatalog' },
        { name = 'Clsp', id = 'ClspID', dict = '_PantsWlCollisionShapePresetCatalog' },
        { name = 'Gpuc', id = 'GpucID', dict = '_PantsWlGpuClothCatalog' },
    },
    PantsLgSkin = {
        { name = 'Skin', id = 'SkinID', dict = '_PantsLgSkinCatalog', enum = 'app.CharacterEditDefine.PantsLgSkinID', styleField = {'_LgSkinID', '_LgSubSkinID'} },
    },
    PantsLg = {
        { name = 'Mesh', id = 'MeshID', dict = '_PantsLgMeshCatalog', enum = 'app.CharacterEditDefine.PantsLgMeshID', styleField = {'_LgMeshID', '_LgSubMeshID'} },
        { name = 'Chain', id = 'ChainID', dict = '_PantsLgChainCatalog' },
        { name = 'Clsp', id = 'ClspID', dict = '_PantsLgCollisionShapePresetCatalog' },
        { name = 'Gpuc', id = 'GpucID', dict = '_PantsLgGpuClothCatalog' },
    },
    HelmSkin = {
        { name = 'Skin', id = 'SkinID', dict = '_HelmSkinCatalog', enum = 'app.CharacterEditDefine.HelmSkinID', styleField = {'_SkinID', '_SubSkinID'} },
    },
    Helm = {
        { name = 'Mesh', id = 'MeshID', dict = '_HelmMeshCatalog', enum = 'app.CharacterEditDefine.HelmMeshID', styleField = {'_MeshID', '_SubMeshID'} },
        { name = 'Chain', id = 'ChainID', dict = '_HelmChainCatalog' },
        { name = 'Clsp', id = 'ClspID', dict = '_HelmCollisionShapePresetCatalog' },
        { name = 'Gpuc', id = 'GpucID', dict = '_HelmGpuClothCatalog' },
    },
    MantleSkin = {
        { name = 'Skin', id = 'SkinID', dict = '_MantleSkinCatalog', enum = 'app.CharacterEditDefine.MantleSkinID', styleField = {'_SkinID'} },
    },
    Mantle = {
        { name = 'Mesh', id = 'MeshID', dict = '_MantleMeshCatalog', enum = 'app.CharacterEditDefine.MantleMeshID', styleField = {'_MeshID'} },
        { name = 'Chain', id = 'ChainID', dict = '_MantleChainCatalog' },
        { name = 'Clsp', id = 'ClspID', dict = '_MantleClspCatalog' },
        { name = 'Gpuc', id = 'GpucID', dict = '_MantleGpuClothCatalog' },
    },
    FacewearSkin = {
        { name = 'Skin', id = 'SkinID', dict = '_FacewearSkinCatalog', enum = 'app.CharacterEditDefine.FacewearSkinID' },
    },
    Facewear = {
        { name = 'Mesh', id = 'MeshID', dict = '_FacewearMeshCatalog', enum = 'app.CharacterEditDefine.FacewearMeshID' },
    }
}
local recordTypes = utils.get_sorted_table_keys(armorCatalogs)

for armorMeshType, fieldData in pairs(armorCatalogs) do
    local sourceEnum = enums.get_enum(fieldData[1].enum).valueToLabel
    udb.register_entity_type(armorMeshType, {
        insert_id_range = {1000, 6942069},
        import = function (import_data, instance)
            instance = instance or {}
            for i, entry in ipairs(fieldData) do
                instance[entry.name] = import_handlers.import('app.PrefabController', import_data[entry.name], instance[entry.name])
                if instance[entry.name] then
                    CharacterEditManager[entry.dict][import_data.id] = instance[entry.name]
                end
            end

            return instance
        end,
        export = function (instance)
            local data = {}
            for _, entry in ipairs(fieldData) do
                data[entry.name] = import_handlers.export(instance[entry.name], 'app.PrefabController')
            end

            return data
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
            local dict = CharacterEditManager[fields.dict]
            dict = dict and utils.dictionary_to_table(dict)
            if dict then -- some of the dictionary are default null / empty, don't crash on those
                for _, id in ipairs(utils.get_sorted_table_keys(dict)) do
                    local pfbCtrl = dict[id]
                    if pfbCtrl then
                        local entity = udb.get_entity(armorMeshType, id)
                        if not entity then
                            entity = udb.register_pristine_entity({
                                id = id,
                                type = armorMeshType,
                            })
                        end
                        entity[fields.name] = pfbCtrl
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
        end
    end

    editor.define_window('armor_catalogs', 'Armor catalogs', function (state)
        _, state.part_type, state.part_type_filter = ui.core.combo_filterable('Part type', state.part_type, recordTypes, state.part_type_filter or '')
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
                if imgui.button('Force update meshes') then
                    local player = CharacterManager:get_ManualPlayer()
                    if player then forceUpdateSwapParts(player) end
                    local it = PawnManager._PawnCharacterList:GetEnumerator()
                    while it:MoveNext() do forceUpdateSwapParts(it._current) end
                end
                if imgui.is_item_hovered() then imgui.set_tooltip('Will force all mesh parts of the player and pawns to refresh based on the currently defined meshes') end
                imgui.text('ID: ' .. tostring(selectedItem.id))
                for _, field in ipairs(recordData) do
                    local pfbCtrl = selectedItem[field.name] --- @type app.PrefabController|nil
                    local path = pfbCtrl and pfbCtrl.get_ResourcePath and pfbCtrl:get_ResourcePath()--[[@as string|nil]]
                    local changed, newpath = imgui.input_text(field.name, path or '')
                    if changed then
                        if newpath and newpath ~= '' then
                            if not pfbCtrl then
                                pfbCtrl = import_handlers.import('app.PrefabController', newpath)
                                selectedItem[field.name] = pfbCtrl
                                CharacterEditManager[field.dict][selectedItem.id] = pfbCtrl
                                udb.mark_entity_dirty(selectedItem)
                            elseif newpath ~= path then
                                pfbCtrl._Item:set_Path(newpath)
                                udb.mark_entity_dirty(selectedItem)
                            end
                        else
                            selectedItem[field.name] = nil
                            CharacterEditManager[field.dict][selectedItem.id] = nil
                            udb.mark_entity_dirty(selectedItem)
                        end
                    end
                end
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
                                if entity.variants['1910070090'] and entity.variants['1910070090'][idField] == selectedItem.id
                                or entity.variants['2776536455'] and entity.variants['2776536455'][idField] == selectedItem.id then
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