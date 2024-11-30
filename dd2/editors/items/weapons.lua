local udb = require('content_editor.database')
local import_handlers = require('content_editor.import_handlers')

local core = require('content_editor.core')
local enums = require('content_editor.enums')

local definitions = require('content_editor.definitions')

local helpers = require('content_editor.helpers')

local ItemManager = sdk.get_managed_singleton('app.ItemManager') --- @type app.ItemManager
local EquipmentManager = sdk.get_managed_singleton('app.EquipmentManager') --- @type app.EquipmentManager

local weaponEnum = enums.get_enum('app.WeaponID')
local OriginalWeaponIDs = weaponEnum.valueToLabel

local get_item_name = sdk.find_type_definition('app.GUIBase'):get_method('getElfItemName(System.Int32, System.Boolean)')
local weapon_to_item_id = sdk.find_type_definition('app.ItemManager'):get_method('getItemData(app.WeaponID)')

--- @class WeaponEntity : DBEntity
--- @field prefab app.RefCounter<app.PrefabController>
--- @field offsets app.WeaponSetting.OffsetSetting|nil

-- TODO: some sort of override for the weapon ID -> category/group conversion?

local max_custom_weapon_id = 100000

local function register_entity(id, prefabContainer, offsets)
    --- @type WeaponEntity
    local entity = {
        id = id,
        type = 'weapon',
        offsets = offsets,
        prefab = prefabContainer,
    }
    udb.create_entity(entity, nil, true)
    udb.mark_entity_dirty(entity, false)
    return entity
end

udb.events.on('get_existing_data', function ()
    -- TODO weapon additional data
    -- ItemManager._WeaponAdditionalDataDict (readonly dict)
    -- ItemManager.WeaponSpecialEfficacyParam
    -- app.ItemManagerBehavior - contains the source data that gets cataloged into the singleton at some point
    -- so the solution for adding new entries might be to modify the behavior and call ItemManager:setupWeapomAdditionalData() again

    local enumerator = EquipmentManager.WeaponCatalog:GetEnumerator()
    while enumerator:MoveNext() do
        local id = enumerator._current.key
        local refPfb = enumerator._current.value
        local offsetSettings = EquipmentManager.WeaponSetting:getOffsetSettings(id)
        if offsetSettings and offsetSettings.ID == id then
            register_entity(id, refPfb, offsetSettings)
        else
            register_entity(id, refPfb)
        end
    end

    for id, label in pairs(OriginalWeaponIDs) do
        if not udb.get_entity('weapon', id) then
            weaponEnum.set_display_label(id, '[group] ' .. label)
        end
    end
end)

udb.register_entity_type('weapon', {
    export = function (instance)
        --- @cast instance WeaponEntity
        return {
            prefab = import_handlers.export(instance.prefab, 'app.RefCounter`1<app.PrefabController>'),
            offsets = import_handlers.export(instance.offsets, 'app.WeaponSetting.OffsetSetting'),
        }
    end,
    import = function (data, instance)
        --- @cast instance WeaponEntity
        instance.prefab = import_handlers.import('app.RefCounter`1<app.PrefabController>', data.prefab, instance.prefab)
        instance.offsets = import_handlers.import('app.WeaponSetting.OffsetSetting', data.offsets, instance.offsets)
        if instance.prefab and instance.prefab:get_RefCount() < 1 then instance.prefab:addRef() end
        if instance.prefab and not EquipmentManager.WeaponCatalog:ContainsKey(data.id) then
            EquipmentManager.WeaponCatalog[data.id] = instance.prefab
        end
        if instance.offsets then
            instance.offsets.ID = data.id
            local offSettings = EquipmentManager.WeaponSetting.DefaultSetting
            if offSettings:getOffsetSettings(data.id) == nil then
                instance.offsets.ID = data.id
                offSettings.OffsetSettings = helpers.expand_system_array(offSettings.OffsetSettings, { instance.offsets })
            end
        end
    end,
    generate_label = function (entity)
        if OriginalWeaponIDs[entity.id] then
            local itemData = weapon_to_item_id:call(ItemManager, entity.id) --[[@as app.ItemWeaponParam]]
            if itemData and itemData._Id then
                return OriginalWeaponIDs[entity.id] .. ' - ' .. tostring(get_item_name:call(nil, itemData and itemData._Id, false))
            else
                return OriginalWeaponIDs[entity.id]
            end
        else
            return 'Weapon ' .. entity.id
        end
    end,
    delete = function (instance)
        --- @cast instance WeaponEntity
        if instance.id > max_custom_weapon_id then return 'forget' end

        if instance.offsets then
            EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings = helpers.system_array_remove(
                EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings, instance.offsets, 'app.WeaponSetting.OffsetSetting'
            )
        end
        EquipmentManager.WeaponCatalog:Remove(instance.id)
        return 'ok'
    end,
    insert_id_range = {1000, 100000},
    -- basegame item IDs go up to 10512
    -- there seems to be a ushort conversion somewhere in the game, so assuming max id 65536 for now
    -- specifically app.ItemManager:isUseEnable(int), called from some native code, ID 140000 was sent as 8928
    replaced_enum = 'app.WeaponID',
    root_types = {},
})

