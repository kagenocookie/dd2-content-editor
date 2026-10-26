local core = require('content_editor.core')
local udb = require('content_editor.database')
local utils = require('content_editor.utils')
local helpers = require('content_editor.helpers')
local enums = require('content_editor.enums')
local import_handlers = require('content_editor.import_handlers')

--- @class ItemCombinationEntity : DBEntity
--- @field material app.ItemMixMaterialParam|nil
--- @field mix app.ItemMixParamHolder[]|nil

local itemsEnum = enums.get_enum('app.ItemIDEnum')
local ItemManager = sdk.get_managed_singleton('app.ItemManager') ---@type app.ItemManager

-- potential custom hook additions:
-- - multiple outputs
-- - don't consume materials

udb.events.on('get_existing_data', function (whitelist)
    -- material combination:
    -- used for the Experiment tab of the combine UI
    -- itemId + anyOf(combineRecipe.PairList) => combineRecipe.CombineItem
    -- only one root MateralParam instance is supported by the game

    -- mix combination:
    -- used for "Use recipe" UI tab
    -- anyOf(MaterialA) + anyOf(MaterialB) => itemId
    -- multiple instances supported

    if not whitelist or whitelist.item_combination then
        for item in utils.enumerate(ItemManager.RecipeListTable) do
            local value = item.value
            --- @cast value app.ItemMixMaterialParam
            local id = value._ItemID

            if not whitelist or whitelist.item_combination[id] then
                local e = udb.get_entity('item_combination', id) --[[@as ItemCombinationEntity|nil]]
                if e then
                    e.material = value
                else
                    udb.register_pristine_entity({
                        id = id,
                        type = 'item_combination',
                        material = value,
                    })
                end
            end
        end

        for item in utils.list_iterator(ItemManager.ItemMixParamTable) do
            --- @cast item app.ItemMixParamHolder
            local id = item.Param._ItemId

            if not whitelist or whitelist.item_combination[id] then
                local e = udb.get_entity('item_combination', id) --[[@as ItemCombinationEntity|nil]]
                if e then
                    e.mix = e.mix or {}
                    e.mix[#e.mix+1] = item
                else
                    udb.register_pristine_entity({
                        id = id,
                        type = 'item_combination',
                        mix = {item},
                    })
                end
            end
        end
    end
end)

udb.register_entity_type('item_combination', {
    export = function (entity)
        --- @cast entity ItemCombinationEntity
        return {
            material = import_handlers.export(entity.material, 'app.ItemMixMaterialParam'),
            mix = entity.mix and import_handlers.export_table(entity.mix, 'app.ItemMixParamHolder') or 'null',
        }
    end,
    import = function (import, entity)
        --- @cast entity ItemCombinationEntity

        if not import.material then
            if entity.material then ItemManager.RecipeListTable:Remove(entity.material._ItemID) end
            entity.material = nil
        else
            local prev_mat = entity.material
            entity.material = import_handlers.import('app.ItemMixMaterialParam', import.material, entity.material)
            if not prev_mat then
                ItemManager.RecipeListTable:TryAdd(entity.material._ItemID, entity.material)
            end
        end

        local prev_mix = entity.mix
        entity.mix = utils.map(import.mix or {}, function (value, index)
            local prev = entity.mix and entity.mix[index]
            local newval = import_handlers.import('app.ItemMixParamHolder', value, prev)
            if not prev and newval then
                ItemManager.ItemMixParamTable:Add(newval)
            end
            return newval
        end)
        -- remove any extra entries that are no longer in the table
        if prev_mix then
            for i = #entity.mix + 1, #prev_mix do
                ItemManager.ItemMixParamTable:Remove(prev_mix[i])
            end
        end
    end,
    insert_id_range = {0, 0},
    delete = function (entity)
        return 'not_deletable'
    end,
    generate_label = function (entity)
        --- @cast entity ItemCombinationEntity
        return itemsEnum.get_label(entity.id)
    end,
    root_types = {'app.ItemMixMaterialParam'},
})

if core.editor_enabled then
    local ui = require('content_editor.ui')
    local editor = require('content_editor.editor')

    usercontent.definitions.override('', {
        ['app.ItemMixParam'] = {
            fields = {
                _MaterialA = { extensions = { { type = 'tooltip', text = 'Combination requires any MaterialA + any MaterialB item' } } },
                _MaterialB = { extensions = { { type = 'tooltip', text = 'Combination requires any MaterialA + any MaterialB item' } } },
                _IsNoSame = { extensions = { { type = 'tooltip', text = 'Disallow picking the same item if it\'s present in both material sets' } } },
                _IsAutoMix = { extensions = { { type = 'tooltip', text = 'Possibly used for logistician?' } } },
            }
        },
        ['app.ItemMixMaterialParam.CombineData'] = {
            fields = {
                _PairList = { label = 'Pair items', extensions = { { type = 'tooltip', text = 'Combining with any item from this list will create the combine item' } } },
                _CombineItem = { label = 'Output item' },
                _CombineMakeNum = { label = 'Output count' },
            }
        },
    })

    --- @param obj app.ItemMixParamHolder
    --- @param entity ItemCombinationEntity
    local function mix_onadd(obj, entity)
        local holder = obj or sdk.create_instance('app.ItemMixParamHolder', true)--[[@as app.ItemMixParamHolder]]
        if obj.Param == nil then
            obj.Param = sdk.create_instance('app.ItemMixParam'):add_ref()--[[@as app.ItemMixParam]]
        end

        obj.Param._ItemId = entity.id

        ItemManager.ItemMixParamTable:Add(holder)
    end

    local function mix_onremove(obj)
        ItemManager.ItemMixParamTable:Remove(obj)
    end

    ui.editor.set_entity_editor('item_combination', function (entity, state)
        --- @cast entity ItemCombinationEntity
        local changed

        imgui.text('Experiment combinations')
        ui.basic.tooltip('Used for the Experiment tab in the crafting UI. The selected item + any item in the PairList creates the CombineItem.\nNote that these don\'t automatically work both ways - it only works if _this_ item is selected first.')
        if not entity.material then
            if imgui.button('Add') then
                entity.material = sdk.create_instance('app.ItemMixMaterialParam'):add_ref()--[[@as app.ItemMixMaterialParam]]
                entity.material._ItemID = entity.id
                ItemManager.RecipeListTable:Add(entity.material._ItemID, entity.material)
            end
        end
        if entity.material then
            changed = ui.handlers.show(entity.material._CombineRecipe, entity, nil, 'System.Collections.Generic.List`1<app.ItemMixMaterialParam.CombineData>', state) or changed
        end

        imgui.text('Recipe combinations')
        ui.basic.tooltip('Used for the Use Recipe tab in the crafting UI. The selected item can be created with any combination of items in the two Material sets')
        changed = ui.handlers.show_object_list(entity, 'mix', entity, nil, 'app.ItemMixParamHolder', state, nil, mix_onadd, mix_onremove) or changed
        for _, mix in ipairs(entity.mix or {}) do
            if mix.Param._ItemId ~= entity.id then
                mix.Param._ItemId = entity.id
            end
        end
        return changed
    end)

    editor.define_window('item_combinations', 'Item combinations', function (state)
        if editor.active_bundle then
            imgui.push_id('new')
            imgui.spacing()
            imgui.indent(12)
            imgui.begin_rect()
            imgui.text('Add new combination')
            local sourceItem = ui.editor.entity_picker('item_data', state, nil, 'Source item')
            if sourceItem then
                if udb.get_entity('item_combination', sourceItem.id) then
                    imgui.text_colored('Combination entity already defined for selected item', core.get_color('warning'))
                elseif imgui.button('Add') then
                    local newCombination = udb.create_entity({ id = sourceItem.id, type = 'item_combination' }, editor.active_bundle)
                    ui.editor.set_selected_entity_picker_entity(state, 'item_combination', newCombination)
                end
            end
            imgui.end_rect(4)
            imgui.unindent(12)
            imgui.spacing()
            imgui.pop_id()
        end
        local selected = ui.editor.entity_picker('item_combination', state)
        if selected then
            ui.editor.show_entity_editor(selected, state)
        end
    end)
end
