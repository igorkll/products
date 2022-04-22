local su = require("superUtiles")
local fs = require("filesystem")
local component = require("component")
local event = require("event")
local shell = require("shell")
local serialization = require("serialization")

local args, options = shell.parse(...)

local thisPath = fs.path(su.getPath())
local modem = component.modem
local bootloader = assert(su.getFile(fs.concat(thisPath, "bootloader.lua")))
local port = 42
modem.open(port)

--------------------------------------------

local device

local function simpleCall(address, ...)
    modem.send(address, port, address, "disteeprom:call", ...)
end

local function call(address, ...)
    simpleCall(address, ...)
    local returned = {event.pull(4, "modem_message", modem.address, address, port, nil, "disteeprom:return")}
    if #returned > 0 then
        return table.unpack(returned, 7)
    else
        return false, "no connection"
    end
end

local function call2(address, timeout, ...)
    simpleCall(address, ...)
    local returned = {event.pull(timeout, "modem_message", modem.address, address, port, nil, "disteeprom:return")}
    if #returned > 0 then
        return table.unpack(returned, 7)
    else
        return false, "no connection"
    end
end

--------------------------------------------

local function power(command)
    if command == "on" then
        modem.send(device, port, device .. ":wake")
    elseif command == "off" then
        simpleCall(device, "power:off")
    elseif command == "get" then
        return not not call2(device, 1, "power:get")
    elseif command == "reboot" then
        power("off")
        os.sleep(0.5)
        power("on")
    end
end

local function connect(address)
    --if power("get", address) then
    --    device = address
    --    return true
    --end
    --return nil, "no connection"
    device = address
end

local function flash(code)
    code = bootloader .. "\n" .. code

    local ok, err = call(device, "flash", code)
    if ok then
        print("код успешно прошит")
        return true
    else
        if err == "no connection" then
            print("нет соенденения(таймаут)")
        else
            print("ошибка во время прошивки " .. (err or "unkown"))
        end
    end
end

local function run(code)
    local ok, err = call2(device, 2, "run", code)
    if ok then
        print("код успешно выполнен")
    else
        if err == "no connection" then
            print("нет соенденения(таймаут)")
        else
            print("ошибка во время выполнения" .. (err or "unkown"))
        end
    end
end

--------------------------------------------base

local base
local basepath = fs.concat(thisPath, "config.cfg")

local function loadbase()
    base = assert(serialization.unserialize(assert(su.getFile(basepath))))
end

local function savebase()
    assert(su.saveFile(basepath, assert(serialization.serialize(base))))
end

if fs.exists(basepath) then
    loadbase()
else
    base = {devices = {}}
    savebase()
end

--------------------------------------------main

if #args == 0 then
    print("power control:")
    print("nFlash control registernameOrFulluuid power on")
    print("nFlash control registernameOrFulluuid power off")
    print("nFlash control registernameOrFulluuid power reboot")
    print("nFlash control registernameOrFulluuid power get")
    print("programm control:")
    print("nFlash control registernameOrFulluuid run path")
    print("nFlash control registernameOrFulluuid fastrun code")
    print("nFlash control registernameOrFulluuid flash path")
    print("base:")
    print("nFlash base list")
    print("nFlash base register uuid(если модем устоновлен в компьютер можно сократить uuid(для быстрой регистрации))")
    print("nFlash base remove")
    print("broadcast:")
    print("nFlash broadcast list(список сохраняться в оперативку для регистрации по номеру)")
    print("nFlash broadcast register number registerName(для начала требуеться проиндексировать устройства)")
    print("nFlash broadcast savedList(выводит предыдулий лист без поиска по сети)")
    return
end

