local core = require('content_editor.core')
local udb = require('content_editor.database')
local enums = require('content_editor.enums')
local import_handlers = require('content_editor.import_handlers')
local definitions = require('content_editor.definitions')
local helpers = require('content_editor.helpers')
local generic_types = require('content_editor.generic_types')

local ItemManager = sdk.get_managed_singleton('app.ItemManager') --- @type app.ItemManager
local EquipmentManager = sdk.get_managed_singleton('app.EquipmentManager') --- @type app.EquipmentManager

local weaponIds = enums.get_enum('app.WeaponID')
local OriginalWeaponIDs = weaponIds.valueToLabel

local get_item_name = sdk.find_type_definition('app.GUIBase'):get_method('getElfItemName(System.Int32, System.Boolean)')
local weapon_to_item_id = sdk.find_type_definition('app.ItemManager'):get_method('getItemData(app.WeaponID)')

local hasRefcounterType = false

--- @class WeaponEntity : DBEntity
--- @field prefab app.RefCounter<app.PrefabController>
--- @field offsets app.WeaponSetting.OffsetSetting|nil
--- @field _kind nil|integer

-- TODO: some sort of override for the weapon ID -> category/group conversion?

local function register_entity(id, prefabContainer, offsets, label)
    --- @type WeaponEntity
    local entity = {
        id = id,
        type = 'weapon',
        offsets = offsets,
        prefab = prefabContainer,
        label = label,
    }
    udb.create_entity(entity, nil, true)
    udb.mark_entity_dirty(entity, false)
    return entity
end

udb.events.on('get_existing_data', function (whitelist)
    if whitelist and not whitelist.weapon then return end
    -- TODO weapon additional data
    -- ItemManager._WeaponAdditionalDataDict (readonly dict)
    -- ItemManager.WeaponSpecialEfficacyParam
    -- app.ItemManagerBehavior - contains the source data that gets cataloged into the singleton at some point
    -- so the solution for adding new entries might be to modify the behavior and call ItemManager:setupWeapomAdditionalData() again

    local enumerator = EquipmentManager.WeaponCatalog:GetEnumerator()
    while enumerator:MoveNext() do
        local id = enumerator._current.key
        if not hasRefcounterType then
            generic_types.add('app.RefCounter`1<app.PrefabController>', enumerator._current.value:GetType())
            hasRefcounterType = true
        end
        if not whitelist or whitelist.weapon[id] then
            local refPfb = enumerator._current.value
            local offsetSettings = EquipmentManager.WeaponSetting:getOffsetSettings(id)
            if offsetSettings and offsetSettings.ID == id then
                register_entity(id, refPfb, offsetSettings)
            else
                register_entity(id, refPfb)
            end
        end
    end

    for id, label in pairs(OriginalWeaponIDs) do
        if id ~= 0 and (not whitelist or whitelist.weapon[id]) and not udb.get_entity('weapon', id) then
            local offsets = EquipmentManager.WeaponSetting:getOffsetSettings(id)
            if offsets and offsets.ID == id then
                local dispLabel = weaponIds.get_label(id)
                if dispLabel == label then
                    register_entity(id, nil, offsets, '[group] ' .. label)
                else
                    register_entity(id, nil, offsets, '[group] ' .. label .. ' ' .. weaponIds.get_label(id))
                end
            elseif core.editor_enabled then
                local dispLabel = weaponIds.get_label(id)
                if dispLabel == label then
                    weaponIds.set_display_label(id, '[group] ' .. dispLabel, false)
                else
                    weaponIds.set_display_label(id, '[group] ' .. label .. ' ' .. dispLabel, false)
                end
            end
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
            local effectiveSettings = offSettings:getOffsetSettings(data.id)
            if effectiveSettings == nil or effectiveSettings.ID ~= data.id then
                offSettings.OffsetSettings = helpers.expand_system_array(offSettings.OffsetSettings, { instance.offsets }, nil, true)
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
        if not udb.is_custom_entity_id('weapon', instance.id) then return 'forget' end

        if instance.offsets then
            EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings = helpers.system_array_remove(
                EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings, instance.offsets, 'app.WeaponSetting.OffsetSetting'
            )
        end
        EquipmentManager.WeaponCatalog:Remove(instance.id)
        return 'ok'
    end,
    insert_id_range = {1000, 100000},
    replaced_enum = 'app.WeaponID',
    root_types = {},
})

definitions.override('weapons', {
    ['app.RefCounter`1<app.PrefabController>'] = {
        import_field_whitelist = {'_Item'}
    }
})

local weaponKinds = {
    sword = weaponIds.labelToValue.wp00,
    shield = weaponIds.labelToValue.wp01,
    greatsword = weaponIds.labelToValue.wp02,
    dagger = weaponIds.labelToValue.wp03,
    bow = weaponIds.labelToValue.wp04,
    magick_bow = weaponIds.labelToValue.wp05,
    staff = weaponIds.labelToValue.wp07,
    archistaff = weaponIds.labelToValue.wp08,
    duospear = weaponIds.labelToValue.wp09,
    censer = weaponIds.labelToValue.wp10,
}

