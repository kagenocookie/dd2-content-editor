local core = require('content_editor.core')

--- @class ItemShopData : DBEntity
--- @field runtime_instance REManagedObject|table

--- @class PartialEntityData : EntityImportData
--- @field parent_id integer
--- @field parent_type string

--- @class PartialArrayEntity : DBEntity
--- @field parent_id integer
--- @field items app.ItemShopBuyParam[]|app.ItemShopSellParam[]

local udb = require('content_editor.database')
local import_handlers = require('content_editor.import_handlers')
local helpers = require('content_editor.helpers')
local utils = require('content_editor.utils')
local enums = require('content_editor.enums')

local ItemManager = sdk.get_managed_singleton('app.ItemManager') ---@type app.ItemManager

-- fetch current game data
udb.events.on('get_existing_data', function (whitelist)
    if whitelist and not whitelist.shop then return end
    local dataRoot = ItemManager.ItemShopData
    for _, shop in ipairs(dataRoot._Params:get_elements()) do
        --- @cast shop app.ItemShopParam
        if not whitelist or whitelist.shop[shop._ShopId] then
            --- @type DBEntity
            local entity = {
                id = shop._ShopId,
                type = 'shop',
                runtime_instance = shop,
            }

            udb.register_pristine_entity(entity)
        end
    end
end)

udb.events.on('entities_created', function (data)
    if data.shop and #data.shop > 0 then
        ItemManager.ItemShopData._Params = helpers.expand_system_array(
            ItemManager.ItemShopData._Params,
            utils.pluck(data.shop, 'runtime_instance'),
            'app.ItemShopParam'
        )
    end
end)

udb.register_entity_type('shop', {
    export = function (instance)
        --- @cast instance ItemShopData
        return {
            data = import_handlers.export(instance.runtime_instance, 'app.ItemShopParam')
        }
    end,
    import = function (data, instance)
        --- @cast instance ItemShopData
        instance.runtime_instance = import_handlers.import('app.ItemShopParam', data.data, instance.runtime_instance)
    end,
    delete = function (instance)
        --- @cast instance ItemShopData
        -- don't delete, also don't create new shops since we have no use for new ones until we can actually put them somewhere
        -- ItemManager.ItemShopData = helpers.system_array_remove(ItemManager.ItemShopData, instance.runtime_instance, 'app.ItemShopParam')
        return 'not_deletable'
    end,
    generate_label = function (entity)
        --- @cast entity ItemShopData
        local displ = enums.get_enum('ShopNameOverrides').get_label(entity.id)
        if displ ~= tostring(entity.id) then
            return displ
        end
        return 'Shop ' .. entity.id .. ': ' .. entity.runtime_instance:get_ShopName()
    end,
    insert_id_range = {1000, 65000, 1},
    root_types = {'app.ItemShopParam'},
})

