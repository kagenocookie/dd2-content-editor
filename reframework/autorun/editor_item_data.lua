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
--- @field name string|nil
--- @field description string|nil

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
local get_item_name = sdk.find_type_definition('app.GUIBase'):get_method('getElfItemName(System.Int32, System.Boolean)')
local get_item_desc = sdk.find_type_definition('app.GUIBase'):get_method('getElfItemDetail(System.Int32, System.Boolean)')

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
        return {
            name = instance.name,
            description = instance.description,
            data = import_handlers.export(instance.runtime_instance, 'app.ItemCommonParam')
        }
    end,
    import = function (data, instance)
        --- @cast instance ItemDataEntity
        instance = instance or {}
        instance.runtime_instance = import_handlers.import('app.ItemCommonParam', data.data, instance.runtime_instance)
        instance.name = data.name or instance.name
        instance.description = data.description or instance.description
        if not instance.runtime_instance then
            print('Missing item runtime instance lol')
            log.info('Missing item runtime instance lol')
        end
        -- if instance.runtime_instance and not ItemManager._ItemDataDict:ContainsKey(data.id) then
        --     ItemManager._ItemDataDict[data.id] = instance.runtime_instance
        -- end
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

-- icon overrides
sdk.hook(
    -- game calls getUVSequenceResourceHolder() and then applyUVSettings() when setting item icons
    sdk.find_type_definition('app.UVSequenceResourceManager'):get_method('applyUVSettings'),
    function (args)
        local iconNo = sdk.to_int64(args[4]) & 0xffffffff
        if iconNo >= 30000 then -- minimum custom item id
            local tex = sdk.to_managed_object(args[3]) --[[@as via.gui.Texture]]
            print('Add a custom icon pls for item id', iconNo)
        end
    end
)

-- name overrides
-- NOTE: potential other avenues of overriding names:
-- sdk.find_type_definition('app.GUIBase'):get_method('getElfItemName') works fine for name
-- sdk.find_type_definition('app.GUIBase'):get_method('getElfItemDetail') works but isn't actually ever getting called (likely inlined)
-- sdk.find_type_definition('app.GUIBase'):get_method('getElfMsg') would work fine for both name and detail but receives a full string so we'd need to parse that which isn't nice
-- anything else mostly just ends up calling these methods anyway, so then the simplest solution is to hook to setups of relevant gui elements
-- need to see if it works fine for item pickups as well

sdk.hook(
    sdk.find_type_definition('app.GUIBase'):get_method('getElfItemName'),
    function (args)
        local itemId = sdk.to_int64(args[2]) & 0xffffffff
        if itemId >= 30000 then -- minimum custom item id
            local item = udb.get_entity('item_data', itemId) --[[@as ItemDataEntity]]
            if item and item.name then
                -- TODO cache the managed string pointer somewhere instead of making new ones each time?
                thread.get_hook_storage().name = sdk.to_ptr(sdk.create_managed_string(item.name))
            end
        end
    end,
    function (ret)
        return thread.get_hook_storage().name or ret
    end
)

sdk.hook(
    sdk.find_type_definition('app.GUIBase.ItemWindowRef'):get_method('setup(app.ItemCommonParam, System.Int32, System.Boolean)'),
    function (args)
        local data = sdk.to_managed_object(args[3]) --[[@as app.ItemCommonParam]]
        local id = data and data._Id
        if id and id >= 30000 then -- minimum custom item id
            local item = udb.get_entity('item_data', id) --[[@as ItemDataEntity]]
            if item and item.name then
                local s = thread.get_hook_storage()
                s.this = sdk.to_managed_object(args[2])
                -- s.name = item.name
                s.description = item.description

            end
        end
    end,
    function (ret)
        local s = thread.get_hook_storage()
        if s.this then
            local this = s.this --[[@as app.GUIBase.ItemWindowRef]]
            this._TxtInfo:set_Message(s.description)
            -- this._TxtName:set_Message(s.name)
        end
        return ret
    end
)


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
        if not item.name then item.name = get_item_name:call(nil, item.id, false) end
        if not item.description then item.description = get_item_desc:call(nil, item.id, false) end
        local changed

        changed, item.name = imgui.input_text('Name', item.name or '')
        if changed then udb.mark_entity_dirty(item) end

        changed, item.description = imgui.input_text_multiline('Description', item.description or '', 5)
        if changed then udb.mark_entity_dirty(item) end
        imgui.spacing()

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
