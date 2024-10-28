local udb = require('content_editor.database')
local import_handlers = require('content_editor.import_handlers')

local core = require('content_editor.core')
local utils = require('content_editor.utils')
local enums = require('content_editor.enums')

local definitions = require('content_editor.definitions')

local CharacterEditManager = sdk.get_managed_singleton('app.CharacterEditManager') --- @type app.CharacterEditManager
local ItemManager = sdk.get_managed_singleton('app.ItemManager') --- @type app.ItemManager

--- @class StyleEntity : DBEntity
--- @field variants table<string,app.TopsSwapItem|app.PantsSwapItem|app.MantleSwapItem|app.HelmSwapItem|app.UnderwearSwapItem|app.BackpackSwapItem|app.BackpackStyle>
--- @field styleHash integer

--- @class StyleData : EntityImportData
--- @field data table<integer, table>
--- @field styleHash integer

local variantLabels = {
    ['2776536455'] = '2776536455 Male',
    ['1910070090'] = '1910070090 Female',
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

--- @type table<string, StyleRecordType>
local recordClasses = {
    PantsStyle = { styleDb = '_PantsDB', swap = 'app.PantsSwapItem', enum = 'app.PantsStyle', styleDict = 'PantsDict', slot = 4, styleField = '_PantsStyle', styleNoEnum = enums.get_virtual_enum('PantsStyleNo', {}) },
    TopsStyle = { styleDb = '_TopsDB', swap = 'app.TopsSwapItem', enum = 'app.TopsStyle', styleDict = 'TopsDict', slot = 3, styleField = '_TopsStyle', styleNoEnum = enums.get_virtual_enum('TopsStyleNo', {}) },
    HelmStyle = { styleDb = '_HelmDB', swap = 'app.HelmSwapItem', enum = 'app.HelmStyle', styleDict = 'HelmDict', slot = 2, styleField = '_HelmStyle', styleNoEnum = enums.get_virtual_enum('HelmStyleNo', {}) },
    MantleStyle = { styleDb = '_MantleDB', swap = 'app.MantleSwapItem', enum = 'app.MantleStyle', styleDict = 'MantleDict', slot = 5, styleField = '_MantleStyle', styleNoEnum = enums.get_virtual_enum('MantleStyleNo', {}) },
    BackpackStyle = { styleDb = '_BackpackDB', swap = 'app.BackpackSwapItem', enum = 'app.BackpackStyle', styleField = '_BackpackStyle' },
    UnderwearStyle = { styleDb = '_UnderwearDB', swap = 'app.UnderwearSwapItem', enum = 'app.UnderwearStyle', styleField = '_Style' },
    -- _BodySkinDB = {'app.BodySkinSwapItem', 'app.SkinStyle'},
    -- _BodyMuscleDB = {'app.BodyMuscleSwapItem', 'app.MuscleStyle'},
    -- _BodyMeshDB = {'app.BodyMeshSwapItem', 'app.BodyMeshStyle'}, -- species +  gender
    -- _BodyHairDB = {'app.BodyHairSwapItem', nil}, -- uint + uint
    -- _HeadMeshDB = {'app.HeadMeshSwapItem', 'app.HeadStyle'}, -- species + gender + headstyle
    -- _HeadSkinDB = {'app.HeadSkinSwapItem', 'app.SkinStyle'}, -- species + gender + skinstyle
}
local recordTypes = utils.get_sorted_table_keys(recordClasses)

local function add_style_entity(id, entityType, variant_id, styleHash, runtime_instance)
    local entity = udb.get_entity(entityType, id)
    --- @cast entity StyleEntity|nil
    if entity then
        entity.variants[tostring(variant_id)] = runtime_instance
    else
        entity = {
            id = id,
            type = entityType,
            styleHash = styleHash,
            variants = {[tostring(variant_id)] = runtime_instance },
        }

        udb.register_pristine_entity(entity)
    end
    return entity
end

udb.events.on('get_existing_data', function ()
    for name, type in pairs(recordClasses) do
        if type.styleDict then
            local root_enumerator = ItemManager[type.styleDict]:GetEnumerator()
            while root_enumerator:MoveNext() do
                local styleId = root_enumerator._current.key
                local styleHash = root_enumerator._current.value
                local variants = CharacterEditManager[type.styleDb]:GetEnumerator()
                while variants:MoveNext() do
                    local variant = variants._current.key
                    local swapData = variants._current.value[styleHash]
                    if swapData then
                        add_style_entity(styleId, name, variant, styleHash, swapData)
                    else
                        -- non-playable style, idk, for npcs or enemies maybe?
                        -- ignore all of these for now
                        -- print('missing style swap', styleId, styleHash, variant)
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
                    add_style_entity(styleHash, name, root_item.key, styleHash, item.value)
                end
            end
        end
    end
end)

for _, name in ipairs(recordTypes) do
    local record = recordClasses[name]
    local class = record.swap
    local styleHashEnum = utils.clone_table(enums.get_enum(record.enum).valueToLabel)
    udb.register_entity_type(name, {
        export = function (instance)
            --- @cast instance StyleEntity
            return {
                styleHash = instance.styleHash,
                data = utils.map_assoc(instance.variants, function (variant)
                    return import_handlers.export(variant, class)
                end),
            }
        end,
        import = function (data, instance)
            --- @cast instance StyleEntity
            --- @cast data StyleData
            instance = instance or {}
            instance.variants = instance.variants or {}
            instance.styleHash = data.styleHash or data.id
            for variantKey, variantImport in pairs(data.data) do
                local variant = import_handlers.import(class, variantImport, instance.variants[variantKey])
                instance.variants[variantKey] = variant
                variant[record.styleField] = data.id
                CharacterEditManager[record.styleDb][tonumber(variantKey)][data.id] = variant
            end

            if record.styleDict then
                ItemManager[record.styleDict][data.id] = instance.styleHash
            end

            return instance
        end,
        generate_label = function (entity)
            --- @cast entity StyleEntity
            if entity.styleHash then
                return (styleHashEnum[entity.styleHash] or (name .. ' ' .. entity.id)) .. ' #' .. tostring(entity.styleHash)
            else
                return name .. ' ' .. entity.id
            end
        end,
        replaced_enum = record.styleNoEnum and record.styleNoEnum.enumName or nil,
        insert_id_range = {10000, 32700}, -- _StyleNo on the armor data is a signed short so we need to limit to that range
        root_types = {class},
    })
end

if core.editor_enabled then
    local editor = require('content_editor.editor')
    local ui = require('content_editor.ui')

    definitions.override('styles', {
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
        ['app.HelmSwapItem'] = { fields = { _HelmStyle = { ui_ignore = true, import_ignore = true } } },
        ['app.TopsSwapItem'] = { fields = { _TopsStyle = { ui_ignore = true, import_ignore = true } } },
        ['app.PantsSwapItem'] = { fields = { _PantsStyle = { ui_ignore = true, import_ignore = true } } },
        ['app.MantleSwapItem'] = { fields = { _MantleStyle = { ui_ignore = true, import_ignore = true } } },
        ['app.BackpackSwapItem'] = { fields = { _BackpackStyle = { ui_ignore = true, import_ignore = true } } },
        ['app.UnderwearSwapItem'] = { fields = { _UnderwearStyle = { ui_ignore = true, import_ignore = true } } },
    })

    local equipped_style_result
    editor.define_window('styles', 'Styles', function (state)
        _, state.style_type, state.style_type_filter = ui.core.combo_filterable('Style type', state.style_type, recordTypes, state.style_type_filter or '')
        if state.style_type then
            local recordData = recordClasses[state.style_type]
            local entity_type = state.style_type

            if editor.active_bundle then
                local create, preset = ui.editor.create_button_with_preset(state, state.style_type, nil, nil, nil, nil, true)
                if create then
                    print('creating style from preset', state.style_type, json.dump_string(preset))
                    local newEntity = udb.insert_new_entity(state.style_type, editor.active_bundle, preset)
                    ui.editor.set_selected_entity_picker_entity(state, state.style_type, newEntity)
                end
            end

            if recordData and recordData.slot and imgui.button('Find currently equipped item') then
                local playerId = enums.get_enum('app.CharacterID').labelToValue.ch000000_00
                local equipData = ItemManager:getEquipData(playerId):get(recordData.slot)
                local styleNo = equipData and equipData._ItemData and equipData._ItemData--[[@as app.ItemCommonParam|app.ItemArmorParam]]._StyleNo
                if styleNo then
                    local styleHash = recordData.styleDict and ItemManager[recordData.styleDict][styleNo]
                    if not styleHash then
                        -- fallback in case something's missing, may not be useful with the styleDict lookup
                        local styleEnumSuffix = string.format('_%03d[ $]', styleNo)
                        local matches = udb.get_entities_where(entity_type, function (entity)
                            --- @cast entity StyleEntity
                            return entity.label and entity.label:find(styleEnumSuffix) ~= nil or false
                        end)
                        if #matches == 1 then
                            styleHash = matches[1]
                        else
                            equipped_style_result = styleNo
                        end
                    end
                    if styleHash then
                        ui.editor.set_selected_entity_picker_entity(state, entity_type, styleHash)
                    end
                else
                    equipped_style_result = nil
                end
            end
            if equipped_style_result then
                imgui.text('Could not match an exact style object for style number: ' .. equipped_style_result)
                imgui.text('Try and find it manually somehow please')
            end
            local selectedItem = ui.editor.entity_picker(entity_type, state)
            if selectedItem then
                --- @cast selectedItem StyleEntity
                imgui.spacing()
                imgui.indent(8)
                imgui.begin_rect()
                ui.editor.show_entity_metadata(selectedItem)
                imgui.text('Style ID: ' .. selectedItem.id)
                imgui.text('Style hash: ' .. tostring(selectedItem.styleHash))
                local variantIds = utils.get_sorted_table_keys(selectedItem.variants)
                local variantIdLabels = utils.map(variantIds, function (value) return variantLabels[value] or value end)
                state.variant_id = select(2, imgui.combo('Variant', state.variant_id, variantIdLabels))
                if state.variant_id and variantIds[state.variant_id] then
                    imgui.spacing()
                    imgui.indent(8)
                    imgui.begin_rect()
                    imgui.text('Selected variant')
                    ui.handlers.show_editable(selectedItem.variants, variantIds[state.variant_id], selectedItem)
                    imgui.end_rect(4)
                    imgui.unindent(8)
                    imgui.spacing()
                end
                imgui.end_rect(4)
                imgui.unindent(8)
                imgui.spacing()
            end
        end
    end)
end