--- @param parent_entity string
--- @param partial_type_name string
--- @param element_classname string
--- @param comparer fun(item1: table, item2: REManagedObject): boolean
--- @param array_getter fun(parentId: integer): SystemArray
--- @param array_setter fun(parentId: integer, newArray: SystemArray)
local function register_partial_entity_array(parent_entity, partial_type_name, element_classname, comparer, array_getter, array_setter)
    udb.register_entity_type(partial_type_name, {
        export = function (instance)
            --- @cast instance PartialArrayEntity
            -- - @type PartialEntityData
            return {
                _is_partial = true,
                parent_type = parent_entity,
                parent_id = instance.parent_id,
                data = import_handlers.export_table(instance.items, element_classname)
            }
        end,
        import = function (data, instance)
            --- @cast instance PartialArrayEntity
            --- @cast data PartialEntityData
            instance.parent_id = data.parent_id
            local importedItems = {}
            local arr = array_getter(data.parent_id)
            if not arr then
                re.msg('error in partial entity ' .. partial_type_name .. ' - array was not found for ID ' .. tostring(instance.parent_id))
                instance.items = {}
                return
            end
            local unimportedItems = utils.table_values(data.data or {})
            for _, existingItem in pairs(arr) do
                for i, newItem in ipairs(unimportedItems) do
                    if comparer(newItem, existingItem) then
                        importedItems[#importedItems+1] = import_handlers.import(element_classname, newItem, existingItem)
                        table.remove(unimportedItems, i)
                        break
                    end
                end
            end

            local newItems = {}
            for _, item in ipairs(unimportedItems) do
                local newItem = import_handlers.import(element_classname, item)
                newItems[#newItems+1] = newItem
                importedItems[#importedItems+1] = newItem
            end
            if #newItems > 0 then
                array_setter(data.parent_id, helpers.expand_system_array(arr, newItems, element_classname))
            end

            instance.items = importedItems
        end,
        delete = function (instance)
            --- @cast instance PartialArrayEntity
            local arr = array_getter(instance.parent_id)
            if not arr then
                re.msg('error in partial entity ' .. partial_type_name .. ' - data array was not found for ID ' .. tostring(instance.parent_id))
                return 'not_deletable'
            end
            local newarr = arr
            for _, item in ipairs(instance.items) do
                newarr = helpers.system_array_remove(newarr, item, element_classname)
            end
            if arr ~= newarr then array_setter(instance.parent_id, newarr) end
            return 'ok'
        end,
        root_types = {},
        insert_id_range = {10, 999000, 1}
    })
end

register_partial_entity_array('shop', 'shop_buy', 'app.ItemShopBuyParam',
    function (item1, item2) --[[@cast item2 app.ItemShopBuyParam]]
        return item1._ItemId == item2._ItemId and item1._Stock == item2._Stock and item1._ReleaseQuestId == item2._ReleaseQuestId
    end,
    function (parentId) local shop = ItemManager:getItemShopData(parentId) return shop and shop._BuyParams end,
    function (parentId, array) ItemManager:getItemShopData(parentId)._BuyParams = array end
)

register_partial_entity_array('shop', 'shop_sell', 'app.ItemShopSellParam',
    function (item1, item2) --[[@cast item2 app.ItemShopSellParam]]
        return item1._ItemId == item2._ItemId
    end,
    function (parentId) local shop = ItemManager:getItemShopData(parentId) return shop and shop._SellParams end,
    function (parentId, array) ItemManager:getItemShopData(parentId)._SellParams = array end
)

if core.editor_enabled then
    local editor = require('content_editor.editor')
    local ui = require('content_editor.ui')

    local definitions = require('content_editor.definitions')

    ui.editor.set_entity_editor('shop', function (entity, state)
        return ui.handlers.show_editable(entity, 'runtime_instance', entity, nil, 'app.ItemShopParam')
    end)

    editor.define_window('shop', 'Shops', function (state)
        local selectedShop = ui.editor.entity_picker('shop', state)
        if selectedShop then
            --- @cast selectedShop ItemShopData
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            state.subtype = select(2, ui.basic.tabs({'Buy lists', 'Sell lists', 'Base shop data'}, state.subtype or 1))
            imgui.push_id(state.subtype or 0)
            if state.subtype == 3 then
                imgui.text_colored('The base shop data view is intended for modifying the basic data or eventually adding new shops, as it fully replaces all data.\nIf you wish to only add items to an existing shop, consider using the buy lists and sell lists views instead.\nThat way multiple mods can add items to the same shop', core.get_color('disabled'))
                imgui.spacing()
                ui.editor.show_entity_metadata(selectedShop)
                ui.handlers.show_editable(selectedShop, 'runtime_instance', selectedShop, nil, 'app.ItemShopParam')
            elseif state.subtype == 1 then
                local subtype = ui.editor.entity_picker('shop_buy', state, nil, 'Buy list', function (e) return e.parent_id == selectedShop.id end) --[[@as PartialArrayEntity|nil]]
                if editor.active_bundle and imgui.button('New buy list') then
                    subtype = udb.insert_new_entity('shop_buy', editor.active_bundle, { parent_id = selectedShop.id, parent_type = 'shop', data = {} }) --[[@as PartialArrayEntity|nil]]
                    ui.editor.set_selected_entity_picker_entity(state, 'shop_buy', subtype)
                end
                if subtype and subtype.parent_id == selectedShop.id then
                    ui.editor.show_entity_metadata(subtype)
                    imgui.text('Items: ' .. #subtype.items)
                    for idx, item in ipairs(subtype.items) do
                        imgui.push_id(idx)
                        if imgui.button('X') then
                            table.remove(subtype.items, idx)
                            local shop = ItemManager:getItemShopData(subtype.parent_id)
                            if shop then
                                shop._BuyParams = helpers.system_array_remove(shop._BuyParams, item, 'app.ItemShopBuyParam')
                            end
                            udb.mark_entity_dirty(subtype)
                        end
                        imgui.pop_id()
                        imgui.same_line()
                        ui.handlers.show(item, subtype, tostring(idx), nil)
                    end
                    if imgui.button('Add') then
                        subtype.items[#subtype.items+1] = sdk.create_instance('app.ItemShopBuyParam'):add_ref()--[[@as app.ItemShopBuyParam]]
                        udb.reimport_entity(subtype)
                        udb.mark_entity_dirty(subtype)
                    end
                end
            elseif state.subtype == 2 then
                local subtype = ui.editor.entity_picker('shop_sell', state, nil, 'Sell list', function (e) return e.parent_id == selectedShop.id end) --[[@as PartialArrayEntity|nil]]
                if editor.active_bundle and imgui.button('New sell list') then
                    subtype = udb.insert_new_entity('shop_sell', editor.active_bundle, { parent_id = selectedShop.id, parent_type = 'shop', data = {} }) --[[@as PartialArrayEntity|nil]]
                    ui.editor.set_selected_entity_picker_entity(state, 'shop_sell', subtype)
                end
                if subtype and subtype.parent_id == selectedShop.id then
                    ui.editor.show_entity_metadata(subtype)
                    imgui.text('Items: ' .. #subtype.items)
                    for idx, item in ipairs(subtype.items) do
                        imgui.push_id(idx)
                        if imgui.button('X') then
                            table.remove(subtype.items, idx)
                            local shop = ItemManager:getItemShopData(subtype.parent_id)
                            if shop then
                                shop._SellParams = helpers.system_array_remove(shop._SellParams, item, 'app.ItemShopSellParam')
                            end
                            udb.mark_entity_dirty(subtype)
                        end
                        imgui.pop_id()
                        imgui.same_line()
                        ui.handlers.show(item, subtype, tostring(idx), nil)
                    end
                    if imgui.button('Add') then
                        subtype.items[#subtype.items+1] = sdk.create_instance('app.ItemShopSellParam'):add_ref()--[[@as app.ItemShopSellParam]]
                        udb.reimport_entity(subtype)
                        udb.mark_entity_dirty(subtype)
                    end
                end
            end
            imgui.pop_id()
            imgui.end_rect(4)
            imgui.unindent(8)
        end
    end)

    editor.add_editor_tab('shop')

    definitions.override('', {
        ['app.ItemShopBuyParam'] = {
            fieldOrder = {'_ItemId', '_Stock'},
            fields = {
                _ItemId = { uiHandler = ui.handlers.common.enum('app.ItemIDEnum') }
            },
            toString = function (value) return 'Buy ' .. enums.get_enum('app.ItemIDEnum').get_label(value._ItemId) end
        },
        ['app.ItemShopSellParam'] = {
            fieldOrder = {'_ItemId'},
            fields = {
                _ItemId = { uiHandler = ui.handlers.common.enum('app.ItemIDEnum') }
            },
            toString = function (value) return 'Sell ' .. enums.get_enum('app.ItemIDEnum').get_label(value._ItemId) end
        },
        ['app.ItemShopParam'] = {
            fields = {
                _ShopNameId = { extensions = { { type = 'translate_guid' } } },
            },
        },
    })
end
