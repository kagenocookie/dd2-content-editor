local udb = require('content_editor.database')
local import_handlers = require('content_editor.import_handlers')

local core = require('content_editor.core')
local enums = require('content_editor.enums')

local definitions = require('content_editor.definitions')

local ItemManager = sdk.get_managed_singleton('app.ItemManager') --- @type app.ItemManager

local helpers = require('content_editor.helpers')
local scripts = require('content_editor.editors.custom_scripts')
local utils = require('content_editor.utils')
local prefabs = require('content_editor.prefabs')

--- @class ItemDataEntity : DBEntity
--- @field runtime_instance app.ItemDataParam|app.ItemArmorParam|app.ItemWeaponParam
--- @field name string|nil
--- @field description string|nil
--- @field icon_path string|nil
--- @field icon_rect ItemUVSettings|nil
--- @field _texture via.render.TextureResourceHolder|nil
--- @field _textureContainer via.GameObject|nil

--- @class ItemUVSettings
--- @field x integer
--- @field y integer
--- @field w integer width
--- @field h integer height

local ItemDataType = enums.get_enum('app.ItemDataType')
local ItemAttrBits = enums.get_enum('app.ItemAttrBits')
local ItemUseAttrBits = enums.get_enum('app.ItemUseAttrBits')

local custom_item_id_min = 30000

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

local get_item_name = sdk.find_type_definition('app.GUIBase'):get_method('getElfItemName(System.Int32, System.Boolean)')
local get_item_desc = sdk.find_type_definition('app.GUIBase'):get_method('getElfItemDetail(System.Int32, System.Boolean)')

udb.events.on('get_existing_data', function ()
    local enumerator = ItemManager._ItemDataDict:GetEnumerator()
    while enumerator:MoveNext() do
        local item = enumerator._current
        if item.value._Id then
            register_entity(item.value._Id, 'item_data', item.value)
        else
            print('Missing id', item, item.value, item:get_type_definition():get_full_name())
        end
    end
end)

