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
local consts = require('editors.items.constants')

--- @class ItemDataEntity : DBEntity
--- @field runtime_instance app.ItemDataParam|app.ItemArmorParam|app.ItemWeaponParam
--- @field name string|nil
--- @field description string|nil
--- @field icon_path string|nil
--- @field icon_rect ItemUVSettings|nil
--- @field enhance app.ArmorEnhanceParam[]|app.WeaponEnhanceParam[]|nil
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

local function register_entity(id, type, runtime_instance, enhance)
    --- @type ItemDataEntity
    local entity = {
        id = id,
        type = type,
        runtime_instance = runtime_instance,
        enhance = enhance,
    }
    udb.create_entity(entity, nil, true)
    udb.mark_entity_dirty(entity, false)
    return entity
end

local get_item_name = sdk.find_type_definition('app.GUIBase'):get_method('getElfItemName(System.Int32, System.Boolean)')
local get_item_desc = sdk.find_type_definition('app.GUIBase'):get_method('getElfItemDetail(System.Int32, System.Boolean)')

local customWeaponIds = {}
local customShieldIds = {}

udb.events.on('get_existing_data', function ()
    for item in utils.enumerate(ItemManager._ItemDataDict) do
        if item.value._Id then
            local itemType = (item.value--[[@as app.ItemCommonParam]]):get_DataType()
            local enhance
            if itemType == 2 then
                enhance = ItemManager._WeaponEnhanceDict:ContainsKey(item.value._Id) and ItemManager._WeaponEnhanceDict[item.value._Id] or nil
                if consts.is_custom_item(item.value._Id) then
                    local weaponId = (item.value--[[@as app.ItemWeaponParam]])._WeaponId
                    local isMain = item.value._EquipCategory == 0
                    if isMain then
                        customWeaponIds[weaponId] = true
                    else
                        customShieldIds[weaponId] = true
                    end
                end
            elseif itemType == 3 then
                enhance = ItemManager._ArmorEnhanceDict:ContainsKey(item.value._Id) and ItemManager._ArmorEnhanceDict[item.value._Id] or nil
            end
            register_entity(item.value._Id, 'item_data', item.value, enhance)
        else
            print('Missing item id', item, item.value, item:get_type_definition():get_full_name())
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
            data = import_handlers.export(instance.runtime_instance, 'app.ItemCommonParam'),
            enhance = instance.enhance and import_handlers.export(instance.enhance) or nil,
        }
    end,
    import = function (data, instance)
        --- @cast instance ItemDataEntity
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
        local dataType = instance.runtime_instance:get_DataType()
        if data.enhance then
            if dataType == 2 then
                instance.enhance = import_handlers.import('app.WeaponEnhanceParam[]', data.enhance, instance.enhance)
                if instance.enhance then ItemManager._WeaponEnhanceDict[data.id] = instance.enhance end
            else
                instance.enhance = import_handlers.import('app.ArmorEnhanceParam[]', data.enhance, instance.enhance)
                if instance.enhance then ItemManager._ArmorEnhanceDict[data.id] = instance.enhance end
            end
        end

        if dataType == 2 and consts.is_custom_item(instance.id) then
            local weaponId = (instance.runtime_instance--[[@as app.ItemWeaponParam]])._WeaponId
            if weaponId and consts.is_custom_weapon(weaponId) then
                local isMain = instance.runtime_instance._EquipCategory == 0
                if isMain then
                    customWeaponIds[weaponId] = true
                else
                    customShieldIds[weaponId] = true
                end
            end
        end

        -- if dataType == 2 or dataType == 3 then
            -- _EquipDataDict contains conversion between item id and style string (why strings, capcom? don't you have enums everywhere??)
            -- I'm actually not sure whether this is even needed and how we're gonna tell the game to fetch it by string
            -- ItemManager._EquipDataDict[tostring(data.id)] = data.id
        -- end
    end,
    generate_label = function (entity)
        return 'Item ' .. entity.id .. ' : ' .. enums.get_enum('app.ItemIDEnum').get_label(entity.id)
    end,
    delete = function (instance)
        --- @cast instance ItemDataEntity
        if not consts.is_custom_item(instance.id) then
            return 'not_deletable'
        end

        if instance.runtime_instance then
            ItemManager._ItemDataDict:Remove(instance.id)
        end
        return 'forget'
    end,
    insert_id_range = {consts.custom_item_min_id, consts.custom_item_max_id},
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

--- @param item ItemDataEntity
--- @param tex via.gui.Texture
local function replace_item_icon(item, tex)
    if not item._texture then
        if not item.icon_path or item.icon_path == '' then return false end
        local immediateInst
        if item.icon_path:match('.tex$') then
            -- issue with using a tex resource directly:
            -- the texture loads up but then game crashes next time it shows up
            -- does the resource get garbage collected despite the add_ref()?
            -- anyway, storing it in a gameobject works
            immediateInst = prefabs.get_shared_instance(item.icon_path)
            if not immediateInst then
                immediateInst = sdk.find_type_definition("via.GameObject"):get_method("create(System.String)"):call(nil, '_' .. item.icon_path):add_ref()--[[@as via.GameObject]]
                local holder = utils.add_gameobject_component(immediateInst, 'app.GUITextureHolder')--[[@as app.GUITextureHolder]]
                holder._Texture = import_handlers.import('via.render.TextureResourceHolder', item.icon_path):add_ref()
                item._texture = holder._Texture
                prefabs.store_shared_instance(item.icon_path, immediateInst)
            else
                local holder = utils.get_gameobject_component(immediateInst, 'app.GUITextureHolder')--[[@as app.GUITextureHolder]]
                item._texture = holder._Texture
            end
            apply_icon_rect(tex, item)
        else
            immediateInst = prefabs.instantiate_shared(item.icon_path, function (gameObj)
                if not item._texture then
                    local texHolder = utils.get_gameobject_component(gameObj, 'app.GUITextureHolder') --[[@as app.GUITextureHolder|nil]]
                    item._texture = texHolder and (texHolder._Texture or texHolder._UVSequense)
                end

                if tex and sdk.is_managed_object(tex) and item._texture then
                    apply_icon_rect(tex, item)
                end
            end)
        end
        -- apply a default transparent texture instead of having it flash white.png until the prefab loads
        -- (iconNo = 8099 is empty for basegame icons, may need to change if devs add more content)
        if not immediateInst then
            tex:set_UVSequence(ItemManager:get_UVSequenceResourceManager():getUVSequenceResourceHolder(8000, 10000000))
            tex:set_UVSequenceNo(8)
            tex:set_UVPatternNo(99)
        end
        return true
    end

    if item._texture then
        apply_icon_rect(tex, item)
        return true
    end

    return false
end

-- the game does some stupid looking black magic to determine whether it wants to apply weapon damage or not
-- and has an extra check to see if it's a main or sub weapon even though it already had that info in the caller method
-- which is why we need to hook in and fix that shit for custom weapons since they're not inside the app.WeaponIDCompTable

sdk.hook(
    sdk.find_type_definition('app.PlayerAttackDefenceStatus'):get_method('setWeaponEquipParam'),
    function (args)
        local weaponId = sdk.to_int64(args[4]) & 0xffffffff--[[@as app.WeaponID]]
        if customWeaponIds[weaponId] then
            thread.get_hook_storage().equip = sdk.to_managed_object(args[3])
            thread.get_hook_storage().param = sdk.to_managed_object(args[5])
        elseif customShieldIds[weaponId] then
            thread.get_hook_storage().equip = sdk.to_managed_object(args[3])
            thread.get_hook_storage().param = sdk.to_managed_object(args[6])
        end
    end,
    function (ret)
        local equip = thread.get_hook_storage().equip--[[@as app.EquipParam]]
        if equip then
            local param = thread.get_hook_storage().param--[[@as app.EquipParam]]
            equip:copyFrom(param)
        end
        return ret
    end
)

-- the upgrade UI applies the focused item's icon UV sequence inlined, needs separate handling
-- as soon as we try to apply a custom texture, somehow the via.gui.Texture breaks and stops drawing basegame items even though the component looks unchanged
-- so until we find a solution, switching to setItemIconUV() which always works but is slightly lower quality
local upgradeMenuFoundCustomItems = false
sdk.hook(
    sdk.find_type_definition('app.ui041101_00'):get_method('awake'),
    function ()
        upgradeMenuFoundCustomItems = false
    end
)
sdk.hook(
    sdk.find_type_definition('app.ui041101_00'):get_method('setupDetail'),
    function (args)
        thread.get_hook_storage().this = sdk.to_managed_object(args[2])
    end,
    function (returnValue)
        local this = thread.get_hook_storage().this--[[@as app.ui041101_00]]

        local selectedInfo = this.ItemListCtrl:get_SelectedInfo()--[[@as app.ui041101_00.ListInfo|nil]]
        local itemIcon = selectedInfo and selectedInfo.Storage and selectedInfo.Storage._ItemData and selectedInfo.Storage._ItemData._IconNo
        if itemIcon then
            if itemIcon >= consts.custom_item_min_id then
                upgradeMenuFoundCustomItems = true
            end
            if upgradeMenuFoundCustomItems then
                sdk.find_type_definition('app.GUIBase'):get_method('setItemIconUV'):call(nil, this.UpgradeDetail.TexIcon, itemIcon)
            else
                sdk.find_type_definition('app.GUIBase'):get_method('setItemIconUVS_ui01c01'):call(nil, this.UpgradeDetail.TexIcon, itemIcon)
            end
        end

        return returnValue
    end
)

sdk.hook(
    -- I think this is the earliest common method where the game fetches item icons
    -- the game then calls getUVSequenceResourceHolder() and then applyUVSettings() when setting item icons, but we can override it right here already
    sdk.find_type_definition('app.GUIBase'):get_method('setItemIconUV'),
    function (args)
        local iconNo = sdk.to_int64(args[3]) & 0xffffffff
        if iconNo >= consts.custom_item_min_id then
            local item = udb.get_entity('item_data', iconNo) --[[@as ItemDataEntity|nil]]
            if not item then return end
            if not item._texture and (not item.icon_path or item.icon_path == '') then
                -- no icon :(
                return
            end

            local tex = sdk.to_managed_object(args[2]) --[[@as via.gui.Texture]]
            if replace_item_icon(item, tex) then
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
    if itemId >= consts.custom_item_min_id then
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
        if id and id >= consts.custom_item_min_id then
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

local ptr_true = sdk.to_ptr(true)
sdk.hook(
    -- ensure all isValid checks pass for custom items
    sdk.find_type_definition('app.ItemManager'):get_method('isValidItem'),
    function(args)
        local id = sdk.to_int64(args[2]) & 0xffffffff
        if consts.is_custom_item(id) and udb.get_entity('item_data', id) ~= nil then
            thread.get_hook_storage().result = ptr_true
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end,
    function(ret) return thread.get_hook_storage().result or ret end
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
        'Write the lua code that should be executed when this item is used.\ninput[2].from: contains the app.Character that used the item\ninput[2].to: contains the app.Character the item was used on.',
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
                _FakeItemId = { uiHandler = ui.handlers.common.enum('app.ItemIDEnum') },
                _DecayedItemId = { uiHandler = ui.handlers.common.enum('app.ItemIDEnum') },
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
        ['app.ArmorEnhanceParam'] = {
            fieldOrder = {'_Type', '_EnhanceNo', '_NeedMoney', '_NeedItemId0', '_NeedItemNum0', '_NeedItemId1', '_NeedItemNum1'},
            fields = {
                _NeedItemId0 = { uiHandler = ui.handlers.common.enum(udb.get_entity_enum('item_data')) },
                _NeedItemId1 = { uiHandler = ui.handlers.common.enum(udb.get_entity_enum('item_data')) },
            },
            toString = function (val)
                ---@cast val app.ArmorEnhanceParam
                return enums.get_enum('app.EnhanceType').get_label(val._Type) .. ' ' .. tostring(val._EnhanceNo)
            end
        },
        ['app.WeaponEnhanceParam'] = {
            fieldOrder = {'_Type', '_EnhanceNo', '_NeedMoney', '_NeedItemId0', '_NeedItemNum0', '_NeedItemId1', '_NeedItemNum1'},
            fields = {
                _NeedItemId0 = { uiHandler = ui.handlers.common.enum(udb.get_entity_enum('item_data')) },
                _NeedItemId1 = { uiHandler = ui.handlers.common.enum(udb.get_entity_enum('item_data')) },
            },
            toString = function (val)
                ---@cast val app.WeaponEnhanceParam
                return enums.get_enum('app.EnhanceType').get_label(val._Type) .. ' ' .. tostring(val._EnhanceNo)
            end,
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

    ui.editor.set_entity_editor('item_data', function (item, state)
        --- @cast item ItemDataEntity
        if not item.name then item.name = get_item_name:call(nil, item.id, false) end
        if not item.description then item.description = get_item_desc:call(nil, item.id, false) end

        local fieldsChanged = false
        local function markdirty() fieldsChanged = true end
        ui.basic.setting_text('Name', item, 'name', markdirty)
        ui.basic.setting_text('Description', item, 'description', markdirty, 4)
        ui.basic.setting_text('Icon filepath', item, 'icon_path', markdirty)
        ui.basic.tooltip('Can either be the path to a .tex file or to a .pfb with an app.GUITextureHolder component')
        if not item.icon_rect then
            local enable_rect = imgui.checkbox('Use custom icon UV rect', false)
            if enable_rect then
                item.icon_rect = { x = 0, y = 0, w = 160, h = 156 }
                fieldsChanged = true
            end
        else
            local disable_rect = imgui.checkbox('Use custom icon UV rect', true)
            if disable_rect then
                item.icon_rect = nil
                fieldsChanged = true
            else
                local vec4 = Vector4f.new(item.icon_rect.x, item.icon_rect.y, item.icon_rect.w, item.icon_rect.h)
                local changed, newVec4 = imgui.drag_float4('Icon UV rect', vec4, 0.25, 0, nil, '%.0f')
                if changed then
                    item.icon_rect.x = math.floor(newVec4.x)
                    item.icon_rect.y = math.floor(newVec4.y)
                    item.icon_rect.w = math.floor(newVec4.z)
                    item.icon_rect.h = math.floor(newVec4.w)
                    fieldsChanged = true
                end
            end
        end

        imgui.spacing()

        local itemType = item.runtime_instance:get_DataType()
        if itemType == 2 or itemType == 3 then
            state.tab = select(2, ui.basic.tabs({ 'Basic data', 'Enhance params' }, state.tab or 0))
            if state.tab == 2 then
                if not item.enhance then
                    if imgui.button('Create') then
                        local preset = usercontent.editor.presets.get_preset_data('item_enhance', itemType == 2 and 'weapon' or 'armor')
                        local enhanceClass = itemType == 2 and 'app.WeaponEnhanceParam' or 'app.ArmorEnhanceParam'
                        if preset then
                            item.enhance = import_handlers.import(enhanceClass .. '[]', preset)
                            for i = 0, 12 do item.enhance[i]._ItemId = item.id end
                        else
                            item.enhance = sdk.create_managed_array(enhanceClass, 13)
                            for i = 0, 12 do
                                item.enhance[i] = import_handlers.import(enhanceClass, {
                                    _Type = i // 3,
                                    _EnhanceNo = i % 3,
                                    _ItemId = item.id,
                                })
                            end
                        end

                        if itemType == 2 then
                            ItemManager._WeaponEnhanceDict[item.id] = item.enhance
                        else
                            ItemManager._ArmorEnhanceDict[item.id] = item.enhance
                        end
                        udb.mark_entity_dirty(item)
                    end
                else
                    if imgui.button('Remove') then
                        if itemType == 2 then
                            ItemManager._WeaponEnhanceDict:Remove(item.id)
                        else
                            ItemManager._ArmorEnhanceDict:Remove(item.id)
                        end
                        item.enhance = nil
                        udb.mark_entity_dirty(item)
                    end
                end
                return ui.handlers.show_editable(item, 'enhance', item) or fieldsChanged
            else
                return ui.handlers.show_editable(item, 'runtime_instance', item) or fieldsChanged
            end
        else
            return ui.handlers.show_editable(item, 'runtime_instance', item) or fieldsChanged
        end
    end)

    editor.define_window('item_data', 'Item data', function (state)
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
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            ui.editor.show_entity_editor(selectedItem, state)
            imgui.end_rect(4)
            imgui.unindent(8)
            imgui.spacing()
        end
    end)
end
