local udb = require('content_editor.database')
local import_handlers = require('content_editor.import_handlers')

local core = require('content_editor.core')
local utils = require('content_editor.utils')
local enums = require('content_editor.enums')

local definitions = require('content_editor.definitions')

local generic_types = require('content_editor.generic_types')

local CharacterManager = sdk.get_managed_singleton('app.CharacterManager') --- @type app.CharacterManager
local PawnManager = sdk.get_managed_singleton('app.PawnManager') --- @type app.PawnManager
local CharacterEditManager = sdk.get_managed_singleton('app.CharacterEditManager') --- @type app.CharacterEditManager
local ItemManager = sdk.get_managed_singleton('app.ItemManager') --- @type app.ItemManager
local GuiManager = sdk.get_managed_singleton('app.GuiManager') --- @type app.GuiManager

local exFurmaskDictType
local function get_ex_furmask_dict_type()
    if exFurmaskDictType then return exFurmaskDictType end

    local rootType = CharacterEditManager._FurMaskMapExCatalog:GetType() ---@type System.Type
    local exFurmaskType = rootType:GetGenericArguments()[1]:GetGenericArguments()[1]:GetGenericArguments()[1]
    exFurmaskDictType = generic_types.get_clean_generic_classname(exFurmaskType:get_FullName()--[[@as string]])
    generic_types.add(exFurmaskDictType, exFurmaskType)

    exFurmaskType = exFurmaskType:GetGenericArguments()[1]
    local subtype = generic_types.get_clean_generic_classname(exFurmaskType:get_FullName()--[[@as string]])
    generic_types.add(subtype, exFurmaskType)

    return exFurmaskDictType
end

--- @class StyleEntity : DBEntity
--- @field variants table<string,app.TopsSwapItem|app.PantsSwapItem|app.MantleSwapItem|app.HelmSwapItem|app.UnderwearSwapItem|app.BackpackSwapItem|app.BackpackStyle>
--- @field furmasks table<string,app.PrefabController>|nil
--- @field styleHash integer

--- @class StyleData : EntityImportData
--- @field data table<integer, table>
--- @field furmasks table<string,string>|nil
--- @field exFurmasks table<string,table<string,any>>|nil
--- @field styleHash integer

local genders = {
    Female = 1910070090,
    Female_str = '1910070090',
    Male = 2776536455,
    Male_str = '2776536455',
}

local variantKeys = {genders.Male_str, genders.Female_str}
local variantLabels = {
    [genders.Male_str] = 'Male (2776536455)',
    [genders.Female_str] = 'Female (1910070090)',
}

--- note to self: furmasks are on CharacterEditManager
--- hair furmasks: _FurMaskMapCatalog
--- underwear lower furmasks: _furMaskMapGenderCatalog[1]
--- underwear upper furmasks: _furMaskMapGenderCatalog[2] (female only)
--- tops furmasks: _furMaskMapGenderCatalog[3]
--- pants furmasks: _furMaskMapGenderCatalog[4]
--- helm furmasks: _furMaskMapGenderCatalog[5]
--- facewear furmasks: _furMaskMapGenderCatalog[6]

--- @class StyleRecordType
--- @field styleDb string Entity style DB field name
--- @field swap string Swap data classname
--- @field enum string Style enum
--- @field styleDict string|nil Name of style lookup dictionary in app.ItemManager
--- @field slot integer|nil app.EquipData.SlotEnum value
--- @field styleField string
--- @field styleNoEnum EnumSummary|nil
--- @field furmaskIndex integer|nil

