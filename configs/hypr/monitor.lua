if HostName == "lumi" then
    hl.monitor({
        output = "eDP-1",
        mode = "1920x1080@60",
        position = "0x0",
        scale = "1",
    })
elseif HostName == "khion" then
    hl.monitor({
        output = "DP-1",
        mode = "2560x1440@180",
        position = "0x0",
        scale = "1",
    })
    hl.monitor({
        output = "DP-2",
        mode = "2560x1440@180",
        position = "2560x0",
        scale = "1",
    })
end
