local core = require('content_editor.core')
local ItemManager = sdk.get_managed_singleton('app.ItemManager')

--- @class ItemShopData : DBEntity
--- @field runtime_instance REManagedObject|table

local udb = require('content_editor.database')
local import_handlers = require('content_editor.import_handlers')

-- fetch current game data
udb.events.on('get_existing_data', function ()
    local dataRoot = ItemManager.ItemShopData ---@type REManagedObject|table
    for _, shop in ipairs(dataRoot._Params:get_elements()) do
        --- @type DBEntity
        local entity = {
            id = shop._ShopId,
            type = 'shop',
            runtime_instance = shop,
        }

        udb.register_pristine_entity(entity)
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
        instance = instance or {}
        instance.runtime_instance = import_handlers.import('app.ItemShopParam', data.data, instance)
        return instance
    end,
    delete = function (instance)
        --- @cast instance ItemShopData
        -- don't delete, also don't create new shops since we have no use for new ones until we can actually put them somewhere
        -- ItemManager.ItemShopData = helpers.system_array_remove(ItemManager.ItemShopData, instance.runtime_instance, 'app.ItemShopParam')
        return 'forget'
    end,
    generate_label = function (entity)
        --- @cast entity ItemShopData
        return 'Shop ' .. entity.id .. ': ' .. entity.runtime_instance:get_ShopName()
    end,
    insert_id_range = {1000, 999000},
    root_types = {'app.ItemShopParam'},
})

if core.editor_enabled then
    local enums = require('content_editor.enums')

    local editor = require('content_editor.editor')
    local ui = require('content_editor.ui')

    local definitions = require('content_editor.definitions')

    editor.define_window('shop', 'Shops', function (state)
        local selectedShop = ui.editor.entity_picker('shop', state)
        if selectedShop then
            --- @cast selectedShop ItemShopData
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            ui.editor.show_entity_metadata(selectedShop)
            ui.handlers.show_editable(selectedShop, 'runtime_instance', selectedShop, nil, 'app.ItemShopParam')
            imgui.end_rect(4)
            imgui.unindent(8)
        end
    end)

    editor.add_editor_tab('shop')

    definitions.override('', {
        ['app.ItemShopBuyParam'] = {
            fields = {
                _ItemId = { uiHandler = ui.handlers.common.enum(enums.get_enum('app.ItemIDEnum')) }
            },
            toString = function (value) return 'Buy ' .. enums.get_enum('app.ItemIDEnum').get_label(value._ItemId) end
        },
        ['app.ItemShopSellParam'] = {
            fields = {
                _ItemId = { uiHandler = ui.handlers.common.enum(enums.get_enum('app.ItemIDEnum')) }
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