--- @type table<string, StyleRecordType>
local recordClasses = {
    PantsStyle = { styleDb = '_PantsDB', swap = 'app.PantsSwapItem', enum = 'app.PantsStyle', styleDict = 'PantsDict', slot = 4, styleField = '_PantsStyle', styleNoEnum = enums.get_virtual_enum('PantsStyleNo', {}), furmaskIndex = 4 },
    TopsStyle = { styleDb = '_TopsDB', swap = 'app.TopsSwapItem', enum = 'app.TopsStyle', styleDict = 'TopsDict', slot = 3, styleField = '_TopsStyle', styleNoEnum = enums.get_virtual_enum('TopsStyleNo', {}), furmaskIndex = 3 },
    HelmStyle = { styleDb = '_HelmDB', swap = 'app.HelmSwapItem', enum = 'app.HelmStyle', styleDict = 'HelmDict', slot = 2, styleField = '_HelmStyle', styleNoEnum = enums.get_virtual_enum('HelmStyleNo', {}), furmaskIndex = 5 },
    MantleStyle = { styleDb = '_MantleDB', swap = 'app.MantleSwapItem', enum = 'app.MantleStyle', styleDict = 'MantleDict', slot = 5, styleField = '_MantleStyle', styleNoEnum = enums.get_virtual_enum('MantleStyleNo', {}) },
    BackpackStyle = { styleDb = '_BackpackDB', swap = 'app.BackpackSwapItem', enum = 'app.BackpackStyle', styleField = '_BackpackStyle' },
    UnderwearStyle = { styleDb = '_UnderwearDB', swap = 'app.UnderwearSwapItem', enum = 'app.UnderwearStyle', styleField = '_Style' },
    FacewearStyle = { styleDb = '_FacewearDB', swap = 'app.FacewearSwapItem', enum = 'app.FacewearStyle', styleDict = 'FaceDict', slot = 7, styleField = '_Style', styleNoEnum = enums.get_virtual_enum('FacewearStyleNo', {}), furmaskIndex = 6 },
    -- _BodySkinDB = {'app.BodySkinSwapItem', 'app.SkinStyle'},
    -- _BodyMuscleDB = {'app.BodyMuscleSwapItem', 'app.MuscleStyle'},
    -- _BodyMeshDB = {'app.BodyMeshSwapItem', 'app.BodyMeshStyle'}, -- species +  gender
    -- _BodyHairDB = {'app.BodyHairSwapItem', nil}, -- uint + uint
    -- _HeadMeshDB = {'app.HeadMeshSwapItem', 'app.HeadStyle'}, -- species + gender + headstyle
    -- _HeadSkinDB = {'app.HeadSkinSwapItem', 'app.SkinStyle'}, -- species + gender + skinstyle
}
local recordTypes = utils.get_sorted_table_keys(recordClasses) ---@type string[]

local visorIds = {}

local styleItemLookups = nil

local function dict_get_safe(dict, key)
    return dict and dict:ContainsKey(key) and dict[key] or nil
end

-- the real implementation does an Array.Contains() on app.CharacterEditDefine.VisorControlEnable but we can't modify that
local ptr_true = sdk.to_ptr(true)
sdk.hook(
    sdk.find_type_definition('app.MockupCtrl'):get_method('isControlVisor'),
    function (args)
        local mockup = sdk.to_managed_object(args[2]) --[[@as app.MockupCtrl]]
        local style = mockup.CompBuilder._RefPartSwapper._Meta._HelmStyle
        if visorIds[style] then
            thread.get_hook_storage().rv = ptr_true
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end,
    function (ret) return thread.get_hook_storage().rv or ret end
)

sdk.hook(
    -- sdk.find_type_definition('app.MockupCtrl'):get_method('changeVisor(app.Character, System.Boolean)'),
    sdk.find_type_definition('app.MockupCtrl'):get_method('changeVisor(app.Character, System.Boolean, System.Boolean)'),
    function (args)
        local mockup = sdk.to_managed_object(args[2]) --[[@as app.MockupCtrl]]
        local partSwapper = mockup.CompBuilder._RefPartSwapper
        local style = partSwapper._Meta._HelmStyle
        if visorIds[style] then
            local chara = sdk.to_managed_object(args[3]) --[[@as app.Character]]
            local visorUp = (sdk.to_int64(args[4]) & 1) ~= 0
            local changeMenuFace = (sdk.to_int64(args[5]) & 1) ~= 0
            -- in case we'd need to override the other overload without the visorUp param as well:
            -- local newVisorFlag = (partSwapper._VisorSwitch ~= 2 and 2 or 1)
            local newVisorFlag = visorUp and 1 or 2
            if partSwapper._VisorSwitch ~= newVisorFlag then
                partSwapper._UpdateStatusOfSwapObjects = true
            end
            partSwapper._VisorSwitch = newVisorFlag
            if partSwapper._HumanContext ~= nil then
                partSwapper._HumanContext._VisorSwitch = newVisorFlag
            end
            if chara and chara:get_Enabled() then
                local hps = chara:get_HumanPartSwapper()
                if hps then hps._VisorSwitch = newVisorFlag end
                if changeMenuFace then
                    GuiManager:updateMenuFace(chara)
                end
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end
)