definitions.override('weapons', {
    ['app.RefCounter`1<app.PrefabController>'] = {
        import_field_whitelist = {'_Item'}
    }
})

if core.editor_enabled then
    local editor = require('content_editor.editor')
    local ui = require('content_editor.ui')

    ui.editor.set_entity_editor('weapon', function (selectedItem, state)
        --- @cast selectedItem WeaponEntity
        local path = selectedItem.prefab and (selectedItem.prefab._Item--[[@as app.PrefabController]]):get_ResourcePath()
        if selectedItem.id < max_custom_weapon_id then
            imgui.text_colored('For custom weapons, make sure the app.Weapon->WeaponID inside the .pfb matches the ID of the entity\nOtherwise the game can crash on unpause. Disabling the bundle with the custom weapon and reloading should fix it.', core.get_color('danger'))
        end
        local changed, newpath = imgui.input_text('Prefab', path or '')
        if changed then
            if newpath and newpath ~= '' then
                if not pfbCtrl then
                    pfbCtrl = import_handlers.import('app.RefCounter`1<app.PrefabController>', { _Item = newpath })
                    if pfbCtrl and pfbCtrl:get_RefCount() < 1 then pfbCtrl:addRef() end

                    selectedItem.prefab = pfbCtrl
                    EquipmentManager.WeaponCatalog[selectedItem.id] = pfbCtrl
                    udb.mark_entity_dirty(selectedItem)
                elseif newpath ~= path then
                    pfbCtrl._Item._Item:set_Path(newpath)
                    udb.mark_entity_dirty(selectedItem)
                end
            else
                selectedItem.prefab = nil
                EquipmentManager.WeaponCatalog:Remove(selectedItem.id)
                udb.mark_entity_dirty(selectedItem)
            end
        end

        if selectedItem.offsets then
            imgui.text('Changes to offsets may not apply immediately.\nIn case of issues, try unequipping the weapon and unpausing before re-equipping it. Maybe equip something else first as well.')
            if imgui.button('Remove offset override') then
                EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings = helpers.system_array_remove(EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings, selectedItem.offsets, 'app.WeaponSetting.OffsetSetting')
                selectedItem.offsets = nil
            end
            changed = ui.handlers.show(selectedItem.offsets, selectedItem, 'Offset override', 'app.WeaponSetting.OffsetSetting') or changed
        else
            local effectiveOffsets = EquipmentManager.WeaponSetting:getOffsetSettings(selectedItem.id)
            if imgui.button('Add offset override') then
                if selectedItem.offsets then
                    EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings = helpers.system_array_remove(EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings, selectedItem.offsets, 'app.WeaponSetting.OffsetSetting')
                    selectedItem.offsets = nil
                end
                if effectiveOffsets then
                    selectedItem.offsets = helpers.clone(effectiveOffsets, 'app.WeaponSetting.OffsetSetting')
                    selectedItem.offsets.ID = selectedItem.id
                else
                    selectedItem.offsets = import_handlers.import('app.WeaponSetting.OffsetSetting', { ID = selectedItem.id })
                end
                EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings = helpers.expand_system_array(EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings, { selectedItem.offsets })
                changed = true
            end
            if effectiveOffsets then
                ui.handlers.show_readonly(effectiveOffsets, nil, 'Effective offsets', 'app.WeaponSetting.OffsetSetting', state)
            else
                imgui.text_colored('No weapon offsets available for this weapon', core.get_color('danger'))
            end
        end
        return changed
    end)

    editor.define_window('weapons', 'Weapons', function (state)
        if editor.active_bundle then
            if imgui.button('Create new') then
                local newEntity = udb.insert_new_entity('weapon', editor.active_bundle, {})
                ui.editor.set_selected_entity_picker_entity(state, 'weapon', newEntity)
            end
        end

        local selectedItem = ui.editor.entity_picker('weapon', state)
        if selectedItem then
            --- @cast selectedItem WeaponEntity
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            ui.editor.show_entity_editor(selectedItem, state)
            imgui.end_rect(4)
            imgui.unindent(8)
            imgui.spacing()

            imgui.spacing()
            imgui.spacing()
            imgui.text('All offsets')
            _, state.view_offset_id, state.view_offset_filter = ui.basic.filterable_enum_value_picker('View offsets', state.view_offset_id, enums.get_enum('app.WeaponID'), state.view_offset_filter)
            if state.view_offset_id then
                local off = EquipmentManager:getWeaponOffsetSetting(state.view_offset_id)
                if off then
                    if off.ID ~= selectedItem.id and imgui.button('Clone as override for current weapon') then
                        selectedItem.offsets = helpers.clone(off, 'app.WeaponSetting.OffsetSetting')
                        selectedItem.offsets.ID = selectedItem.id
                        EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings = helpers.expand_system_array(EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings, { selectedItem.offsets })
                    end
                    ui.handlers.show_readonly(off, nil, 'Offsets', 'app.WeaponSetting.OffsetSetting', state)
                end
            end
        end
    end)
end