if args[1] == "control" then
    local uuid = base.devices[args[2]] or args[2]
    if not uuid then
        io.stderr:write("ошибка второго аргумента")
        return
    end
    if #uuid ~= 36 then
        io.stderr:write("ошибка uuid некоректный")
        return
    end
    connect(uuid)

    if args[3] == "power" then
        if args[4] == "reboot" then
            power("reboot")
        elseif args[4] == "on" then
            power("on")
        elseif args[4] == "off" then
            power("off")
        elseif args[4] == "get" then
            print(power("get"))
        else
            io.stderr:write("ошибка четвертого аргумента")
            return
        end
    elseif args[3] == "run" or args[3] == "flash" or args[3] == "fastrun" then
        local path = args[4]
        if not path then
            io.stderr:write("ошибка четвертого аргумента")
            return
        end

        local code
        if args[3] ~= "fastrun" then
            path = shell.resolve(path)
            if not fs.exists(path) then
                io.stderr:write("файл не найден")
                return
            end
            if fs.isDirectory(path) then
                io.stderr:write("это папка")
                return
            end
            code = su.getFile(path)
        else
            code = path
        end

        local oldPowerState = power("get")
        if not oldPowerState then
            power("on")
            os.sleep(0.5)
        end

        local flashState
        if args[3] == "run" or args[3] == "fastrun" then
            run(code)
        else
            flashState = flash(code)
        end

        if not oldPowerState then
            power("off")
        elseif args[3] == "flash" and flashState then
            power("reboot")
        end
    else
        io.stderr:write("ошибка третиго аргумента")
        return
    end
elseif args[1] == "base" then
    if args[2] == "list" then
        local count = 1
        for k, v in pairs(base.devices) do
            print(tostring(count) .. "." .. tostring(k) .. " > " .. tostring(v))
            count = count + 1
        end
    elseif args[2] == "remove" then
        local num = args[3]
        if not num then
            io.stderr:write("ошибка третиго аргумента")
            return
        end
        if not base.devices[num] then
            io.stderr:write("this name is not register")
            return
        end
        base.devices[num] = nil
        savebase()
    elseif args[2] == "register" then
        local uuid = args[3]
        if #uuid < 3 then
            io.stderr:write("слишком сильное сокрашения нужно минимум 3 символа")
            return
        end
        if #uuid ~= 36 then
            uuid = component.get(uuid)
            if not uuid then
                io.stderr:write("для сокрашенного регистрирования модем должен быть установлен в компьютер")
                io.stderr:write("временно устоновите модем или введите полный uuid")
                return
            end
        end

        local name = args[4]
        if not name then
            io.stderr:write("ошибка четвертого аргумента")
            return
        end

        base.devices[name] = uuid
        savebase()
    else
        io.stderr:write("ошибка второго аргумента")
        return
    end
elseif args[1] == "broadcast" then
    if args[2] == "list" then
        _G.mkList = {}
        _G.mkList2 = {}
        modem.broadcast(port, "disteeprom:list")

        while true do
            local eventName, _, address, _, _, _, dat = event.pull(2, "modem_message", modem.address, nil, port, nil, "disteeprom:dat")
            if not eventName then
                break
            end

            table.insert(_G.mkList, address)
            table.insert(_G.mkList2, dat)
            print(#_G.mkList, dat)
        end
    elseif args[2] == "register" then
        if not _G.mkList or #_G.mkList == 0 then
            io.stderr:write("list not in opetating memory, enter command 'nFlash broadcast list' to index")
            return
        end

        local input = tonumber(args[3])
        if not input then
            io.stderr:write("input error")
            return
        end

        if input < 1 or input > #_G.mkList then
            io.stderr:write("number out size")
            return
        end

        local name = args[4]
        if not name then
            io.stderr:write("ошибка четвертого аргумента")
            return
        end

        base.devices[name] = _G.mkList[input]
        savebase()
    elseif args[2] == "savedList" then
        if not _G.mkList or #_G.mkList == 0 then
            io.stderr:write("list not in opetating memory, enter command 'nFlash broadcast list' to index")
            return
        end
        for i, v in ipairs(_G.mkList2) do
            print(i, v)
        end
    else
        io.stderr:write("ошибка второго аргумента")
        return
    end
else
    io.stderr:write("ошибка первого аргумента")
    return
end