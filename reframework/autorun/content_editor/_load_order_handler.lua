--- @param udb UserdataDB
return function (udb)
    if type(_userdata_DB) == "nil" then _userdata_DB = {} end

    return function ()
        for idx, bundle in ipairs(udb.bundles_order_list) do
            imgui.push_id(bundle.name)
            -- TODO reorder should check if any entities are touched by both the reoredered bundles,
            -- if so, either mark needs_full_restart as true or properly handle reloading
            if imgui.button('^') and idx ~= 1 then
                udb.swap_bundle_load_order(udb.bundles_order_list[idx].name, udb.bundles_order_list[idx - 1].name)
                break
            end
            imgui.same_line()
            if imgui.button('v') and idx ~= #udb.bundles_order_list then
                udb.swap_bundle_load_order(udb.bundles_order_list[idx].name, udb.bundles_order_list[idx + 1].name)
                break
            end
            imgui.same_line()
            if imgui.button('?') then
                if _userdata_DB._loadOrderWindow == bundle.name then
                    _userdata_DB._loadOrderWindow = nil
                else
                    _userdata_DB._loadOrderWindow = bundle.name
                end
            end
            if imgui.is_item_hovered() then
                imgui.set_tooltip('Author: ' .. (bundle.author or '<unknown>'))
            end
            imgui.same_line()
            changed, val = imgui.checkbox('Active  ', udb.get_bundle_enabled(bundle.name))
            if changed then
                udb.set_bundle_enabled(bundle.name, val)
            end
            imgui.same_line()
            imgui.text(tostring(idx) .. '. ' .. bundle.name)
            if _userdata_DB._loadOrderWindow == bundle.name then
                imgui.input_text_multiline('Description', bundle.description, 10)
            end
            imgui.pop_id()
        end
    end
end