local function add_style_entity(id, entityType, variant_id, styleHash, runtime_instance, furmask)
    local entity = udb.get_entity(entityType, id)
    --- @cast entity StyleEntity|nil
    if entity then
        entity.variants[tostring(variant_id)] = runtime_instance
        if furmask then
            entity.furmasks = entity.furmasks or {}
            entity.furmasks[tostring(variant_id)] = furmask
        end
    else
        --- @type StyleEntity
        entity = {
            id = id,
            type = entityType,
            styleHash = styleHash,
            variants = {[tostring(variant_id)] = runtime_instance },
        }
        if furmask then entity.furmasks = {[tostring(variant_id)] = furmask} end

        udb.register_pristine_entity(entity)
    end
    return entity
end

udb.events.on('get_existing_data', function (whitelist)
    for name, type in pairs(recordClasses) do
        if whitelist and not whitelist[name] then goto continue end

        local wl = whitelist and whitelist[name]
        if type.styleDict then
            local root_enumerator = ItemManager[type.styleDict]:GetEnumerator()
            while root_enumerator:MoveNext() do
                local styleId = root_enumerator._current.key
                if not wl or wl[styleId] then
                    local styleHash = root_enumerator._current.value
                    local variants = CharacterEditManager[type.styleDb]:GetEnumerator()
                    while variants:MoveNext() do
                        local variant = variants._current.key
                        if variants._current.value:ContainsKey(styleHash) then
                            local swapData = variants._current.value[styleHash]
                            local furmask
                            if type.furmaskIndex then
                                local furmaskContainer = CharacterEditManager._FurMaskMapGenderCatalog[type.furmaskIndex]
                                furmask = furmaskContainer and dict_get_safe(furmaskContainer, variant)
                                furmask = furmask and dict_get_safe(furmask, styleHash) or nil
                            end
                            add_style_entity(styleId, name, variant, styleHash, swapData, furmask)
                        else
                            -- non-playable style, idk, for npcs or enemies maybe?
                            -- ignore all of these for now
                            -- print('missing style swap', styleId, styleHash, variant)
                        end
                    end
                end
            end
        else
            -- underwears and backpacks don't have distinct style numbers, use hash == nr here
            local root_dict = CharacterEditManager[type.styleDb]:GetEnumerator()
            while root_dict:MoveNext() do
                local root_item = root_dict._current
                local enumerator = root_item.value:GetEnumerator()
                while enumerator:MoveNext() do
                    local item = enumerator._current
                    local styleHash = item.key
                    if not wl or wl[styleHash] then
                        add_style_entity(styleHash, name, root_item.key, styleHash, item.value)
                    end
                end
            end
        end
        ::continue::
    end
end)

local function get_ex_furmasks(furmaskIndex, styleHash)
    local root = CharacterEditManager._FurMaskMapExCatalog[furmaskIndex]
    if not root then return {} end
    local male = dict_get_safe(dict_get_safe(root, genders.Male), styleHash)
    local female = dict_get_safe(dict_get_safe(root, genders.Female), styleHash)

    if male or female then return { [genders.Male_str] = male, [genders.Female_str] = female } end
    return nil
end

