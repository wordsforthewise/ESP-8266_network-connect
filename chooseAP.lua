-- had to chunk up sending of webpage, to deal with low amounts of memory on ESP-8266 devices
-- surely a more elegant way to do it
local SSID = nil
local pass = nil
local otherSSID = nil
local errMsg = nil
local savedNetwork = false
local SSIDs = {}
local resetTimer = 15 -- for resetting the module after successfully connecting to chosen network
-- lookup table for wifi.sta.status()
local statusTable = {}
-- statusTable[0] = "neither connected nor connecting"
-- statusTable[1] = "still connecting"
statusTable["2"] = "wrong password"
statusTable["3"] = "didn\'t find the network you specified"
statusTable["4"] = "failed to connect"
-- statusTable[5] = "successfully connected"
wifi.sta.disconnect()
wifi.setmode(wifi.STATIONAP)
print('wifi status: '..wifi.sta.status())

-- opens saved list of nearby networks and puts into SSIDs table
file.open('networkList','r')
local counter = 0
local line = ""
while true do
    line = file.readline()
    if line == nil then break end
    counter = counter + 1
    SSIDs[counter] = line
end

local cfg = {}
cfg.ssid = "mysticalNetwork"
cfg.pwd = "mystical5000"
wifi.ap.config(cfg)
local srv=net.createServer(net.TCP, 300)
print('connect to \''..cfg.ssid..'\', password \''..cfg.pwd..'\', ip '..wifi.ap.getip())
cfg = nil
srv:listen(80,function(conn)
conn:on("receive", function(client,request)
    print("recieve")
    local errMsg = nil
    local _, _, delete = string.find(request, "(deleteSaved=true)")
    if (delete~=nil) then
        file.remove('networks')
        errMsg = "<center><h2>Saved networks deleted.<\h2><\center>"
    end
    -- check if SSID and password have been submitted
    local connecting = false
    local _, _, SSID, pass = string.find(request, "SSID=(.+)%%0D%%0A&otherSSID=&password=(.*)")
    print(node.heap())

    if (pass~=nil and pass~="") then
        if (string.len(pass)<8) then
            local pass = nil
            errMsg = "<center><h2 style=\"color:red\">Whoops! Password must be at least 8 characters.<\h2><\center>"
        end
    end
    
    if (SSID==nil) then
        _, _, SSID, pass = string.find(request, "SSID=&otherSSID=(.+)%%0D%%0A&password=(.*)")
    end

    print(request)
    local buf = "";

    -- if password for network is nothing, any password should work
    if (SSID~=nil and pass~=nil) then
        if (pass == "") then
            pass = "aaaaaaaa"
        end
        print(SSID..', '..pass)
        -- TO-DO: add timout for connection attempt
        local connectStatus = wifi.sta.status()
        print(connectStatus)
        sendHeader(client)
        tmr.alarm(5,500,0,function()
            buf = buf.."<center><h2 style=\"color:DarkGreen\">Connecting to "..tostring(SSID)
            buf = buf.."!</h2><br><h2>Please hold tight, we'll be back to you shortly.</h2></center></div></html>"
            client:send(buf)
            buf = ""
        end)
        tmr.alarm(1,1000,1, function()
            tmr.alarm(4,1000,0,function()
                wifi.sta.config(tostring(SSID),tostring(pass))
                wifi.sta.connect()
                connecting = true
            end)
            connectStatus = wifi.sta.status()
            print("connecting")
            if (connectStatus ~= 1) then
                if (connectStatus == 5) then
                    print("connected!")
                    sendHeader(client)
                    buf = buf.."<center><h2 style=\"color:DarkGreen\">Successfully connected to "..tostring(SSID).."!"
                    buf = buf.."</h2><br><h2>Added to network list.</h2><br><h2>Resetting module in "..resetTimer.."s...</h1></center></div></html>"
                    client:send(buf)
                    buf = ""
                    file.open("networks","a+")
                    file.writeline(tostring(SSID))
                    file.writeline(tostring(pass))
                    file.close()
                    savedNetwork = true
                    tmr.alarm(2,resetTimer*1000,0,function()
                        srv:close()
                        node.restart()
                        end)
                else
                    print("couldn't connect")
                    sendHeader(client)
                    buf = buf.."<center><h2 style=\"color:red\">Whoops! Could not connect to "..tostring(SSID)..". "..statusTable[tostring(connectStatus)].."</h2><br></center>"
                    client:send(buf)
                    buf = ""
                    sendForm(client, errMsg)
                end
                client:send(buf)
                collectgarbage()
                tmr.stop(1)
                client:close()
            end
        end)
    end
    buf = ""
    if(not connecting) then
        sendHeader(client)
        sendForm(client, errMsg)
        client:send(buf)
        buf = ""
        client:close()
    end
    collectgarbage()
end)
end)

function sendHeader(client)
    -- write header to client
    buf = ""
    buf = buf.."<!DOCTYPE html><html><head><style>h2{font-size:500%; font-family:helvetica} "
    buf = buf.."p{font-size:200%; font-family:helvetica}</style>"
    buf = buf.."</head><div style = \"width:80%; margin: 0 auto\">"
    client:send(buf)
end

function sendForm(client, errMsg)
    buf = ""
    -- send top of form to client
    buf = buf.."<center><h1>Choose a network to join:</h1></center>"
    buf = buf.."<form align=\"left\" method=\"POST\" autocomplete=\"off\">"
    buf = buf.."<p><u><b>1. Choose network:</u></b><br>"
    client:send(buf)
    buf = ""
    -- send network names one at a time; if there are lots of networks the ESP can run out of memory
    for i,network in pairs(SSIDs) do
        netSubSpaces, _ = string.gsub(network, " ", "%%20")
        buf = "<input type=\"radio\" name=\"SSID\" value=\""..netSubSpaces.."\">"..network.."<br>"
        client:send(buf)
        buf = ""
    end
    buf = buf.."other: <input type=\"text\" name=\"otherSSID\"><br><br>"
    buf = buf.."<u><b>2. Enter password (or blank for none):</u></b><br><input type=\"text\" name=\"password\"><br><br>"
    buf = buf.."<input style=\"font-size:30pt\" type=\"submit\" value=\"Submit\">"
    buf = buf.."</p></form>"
    client:send(buf)
    buf = ""
    -- add warning about password<8 characters if needed
    if (errMsg~=nil) then
        buf = buf.."<br><br>"..errMsg
        client:send(buf)
    end
    buf = buf.."<br><br><br><form align=\"center\" method=\"POST\">"
    buf = buf.."<input type=\"hidden\" name=\"deleteSaved\" value=\"true\">"
    buf = buf.."<input type=\"submit\" value=\"Delete all saved networks\" style=\"font-size:30pt; color:red\"></form></html></div>"
    client:send(buf)
    buf = ""
end
