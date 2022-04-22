do
    function getCP(ctype) return component.proxy(component.list(ctype)()) end
    modem = getCP("modem")
    modem.setWakeMessage(modem.address .. ":wake")
    eeprom = getCP("eeprom")
  
    local component, computer = component, computer

    --------------------------------------------

    local port = 42
    modem.open(port)

    function getDeviceType()
        local function func(ctype) --и так понятно че она делает
            local _, lctype = component.list(ctype)()
            return lctype
        end
        return func("robot") or func("tablet") or func("drone") or func("microcontroller") or func("computer")
    end

    function delay(time, func)
        if not func then
            func = function()
                computer.pullSignal(0.1)
            end
        end
        local inTime = computer.uptime()
        while computer.uptime() - inTime < time do
            func()
        end
    end
    
    local computer_pullSignal = computer.pullSignal
    function computer.pullSignal(time)
        local eventData = {computer_pullSignal(time)}

        local function returnData(address, ...)
            modem.send(address, port, "disteeprom:return", ...)
        end

        if eventData[1] == "modem_message" and eventData[2] == modem.address and eventData[4] == port then
            if eventData[6] == modem.address and eventData[7] == "disteeprom:call" then
                if eventData[8] == "power:off" then
                    computer.shutdown()
                elseif eventData[8] == "flash" then
                    local ok, err = load(eventData[9])
                    if ok then
                        eeprom.set(eventData[9])
                        returnData(eventData[3], true)
                    else
                        returnData(eventData[3], false, err)
                    end
                elseif eventData[8] == "run" then
                    local code, err = load(eventData[9])
                    if code then
                        local ok, err = pcall(code)
                        if not ok then
                            returnData(eventData[3], false, err)
                        else
                            returnData(eventData[3], true)
                        end
                    else
                        returnData(eventData[3], false, err)
                    end
                elseif eventData[8] == "power:get" then
                    returnData(eventData[3], true)
                end
            elseif eventData[6] == "disteeprom:list" then
                modem.send(eventData[3], port, "disteeprom:dat", "modem address: " .. modem.address .. ", computer type:" .. getDeviceType())
            end
        end
        return table.unpack(eventData)
    end

    delay(4)
end