for _, name in ipairs(recordTypes) do
    local record = recordClasses[name]
    local class = record.swap
    local hasFurmasks = record.furmaskIndex ~= nil
    local styleHashEnum = utils.clone_table(enums.get_enum(record.enum).valueToLabel)
    udb.register_entity_type(name, {
        export = function (entity)
            --- @cast entity StyleEntity
            local furmasks = nil
            if hasFurmasks then
                furmasks = import_handlers.export_table(entity.furmasks or {}, 'app.PrefabController') or {}
                furmasks[variantKeys[1]] = furmasks[variantKeys[1]] or 'null'
                furmasks[variantKeys[2]] = furmasks[variantKeys[2]] or 'null'
            end
            local exFurmasks = hasFurmasks and get_ex_furmasks(record.furmaskIndex, entity.styleHash) or nil
            return {
                styleHash = entity.styleHash,
                data = import_handlers.export_table(entity.variants, class),
                furmasks = furmasks,
                exFurmasks = exFurmasks and import_handlers.export_table(exFurmasks, get_ex_furmask_dict_type()) or nil,
            }
        end,
        import = function (data, entity)
            --- @cast entity StyleEntity
            --- @cast data StyleData
            entity.variants = entity.variants or {}
            entity.styleHash = data.styleHash or data.id
            local hasVisor = false
            for variantKey, variantImport in pairs(data.data) do
                local variant = import_handlers.import(class, variantImport, entity.variants[variantKey])
                entity.variants[variantKey] = variant
                variant[record.styleField] = data.id
                if variant then
                    CharacterEditManager[record.styleDb][tonumber(variantKey)][data.id] = variant
                    hasVisor = hasVisor
                        or variant._VisorControl and variant._VisorControl ~= 0
                        or variant._SubVisorControl and variant._SubVisorControl ~= 0
                else
                    CharacterEditManager[record.styleDb][tonumber(variantKey)]:Remove(data.id)
                end
            end
            if name == 'HelmStyle' then
                visorIds[data.id] = hasVisor or nil
            end
            if data.furmasks then
                entity.furmasks = entity.furmasks or {}
                for k, v in pairs(data.furmasks) do
                    local importedFurmask = import_handlers.import('app.PrefabController', v, entity.furmasks[k])
                    entity.furmasks[k] = importedFurmask
                    if CharacterEditManager._FurMaskMapGenderCatalog[record.furmaskIndex][tonumber(k)] then
                        if importedFurmask then
                            CharacterEditManager._FurMaskMapGenderCatalog[record.furmaskIndex][tonumber(k)][data.styleHash] = importedFurmask
                        else
                            CharacterEditManager._FurMaskMapGenderCatalog[record.furmaskIndex][tonumber(k)]:Remove(data.styleHash)
                        end
                    end
                end
            end
            if record.furmaskIndex and data.exFurmasks then
                local specificFurmasks = get_ex_furmasks(record.furmaskIndex, data.styleHash)
                if data.exFurmasks[genders.Male_str] then
                    CharacterEditManager._FurMaskMapExCatalog[record.furmaskIndex][genders.Male][data.styleHash] =
                        import_handlers.import(get_ex_furmask_dict_type(), data.exFurmasks[genders.Male_str], specificFurmasks and specificFurmasks[genders.Male_str])
                end
                if data.exFurmasks[genders.Female_str] then
                    CharacterEditManager._FurMaskMapExCatalog[record.furmaskIndex][genders.Female][data.styleHash] =
                        import_handlers.import(get_ex_furmask_dict_type(), data.exFurmasks[genders.Female_str], specificFurmasks and specificFurmasks[genders.Female_str])
                end
            end

            if record.styleDict then
                ItemManager[record.styleDict][data.id] = entity.styleHash
            end
        end,
        generate_label = function (entity)
            --- @cast entity StyleEntity
            if not entity.styleHash then return name .. ' ' .. entity.id end

            local styleName = (styleHashEnum[entity.styleHash] or (name .. ' ' .. entity.id))
            if not styleItemLookups then
                -- construct item lookup table
                styleItemLookups = {}
                for pair in utils.enumerate(ItemManager._ItemDataDict) do
                    local itemId = pair.key---@type integer
                    local item = pair.value
                    --- @cast item app.ItemArmorParam
                    if item:get_DataType() == 3 and item._StyleNo ~= 0 then
                        if not styleItemLookups[item._EquipCategory] then styleItemLookups[item._EquipCategory] = {} end
                        if styleItemLookups[item._EquipCategory][item._StyleNo] then
                            local previousValid = ItemManager.isValidItem(styleItemLookups[item._EquipCategory][item._StyleNo])
                            local newValid = ItemManager.isValidItem(itemId)
                            if previousValid ~= newValid and newValid then
                                styleItemLookups[item._EquipCategory][item._StyleNo] = itemId
                            elseif newValid and previousValid then
                                print('Two item IDs were found valid for style entry', item._StyleNo, 'category', item._EquipCategory, 'previous ID', styleItemLookups[item._EquipCategory][item._StyleNo], 'newId', itemId)
                            end
                        else
                            styleItemLookups[item._EquipCategory][item._StyleNo] = itemId
                        end
                    end
                end
            end

            local itemId = record.slot and styleItemLookups[record.slot] and styleItemLookups[record.slot][entity.id]
            if itemId then
                styleName = styleName .. ' ' .. tostring(ItemManager:getItemData(itemId):get_Name())
            end

            if entity.id ~= entity.styleHash then
                styleName = styleName .. ' #' .. tostring(entity.styleHash)
            end
            return styleName
        end,
        delete = function (entity)
            --- @cast entity StyleEntity
            if not udb.is_custom_entity_id(entity.type, entity.id) then return 'forget' end

            if entity.furmasks then
                for k, v in pairs(entity.furmasks) do
                    CharacterEditManager._FurMaskMapGenderCatalog[record.furmaskIndex][tonumber(k)]:Remove(entity.styleHash)
                end
            end

            if record.styleDict then
                ItemManager[record.styleDict]:Remove(entity.id)
            end

            for variantKey, _ in pairs(entity.variants or {}) do
                CharacterEditManager[record.styleDb][tonumber(variantKey)]:Remove(entity.id)
            end

            return 'ok'
        end,
        replaced_enum = record.styleNoEnum and record.styleNoEnum.enumName or nil,
        insert_id_range = {10000, 32700}, -- _StyleNo on the armor data is a signed short so we need to limit to that range
        root_types = {class},
    })
