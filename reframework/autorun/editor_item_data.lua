local udb = require('content_editor.database')
local import_handlers = require('content_editor.import_handlers')

local core = require('content_editor.core')
local enums = require('content_editor.enums')

local definitions = require('content_editor.definitions')

local ItemManager = sdk.get_managed_singleton('app.ItemManager') --- @type app.ItemManager

local helpers = require('content_editor.helpers')
local scripts = require('content_editor.editors.custom_scripts')


--- @class ItemDataEntity : DBEntity
--- @field runtime_instance app.ItemDataParam|app.ItemArmorParam|app.ItemWeaponParam

local ItemDataType = enums.get_enum('app.ItemDataType')
local ItemAttrBits = enums.get_enum('app.ItemAttrBits')
local ItemUseAttrBits = enums.get_enum('app.ItemUseAttrBits')

local function register_entity(id, type, runtime_instance)
    --- @type ItemDataEntity
    local entity = {
        id = id,
        type = type,
        runtime_instance = runtime_instance,
    }
    udb.create_entity(entity, nil, true)
    udb.mark_entity_dirty(entity, false)
    return entity
end

local type_weaponparam = sdk.find_type_definition('app.ItemWeaponParam')

udb.events.on('get_existing_data', function ()
    local enumerator = ItemManager._ItemDataDict:GetEnumerator()
    local weaponIdLabels = {}
    local weaponIdEnum = enums.get_enum('app.WeaponID')
    local itemsEnum = enums.get_enum('app.ItemID')
    while enumerator:MoveNext() do
        local item = enumerator._current
        if item.value._Id then
            register_entity(item.value._Id, 'item_data', item.value)
            if item.value:get_type_definition():is_a(type_weaponparam) then
                local weaponId = item.value._WeaponId
                local weaponLabel = weaponIdEnum.valueToLabel[weaponId]
                if weaponLabel then
                    weaponIdLabels[#weaponIdLabels+1] = {weaponId, weaponLabel .. ' - ' .. itemsEnum.get_label(item.value._Id)}
                else
                    weaponIdLabels[#weaponIdLabels+1] = {weaponId, 'Weapon - ' .. itemsEnum.get_label(item.value._Id)}
                end
            end
        else
            print('Missing id', item, item.value, item:get_type_definition():get_full_name())
        end
    end

    weaponIdEnum.set_display_labels(weaponIdLabels)
end)

udb.register_entity_type('item_data', {
    export = function (instance)
        --- @cast instance ItemDataEntity
        return { data = import_handlers.export(instance.runtime_instance, 'app.ItemCommonParam') }
    end,
    import = function (data, instance)
        --- @cast instance ItemDataEntity
        instance = instance or {}
        instance.runtime_instance = import_handlers.import('app.ItemCommonParam', data.data, instance.runtime_instance)
        if not ItemManager._ItemDataDict:ContainsKey(data.id) then
            ItemManager._ItemDataDict[data.id] = instance.runtime_instance
        end
        -- local dataType = instance.runtime_instance:get_DataType()
        -- if dataType == 2 or dataType == 3 then
            -- _EquipDataDict contains conversion between item id and style string (why strings, capcom? don't you have enums everywhere??)
            -- I'm actually not sure whether this is even needed and how we're gonna tell the game to fetch it by string
            -- ItemManager._EquipDataDict[tostring(data.id)] = data.id
        -- end
        return instance
    end,
    generate_label = function (entity)
        return 'Item ' .. entity.id .. ' : ' .. enums.get_enum('app.ItemIDEnum').get_label(entity.id)
    end,
    insert_id_range = {30000, 65000},
    -- basegame item IDs go up to 10512
    -- there seems to be a ushort conversion somewhere in the game, so assuming max id 65536 for now
    -- specifically app.ItemManager:isUseEnable(int), called from some native code, ID 140000 was sent as 8928
    replaced_enum = 'app.ItemIDEnum',
    root_types = {'app.ItemCommonParam'},
})

definitions.override('items', {
    ['app.ItemDataParam'] = {
        fieldOrder = {'<DataType>k__BackingField', '_Category', '_SubCategory', '_UseEffect'},
        fields = {
            _UseEffect = {
                extensions = { { type = 'space_after', count = 4 } }
            },
            ['<DataType>k__BackingField'] = {
                extensions = { { type = 'item_data_type_enum' } }
            },
        },
        extensions = { { type = 'item_instance_type_fixer' } },
    },
    ['app.ItemWeaponParam'] = {
        fieldOrder = {'<DataType>k__BackingField', '_Category', '_EquipCategory', '_WeaponId', '_Element', '_WeaponName'},
        fields = {
            _WeaponName = {
                extensions = { { type = 'space_after', count = 4 } }
            },
            ['<DataType>k__BackingField'] = {
                extensions = { { type = 'item_data_type_enum' } }
            },
            _Category = { ui_ignore = true },
        },
        extensions = { { type = 'item_instance_type_fixer' } },
    },
    ['app.ItemArmorParam'] = {
        fieldOrder = {'<DataType>k__BackingField', '_Category', '_EquipCategory', '_Special', '_StyleNo'},
        fields = {
            _StyleNo = {
                extensions = { { type = 'space_after', count = 4 } }
            },
            ['<DataType>k__BackingField'] = {
                extensions = { { type = 'item_data_type_enum' } }
            },
            _Category = { ui_ignore = true },
        },
        extensions = { { type = 'item_instance_type_fixer' } },
    },
})

scripts.define_script_hook(
    'app.ItemManager',
    'useItemSub',
    function (args)
        local itemData = sdk.to_managed_object(args[5]) --[[@as app.ItemDataParam]]
        if itemData._UseEffect < 10000 then return nil end
        return itemData._UseEffect, { from = sdk.to_managed_object(args[3]), to = sdk.to_managed_object(args[4]) }
    end
)

if core.editor_enabled then
    local editor = require('content_editor.editor')
    local ui = require('content_editor.ui')

    scripts.define_script_hook_editor_override(
        'app.ItemDataParam',
        function (target)
            return target._UseEffect and target._UseEffect >= 100000 and target._UseEffect or nil
        end,
        function (target, isHook)
            target._UseEffect = isHook and 100000 or 0
        end,
        function (target, id)
            target._UseEffect = id
        end,
        'Write the lua code that should be executed when this item is used.\nscript_args.from: contains the app.Character that used the item\nscript_args.to: contains the app.Character the item was used on.',
        true -- show_default_editor
    )

    definitions.override('', {
        ['app.ItemDataParam'] = {
            fields = {
                _Attr = {
                    label = 'Attributes',
                    uiHandler = ui.handlers.common.enum_flags(ItemAttrBits, 6)
                },
                _UseAttr = {
                    label = 'Use attributes',
                    uiHandler = ui.handlers.common.enum_flags(ItemUseAttrBits, 6)
                },
            },
        },
        ['app.ItemWeaponParam'] = {
            fields = {
                _Attr = {
                    label = 'Attributes',
                    uiHandler = ui.handlers.common.enum_flags(ItemAttrBits, 6)
                },
                _UseAttr = { ui_ignore = true },
            },
        },
        ['app.ItemArmorParam'] = {
            fields = {
                _Attr = {
                    label = 'Attributes',
                    uiHandler = ui.handlers.common.enum_flags(ItemAttrBits, 6)
                },
                _UseAttr = { ui_ignore = true },
            },
        },
    })

    object_explorer:handle_address()
    ui.handlers.register_extension('item_instance_type_fixer', function (handler)
        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            if changed then
                local obj = ctx.get() --- @type app.ItemDataParam|app.ItemWeaponParam|app.ItemArmorParam

                local dataType = obj:get_DataType()
                local class = obj:get_type_definition():get_full_name()
                local expectedParentType = ({
                    [ItemDataType.labelToValue.Item] = 'app.ItemDataParam',
                    [ItemDataType.labelToValue.Weapon] = 'app.ItemWeaponParam',
                    [ItemDataType.labelToValue.Armor] = 'app.ItemArmorParam',
                })[dataType]
                if expectedParentType and class ~= expectedParentType then
                    print('Fixing item data type ', class, '=>', expectedParentType)
                    -- would we rather ensure we also remove any added items, or just let the user deal with restarting the game?
                    if ItemManager._ItemDataDict:ContainsKey(obj._Id) then
                        editor.set_need_game_restart()
                    end
                    obj = helpers.change_type(obj, expectedParentType) --[[@as app.ItemDataParam|app.ItemWeaponParam|app.ItemArmorParam]]
                    ctx.set(obj)
                    obj._Category = dataType == ItemDataType.labelToValue.Item and 2 or 3 -- other or equip
                end
            end
            return changed
        end
    end)

    ui.handlers.register_extension('item_data_type_enum', function (handler, data)
        --- @type UIHandler
        return function (ctx)
            local changed = handler(ctx)
            if changed then
                local val = ctx.get() --- @type app.ItemDataType
                 -- none is unused, reset it to item
                if val == 0 then
                    ctx.set(1)
                end
            end
            return changed
        end
    end)

    --- @param item ItemDataEntity
    local function show_item_editor(item)
        ui.handlers.show_editable(item, 'runtime_instance', item)
    end

    editor.define_window('item_data', 'Items', function (state)
        if editor.active_bundle then
            local create, preset = ui.editor.create_button_with_preset(state, 'item_data')
            if create then
                local newEntity = udb.insert_new_entity('item_data', editor.active_bundle, preset or {})
                ui.editor.set_selected_entity_picker_entity(state, 'item_data', newEntity)
                --- @cast newEntity ItemDataEntity
                newEntity.runtime_instance._Id = newEntity.id
            end
        end

        local selectedItem = ui.editor.entity_picker('item_data', state)
        if selectedItem then
            --- @cast selectedItem ItemDataEntity
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            ui.editor.show_entity_metadata(selectedItem)
            show_item_editor(selectedItem)
            imgui.end_rect(4)
            imgui.unindent(8)
            imgui.spacing()
        end
    end)

    editor.add_editor_tab('item_data')
end

--- notes
-- inventory items are stored within app.ItemManager.StorageMasterData
-- _StorageID doesn't matter, autogenerated
-- item name is fetched from app.GUIBase:getItemName(ID)
--  this method then does int.tostring(), some lookups somewhere, and finally gets the real message from via.gui.MessageAccessData:get_Message()

-- TODO
-- figure out how IconNo numbers are mapped
