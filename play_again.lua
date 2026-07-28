mp.add_key_binding("Space", function()
    if mp.get_property_native("eof-reached") then
        mp.command("no-osd seek 0 absolute ; set pause no")
    else
        mp.command("cycle pause")
    end
end)