udb.register_entity_type('item_data', {
    export = function (instance)
        --- @cast instance ItemDataEntity
        return {
            name = instance.name,
            description = instance.description,
            icon_path = instance.icon_path,
            icon_rect = instance.icon_rect,
            data = import_handlers.export(instance.runtime_instance, 'app.ItemCommonParam')
        }
    end,
    import = function (data, instance)
        --- @cast instance ItemDataEntity
        instance = instance or {}
        if data.data and data.data._IconNo == 0 then
            data.data._IconNo = data.id
        end
        instance.runtime_instance = import_handlers.import('app.ItemCommonParam', data.data, instance.runtime_instance)
        instance.name = data.name or instance.name
        instance.description = data.description or instance.description
        instance.icon_path = data.icon_path
        instance.icon_rect = data.icon_rect
        if not instance.runtime_instance then
            print('Missing item runtime instance lol')
            log.info('Missing item runtime instance lol')
        end
        if instance.runtime_instance and not ItemManager._ItemDataDict:ContainsKey(data.id) then
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
    delete = function (instance)
        --- @cast instance ItemDataEntity
        if instance.id < custom_item_id_min then
            return 'not_deletable'
        end

        if instance.runtime_instance then
            ItemManager._ItemDataDict:Remove(instance.id)
        end
        return 'forget'
    end,
    insert_id_range = {custom_item_id_min, 65000},
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
        fieldOrder = {'<DataType>k__BackingField', '_Category', '_EquipCategory', '_StyleNo', '_Special'},
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

--#region Icon overrides

--- @param tex via.gui.Texture
--- @param item ItemDataEntity
local function apply_icon_rect(tex, item)
    tex:setTexture(item._texture)
    if item.icon_rect then
        tex:set_RectL(item.icon_rect.x)
        tex:set_RectT(item.icon_rect.y)
        tex:set_RectW(item.icon_rect.w)
        tex:set_RectH(item.icon_rect.h)
    else
        tex:set_RectL(0)
        tex:set_RectT(0)
        tex:set_RectW(160)
        tex:set_RectH(156)
    end
end

sdk.hook(
    -- I think this is the earliest common method where the game fetches item icons
    -- the game then calls getUVSequenceResourceHolder() and then applyUVSettings() when setting item icons, but we can override it right here already
    sdk.find_type_definition('app.GUIBase'):get_method('setItemIconUV'),
    function (args)
        local iconNo = sdk.to_int64(args[3]) & 0xffffffff
        if iconNo >= custom_item_id_min then
            local item = udb.get_entity('item_data', iconNo) --[[@as ItemDataEntity|nil]]
            if not item then return end
            if not item._texture and (not item.icon_path or item.icon_path == '') then
                -- no icon :(
                return
            end

            local tex = sdk.to_managed_object(args[2]) --[[@as via.gui.Texture]]
            if not item._texture then
                if not item.icon_path or item.icon_path == '' then return end
                local immediateInst = prefabs.instantiate_shared(item.icon_path, function (gameObj)
                    if not item._texture then
                        local texHolder = utils.get_gameobject_component(gameObj, 'app.GUITextureHolder') --[[@as app.GUITextureHolder|nil]]
                        item._texture = texHolder and (texHolder._Texture or texHolder._UVSequense)
                    end

                    if tex and sdk.is_managed_object(tex) and item._texture then
                        apply_icon_rect(tex, item)
                    end
                end)
                -- apply a default transparent texture instead of having it flash white.png until the prefab loads
                -- (iconNo = 8099 is empty for basegame icons, may need to change if devs add more content)
                if not immediateInst then
                    tex:set_UVSequence(ItemManager:get_UVSequenceResourceManager():getUVSequenceResourceHolder(8000, 10000000))
                    tex:set_UVSequenceNo(8)
                    tex:set_UVPatternNo(99)
                end
                return sdk.PreHookResult.SKIP_ORIGINAL
            end

            if item._texture then
                apply_icon_rect(tex, item)
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end
    end
)
--#endregion

--#region Name overrides
-- sdk.find_type_definition('app.GUIBase'):get_method('getItemName') is used for item pickup and drop notifications
-- sdk.find_type_definition('app.GUIBase'):get_method('getElfItemName') is used for name in inventory
-- sdk.find_type_definition('app.GUIBase'):get_method('getElfItemDetail') works for description but isn't actually ever getting called (likely inlined)
-- sdk.find_type_definition('app.GUIBase'):get_method('getElfMsg') seems like it would work fine for both name and detail but receives a string like item_detail_{id} so we'd need to parse that which isn't nice
-- everything mostly ends up calling one of these methods

local function hook_pre_getItemName(args)
    local itemId = sdk.to_int64(args[2]) & 0xffffffff
    if itemId >= custom_item_id_min then
        local item = udb.get_entity('item_data', itemId) --[[@as ItemDataEntity]]
        if item and item.name then
            -- TODO cache the managed string pointer somewhere instead of making new ones each time?
            thread.get_hook_storage().name = sdk.to_ptr(sdk.create_managed_string(item.name))
        end
    end
end
sdk.hook(
    sdk.find_type_definition('app.GUIBase'):get_method('getElfItemName'),
    hook_pre_getItemName,
    function (ret) return thread.get_hook_storage().name or ret end
)

sdk.hook(
    sdk.find_type_definition('app.GUIBase'):get_method('getItemName'),
    hook_pre_getItemName,
    function (ret) return thread.get_hook_storage().name or ret end
)

sdk.hook(
    sdk.find_type_definition('app.GUIBase.ItemWindowRef'):get_method('setup(app.ItemCommonParam, System.Int32, System.Boolean)'),
    function (args)
        local data = sdk.to_managed_object(args[3]) --[[@as app.ItemCommonParam]]
        local id = data and data._Id
        if id and id >= custom_item_id_min then
            local item = udb.get_entity('item_data', id) --[[@as ItemDataEntity]]
            if item and item.name then
                local s = thread.get_hook_storage()
                s.this = sdk.to_managed_object(args[2])
                s.description = item.description
            end
        end
    end,
    function (ret)
        local s = thread.get_hook_storage()
        if s.this then
            local this = s.this --[[@as app.GUIBase.ItemWindowRef]]
            this._TxtInfo:set_Message(s.description)
        end
        return ret
    end
)
--#endregion

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

    local ItemJobFlags = enums.get_virtual_enum('ItemJobFlags', {
        Job01Fighter = 2,
        Job02Archer = 4,
        Job03Mage = 8,
        Job04Thief = 16,
        Job05Warrior = 32,
        Job06Sorcerer = 64,
        Job07MysticSpearhand = 128,
        Job08MagickArcher = 256,
        Job09Trickster = 512,
    })

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
                _IconNo = { extensions = { { type = 'tooltip', text = 'For custom items, icon number should be equal to the item ID' } } },
            },
        },
        ['app.ItemWeaponParam'] = {
            fields = {
                _Attr = {
                    label = 'Attributes',
                    uiHandler = ui.handlers.common.enum_flags(ItemAttrBits, 6)
                },
                _Job = { uiHandler = ui.handlers.common.enum_flags(ItemJobFlags, 5) },
                _IconNo = { extensions = { { type = 'tooltip', text = 'For custom items, icon number should be equal to the item ID' } } },
                _UseAttr = { ui_ignore = true },
            },
        },
        ['app.ItemArmorParam'] = {
            fields = {
                _Attr = {
                    label = 'Attributes',
                    uiHandler = ui.handlers.common.enum_flags(ItemAttrBits, 6)
                },
                _StyleNo = {
                    uiHandler = ui.handlers.common.enum_dynamic(function (context)
                        if context.parent then
                            local armordata = context.parent.get() ---@type app.ItemArmorParam
                            if armordata._EquipCategory == 2 then return enums.get_enum('HelmStyleNo') end
                            if armordata._EquipCategory == 3 then return enums.get_enum('TopsStyleNo') end
                            if armordata._EquipCategory == 4 then return enums.get_enum('PantsStyleNo') end
                            if armordata._EquipCategory == 5 then return enums.get_enum('MantleStyleNo') end
                            return nil
                        else
                            return nil
                        end
                    end)
                },
                _IconNo = { extensions = { { type = 'tooltip', text = 'For custom items, icon number should be equal to the item ID' } } },
                _Job = { uiHandler = ui.handlers.common.enum_flags(ItemJobFlags, 5) },
                _UseAttr = { ui_ignore = true },
                _BlowResistRate = { label = 'BlowResistRate (Knockdown)' }
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

        local function markdirty() udb.mark_entity_dirty(item) end
        ui.core.setting_text('Name', item, 'name', markdirty)
        ui.core.setting_text('Description', item, 'description', markdirty, 4)
        ui.core.setting_text('Icon .pfb filepath', item, 'icon_path', markdirty)
        if not item.icon_rect then
            local enable_rect = imgui.checkbox('Use custom icon UV rect', false)
            if enable_rect then
                item.icon_rect = { x = 0, y = 0, w = 160, h = 156 }
                markdirty()
            end
        else
            local disable_rect = imgui.checkbox('Use custom icon UV rect', true)
            if disable_rect then
                item.icon_rect = nil
                markdirty()
            else
                local vec4 = Vector4f.new(item.icon_rect.x, item.icon_rect.y, item.icon_rect.w, item.icon_rect.h)
                local changed, newVec4 = imgui.drag_float4('Icon UV rect', vec4, 0.25, 0, nil, '%.0f')
                if changed then
                    item.icon_rect.x = math.floor(newVec4.x)
                    item.icon_rect.y = math.floor(newVec4.y)
                    item.icon_rect.w = math.floor(newVec4.z)
                    item.icon_rect.h = math.floor(newVec4.w)
                    markdirty()
                end
            end
        end

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
end
