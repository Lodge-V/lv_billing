local ESX = exports['es_extended']:getSharedObject()
local uiOpen = false

-------------------------------------------------------
-- NUI öffnen / schließen
-------------------------------------------------------

local function openUI()
    if uiOpen then return end
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open' })
    TriggerEvent('esx_rechnungen:requestData')
end

local function closeUI()
    if not uiOpen then return end
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterCommand(Config.Command, function()
    openUI()
end, false)

RegisterKeyMapping(Config.Command, 'Rechnungen öffnen', 'keyboard', Config.Key)

-------------------------------------------------------
-- Daten für NUI laden
-------------------------------------------------------

RegisterNetEvent('esx_rechnungen:requestData', function()
    ESX.TriggerServerCallback('esx_rechnungen:getInvoices', function(data)
        SendNUIMessage({ action = 'setInvoices', data = data })
    end)

    ESX.TriggerServerCallback('esx_rechnungen:getPlayers', function(players)
        SendNUIMessage({ action = 'setPlayers', data = players })
    end)

    ESX.TriggerServerCallback('esx_rechnungen:getContext', function(context)
        SendNUIMessage({ action = 'setContext', data = context })
    end)
end)

RegisterNetEvent('esx_rechnungen:refresh', function()
    if uiOpen then
        TriggerEvent('esx_rechnungen:requestData')
    end
end)

-------------------------------------------------------
-- Benachrichtigungen
-------------------------------------------------------

RegisterNetEvent('esx_rechnungen:notify', function(message, type)
    if ESX.ShowNotification then
        ESX.ShowNotification(message)
    else
        TriggerEvent('chat:addMessage', { args = { 'Rechnungen', message } })
    end
end)

-------------------------------------------------------
-- NUI Callbacks
-------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    closeUI()
    cb('ok')
end)

RegisterNUICallback('payInvoice', function(data, cb)
    TriggerServerEvent('esx_rechnungen:payInvoice', data.id)
    cb('ok')
end)

RegisterNUICallback('payInstallment', function(data, cb)
    TriggerServerEvent('esx_rechnungen:payInstallment', data.id)
    cb('ok')
end)

RegisterNUICallback('payAllInvoices', function(_, cb)
    TriggerServerEvent('esx_rechnungen:payAllInvoices')
    cb('ok')
end)

RegisterNUICallback('payByReference', function(data, cb)
    TriggerServerEvent('esx_rechnungen:payByReference', data.refId)
    cb('ok')
end)

RegisterNUICallback('sendInvoice', function(data, cb)
    TriggerServerEvent('esx_rechnungen:sendInvoice', tonumber(data.targetId), data.items, data.society, data.notes, tonumber(data.installmentParts))
    cb('ok')
end)

RegisterNUICallback('sendGroupInvoice', function(data, cb)
    local ids = {}
    for _, id in ipairs(data.targetIds or {}) do
        ids[#ids + 1] = tonumber(id)
    end
    TriggerServerEvent('esx_rechnungen:sendGroupInvoice', ids, tonumber(data.amount), data.item, data.notes)
    cb('ok')
end)

RegisterNUICallback('cancelInvoice', function(data, cb)
    TriggerServerEvent('esx_rechnungen:cancelInvoice', data.id)
    cb('ok')
end)

RegisterNUICallback('inspectPlayer', function(data, cb)
    ESX.TriggerServerCallback('esx_rechnungen:inspectPlayer', function(result)
        cb(result)
    end, tonumber(data.targetId))
end)

RegisterNUICallback('getCityInvoices', function(_, cb)
    ESX.TriggerServerCallback('esx_rechnungen:getCityInvoices', function(result)
        cb(result)
    end)
end)

RegisterNUICallback('getInvoiceDetail', function(data, cb)
    ESX.TriggerServerCallback('esx_rechnungen:getInvoiceDetail', function(result)
        cb(result)
    end, tonumber(data.id))
end)

RegisterNUICallback('getSocietyLeaderboard', function(_, cb)
    ESX.TriggerServerCallback('esx_rechnungen:getSocietyLeaderboard', function(result)
        cb(result)
    end)
end)

RegisterNUICallback('refreshData', function(_, cb)
    TriggerEvent('esx_rechnungen:requestData')
    cb('ok')
end)

-------------------------------------------------------
-- ESC schließt NUI
-------------------------------------------------------

CreateThread(function()
    while true do
        Wait(0)
        if uiOpen then
            if IsControlJustPressed(0, 322) then
                closeUI()
            end
        else
            Wait(500)
        end
    end
end)