end

definitions.override('styles', {
    ['app.HelmSwapItem'] = { fields = { _HelmStyle = { ui_ignore = true, import_ignore = true } } },
    ['app.TopsSwapItem'] = { fields = { _TopsStyle = { ui_ignore = true, import_ignore = true } } },
    ['app.PantsSwapItem'] = { fields = { _PantsStyle = { ui_ignore = true, import_ignore = true } } },
    ['app.MantleSwapItem'] = { fields = { _MantleStyle = { ui_ignore = true, import_ignore = true } } },
    ['app.BackpackSwapItem'] = { fields = { _BackpackStyle = { ui_ignore = true, import_ignore = true } } },
    ['app.UnderwearSwapItem'] = { fields = { _UnderwearStyle = { ui_ignore = true, import_ignore = true } } },
    ['app.FacewearSwapItem'] = { fields = { _Style = { ui_ignore = true, import_ignore = true } } },
})

if core.editor_enabled then
    local editor = require('content_editor.editor')
    local ui = require('content_editor.ui')
    local helpers = require('content_editor.helpers')

    --- @param character app.Character
    local function forceRefresh(character, part)
        local partSwapper = character:get_HumanPartSwapper()
        if partSwapper then
            if part == 1 then partSwapper:swapFurMaskMap() end
            if part == 2 then partSwapper:forceUpdateStatusOfSwapObjects() end
            if part == 3 then partSwapper:call('requestSwap(app.PartSwapper.Parts)', 32 + 64 + 128 + 256) end
        end
    end

    definitions.override('', {
        ['app.TopsAmPartFlags'] = { uiHandler = ui.handlers.common.enum_flags(nil, 6) },
        ['app.TopsBdPartFlags'] = { uiHandler = ui.handlers.common.enum_flags(nil, 6) },
        ['app.TopsBtPartFlags'] = { uiHandler = ui.handlers.common.enum_flags(nil, 6) },
        ['app.HandPartFlags'] = { uiHandler = ui.handlers.common.enum_flags(nil, 6) },
        ['app.HelmPartFlags'] = { uiHandler = ui.handlers.common.enum_flags(nil, 6) },
        ['app.TopsWbPartFlags'] = { uiHandler = ui.handlers.common.enum_flags(nil, 6) },
        ['app.PantsLgPartFlags'] = { uiHandler = ui.handlers.common.enum_flags(nil, 6) },
        ['app.FootPartFlags'] = { uiHandler = ui.handlers.common.enum_flags(nil, 6) },
        ['app.PantsWlPartFlags'] = { uiHandler = ui.handlers.common.enum_flags(nil, 6) },
        ['app.BackpackPartFlags'] = { uiHandler = ui.handlers.common.enum_flags(nil, 6) },
        ['app.FacewearPartFlags'] = { uiHandler = ui.handlers.common.enum_flags(nil, 6) },
        ['app.BeardPartFlags'] = { uiHandler = ui.handlers.common.enum_flags(nil, 6) },
        ['app.CharacterEditDefine.VisorControlFlag'] = { uiHandler = ui.handlers.common.enum_flags(enums.get_enum('app.CharacterEditDefine.VisorControlFlag')) },
    })

    local function showStyles(selectedItem, state)
        local recordData = recordClasses[state.style_type]
        imgui.text('Style ID: ' .. selectedItem.id)
        imgui.text('Style hash: ' .. tostring(selectedItem.styleHash))
        local variantIds = utils.get_sorted_table_keys(selectedItem.variants)
        local variantIdLabels = utils.map(variantIds, function (value) return variantLabels[value] or value end)
        state.variant_id = select(2, imgui.combo('Variant', state.variant_id, variantIdLabels))
        local furmaskChanged, meshesChanged, stylesChanged = false, false, false
        if state.variant_id and variantIds[state.variant_id] then
            local variantKey = variantIds[state.variant_id]
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            imgui.text('Selected variant')
            if recordData.furmaskIndex then
                local furmask = selectedItem.furmasks and selectedItem.furmasks[variantKey]
                local path = furmask and furmask:get_ResourcePath()
                local changed, newpath = imgui.input_text('Furmask .pfb', path or '')
                if changed then
                    furmaskChanged = true
                    if furmask then
                        if newpath and newpath ~= '' then
                            if newpath ~= path then
                                furmask._Item:set_Path(newpath)
                                udb.mark_entity_dirty(selectedItem)
                            end
                        else
                            if selectedItem.furmasks then
                                selectedItem.furmasks[variantKey] = nil
                            end
                            CharacterEditManager._FurMaskMapGenderCatalog[recordData.furmaskIndex][tonumber(variantKey)]:Remove(selectedItem.styleHash)
                            udb.mark_entity_dirty(selectedItem)
                        end
                    elseif newpath and newpath ~= '' then
                        local pfbCtrl = import_handlers.import('app.PrefabController', newpath)
                        selectedItem.furmasks = selectedItem.furmasks or {}
                        selectedItem.furmasks[variantKey] = pfbCtrl
                        CharacterEditManager._FurMaskMapGenderCatalog[recordData.furmaskIndex][tonumber(variantKey)][selectedItem.styleHash] = pfbCtrl
                        udb.mark_entity_dirty(selectedItem)
                    end
                end

                local specificFurmasks = get_ex_furmasks(recordData.furmaskIndex, selectedItem.styleHash)
                specificFurmasks = specificFurmasks and specificFurmasks[variantKey]
                if specificFurmasks then
                    furmaskChanged = ui.handlers.show(specificFurmasks, selectedItem, 'Per-vocation furmasks', get_ex_furmask_dict_type(), state) or furmaskChanged
                else
                    if imgui.button('Add per-vocation furmasks') then
                        CharacterEditManager._FurMaskMapExCatalog[recordData.furmaskIndex][tonumber(variantKey)][selectedItem.styleHash] = helpers.create_generic_instance(get_ex_furmask_dict_type())
                        furmaskChanged = true
                    end
                end

                if imgui.button('Force swap meshes') then
                    meshesChanged = true
                end
                imgui.same_line()
                state.autorefresh = select(2, imgui.checkbox('Auto-refresh styles and furmasks', state.autorefresh == nil and true or state.autorefresh))
                if imgui.is_item_hovered() then imgui.set_tooltip('Will force any style or furmask changes to apply to the player and pawns in realtime\nMesh changes are a bit slow, use the button or re-equip items for those') end
            end
            stylesChanged = ui.handlers.show_editable(selectedItem.variants, variantKey, selectedItem)

            if state.autorefresh then
                local refreshPart = furmaskChanged and 1 or stylesChanged and 2 or meshesChanged and 3 or nil
                if refreshPart then
                    local player = CharacterManager:get_ManualPlayer()
                    if player then forceRefresh(player, refreshPart) end
                    local it = PawnManager._PawnCharacterList:GetEnumerator()
                    while it:MoveNext() do forceRefresh(it._current, refreshPart) end
                end
            end
            imgui.end_rect(4)
            imgui.unindent(8)
            imgui.spacing()
        end
        return furmaskChanged or meshesChanged or stylesChanged
    end

    for _, rtype in ipairs(recordTypes) do
        ui.editor.set_entity_editor(rtype, showStyles)
    end

    local equipped_style_result
    editor.define_window('styles', 'Styles', function (state)
        local styleIdx = select(2, ui.basic.tabs(recordTypes, utils.table_index_of(recordTypes, state.style_type or '')))
        state.style_type = recordTypes[styleIdx]
        if state.style_type then
            imgui.spacing()
            local recordData = recordClasses[state.style_type]
            local entity_type = state.style_type

            if editor.active_bundle then
                local create, preset = ui.editor.create_button_with_preset(state, state.style_type, nil, nil, nil, nil, true)
                if create then
                    -- print('creating style from preset', state.style_type, json.dump_string(preset))
                    local newEntity = udb.insert_new_entity(state.style_type, editor.active_bundle, preset)
                    ui.editor.set_selected_entity_picker_entity(state, state.style_type, newEntity)
                end
            end

            if recordData and recordData.slot and imgui.button('Find currently equipped item') then
                local playerId = enums.get_enum('app.CharacterID').labelToValue.ch000000_00
                local equipData = ItemManager:getEquipData(playerId):get(recordData.slot)
                local styleNo = equipData and equipData._ItemData and equipData._ItemData--[[@as app.ItemCommonParam|app.ItemArmorParam]]._StyleNo
                if styleNo then
                    local styleEntity = udb.get_entity(entity_type, styleNo)
                    if styleEntity then
                        ui.editor.set_selected_entity_picker_entity(state, entity_type, styleEntity)
                    else
                        equipped_style_result = styleNo
                    end
                else
                    equipped_style_result = nil
                end
            end
            if equipped_style_result then
                imgui.text('Could not find a style for style number: ' .. equipped_style_result)
                imgui.text('Try and find it manually somehow please')
            end
            local selectedItem = ui.editor.entity_picker(entity_type, state)
            if selectedItem then
                --- @cast selectedItem StyleEntity
                imgui.spacing()
                imgui.indent(8)
                imgui.begin_rect()
                ui.editor.show_entity_metadata(selectedItem)
                showStyles(selectedItem, state)
                imgui.end_rect(4)
                imgui.unindent(8)
                imgui.spacing()
            end
        end
    end)
end
