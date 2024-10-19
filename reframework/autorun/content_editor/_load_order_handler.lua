--- @param udb UserdataDB
return function (udb)
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
            changed, val = imgui.checkbox('Active  ', udb.get_bundle_enabled(bundle.name))
            if changed then
                udb.set_bundle_enabled(bundle.name, val)
            end
            imgui.same_line()
            imgui.text(tostring(idx) .. '. ' .. bundle.name)
            imgui.pop_id()
        end
    end
end