--- @param weapon WeaponEntity
--- @return integer
local function figure_out_weapon_kind(weapon)
    --- @type ItemDataEntity|nil
    local wpItem = select(2, next(udb.get_entities_where('item_data', function (entity)
        --- @cast entity ItemDataEntity
        local wpId = entity.runtime_instance and entity.runtime_instance._WeaponId
        return wpId and wpId == weapon.id
    end)))
    if wpItem and wpItem.runtime_instance:get_DataType() == 2 then
        if wpItem.runtime_instance._EquipCategory == 1 then
            return weaponKinds.shield
        end
        local jobId = wpItem.runtime_instance._Job
        if (jobId & 2) ~= 0 then return weaponKinds.sword end
        if (jobId & 4) ~= 0 then return weaponKinds.bow end
        if (jobId & 8) ~= 0 then return weaponKinds.staff end
        if (jobId & 16) ~= 0 then return weaponKinds.dagger end
        if (jobId & 32) ~= 0 then return weaponKinds.greatsword end
        if (jobId & 64) ~= 0 then return weaponKinds.archistaff end
        if (jobId & 128) ~= 0 then return weaponKinds.duospear end
        if (jobId & 256) ~= 0 then return weaponKinds.magick_bow end
        if (jobId & 512) ~= 0 then return weaponKinds.censer end
    end
    return 0
end

local ptr_true = sdk.to_ptr(true)
local ptr_false = sdk.to_ptr(false)
sdk.hook(
    sdk.find_type_definition('app.WeaponIDUtil'):get_method('isKindOf'),
    function (args)
        local weaponId = sdk.to_int64(args[2]) & 0xffffffff
        if udb.is_custom_entity_id('weapon', weaponId) then
            local weapon = udb.get_entity('weapon', weaponId)--[[@as WeaponEntity|nil]]
            if weapon then
                if not weapon._kind then
                    weapon._kind = figure_out_weapon_kind(weapon)
                end
                local compId = sdk.to_int64(args[3]) & 0xffffffff
                thread.get_hook_storage().ret = compId == weapon._kind and ptr_true or ptr_false
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end
    end,
    function (r) return thread.get_hook_storage().ret or r end
)

if core.editor_enabled then
    local editor = require('content_editor.editor')
    local ui = require('content_editor.ui')

    definitions.override('', {
        ['app.WeaponSetting.OffsetSetting'] = {
            fields = {
                ID = { uiHandler = function (value)
                    imgui.text('Offset for ID: ' .. value.get() .. '  | '.. helpers.to_string(value.get(), 'app.WeaponID'))
                    return false
                end }
            },
        }
    })

    ui.editor.set_entity_editor('weapon', function (selectedItem, state)
        --- @cast selectedItem WeaponEntity
        local path = selectedItem.prefab and (selectedItem.prefab._Item--[[@as app.PrefabController]]):get_ResourcePath()
        if udb.is_custom_entity_id('weapon', selectedItem.id) then
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
                EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings = helpers.expand_system_array(EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings, { selectedItem.offsets }, nil, true)
                changed = true
            end
            if effectiveOffsets then
                ui.basic.tooltip('This is the evaluated offset settings for this weapon.\nIf you wish to change settings for the current weapon, use the Add offset override button.', nil, true)
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
            imgui.spacing()
            imgui.text('Browse defined offsets')
            imgui.text_colored('These are intended as a reference to see how other / basegame weapons are configured.\nChanges done directly to these settings will not be saved.', core.get_color('disabled'))
            _, state.view_offset_id, state.view_offset_filter = ui.basic.filterable_enum_value_picker('Existing offsets search', state.view_offset_id, enums.get_enum('app.WeaponID'), state.view_offset_filter)
            ui.basic.tooltip('This will find which offsets are matched for the selected weapon ID / group.')
            if state.view_offset_id then
                local off = EquipmentManager:getWeaponOffsetSetting(state.view_offset_id)
                if off then
                    if off.ID ~= selectedItem.id and imgui.button('Clone as override for current weapon') then
                        selectedItem.offsets = helpers.clone(off, 'app.WeaponSetting.OffsetSetting')
                        selectedItem.offsets.ID = selectedItem.id
                        EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings = helpers.expand_system_array(EquipmentManager.WeaponSetting.DefaultSetting.OffsetSettings, { selectedItem.offsets })
                    end
                    ui.handlers.show_readonly(off, nil, 'Matching offsets', 'app.WeaponSetting.OffsetSetting', state)
                else
                    imgui.text_colored('No offsets defined for the selected weapon ID / group', core.get_color('warning'))
                end
            else
                imgui.text_colored('Choose a weapon ID / group to find offsets for', core.get_color('disabled'))
            end
        end
    end)
end
