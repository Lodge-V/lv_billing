local ESX = exports['es_extended']:getSharedObject()

-------------------------------------------------------
-- Hilfsfunktionen
-------------------------------------------------------

local function GetPlayerName(xPlayer)
    if not xPlayer then return 'Unbekannt' end
    return ('%s %s'):format(xPlayer.get('firstName') or xPlayer.getName(), xPlayer.get('lastName') or '')
end

local function GenerateRefId(cb)
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    local function make()
        local id = ''
        for _ = 1, 6 do
            local idx = math.random(1, #chars)
            id = id .. chars:sub(idx, idx)
        end
        return id
    end

    local function attempt()
        local id = make()
        MySQL.scalar('SELECT id FROM esx_invoices WHERE ref_id = ?', { id }, function(exists)
            if exists then
                attempt()
            else
                cb(id)
            end
        end)
    end

    attempt()
end

local function GenerateGroupId()
    local chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
    local id = ''
    for _ = 1, 12 do
        local idx = math.random(1, #chars)
        id = id .. chars:sub(idx, idx)
    end
    return 'grp_' .. id
end

local function DiscordLog(title, description, color)
    if not Config.DiscordLogs.enabled or Config.DiscordLogs.webhook == '' then return end

    PerformHttpRequest(Config.DiscordLogs.webhook, function() end, 'POST', json.encode({
        embeds = {
            {
                title = title,
                description = description,
                color = color or Config.DiscordLogs.color,
                footer = { text = os.date('%d.%m.%Y %H:%M:%S') }
            }
        }
    }), { ['Content-Type'] = 'application/json' })
end

local function HasJobAccess(xPlayer, jobList)
    if not xPlayer then return false end
    local job = xPlayer.job and xPlayer.job.name
    if not job then return false end
    for _, j in ipairs(jobList) do
        if j == job then return true end
    end
    return false
end

local function FormatDate(ts)
    return os.date('%Y-%m-%d %H:%M:%S', ts)
end

local function CanManage(source, xPlayer)
    return HasJobAccess(xPlayer, Config.ManageJobs) or IsPlayerAceAllowed(source, Config.ManageAcePermission)
end

-------------------------------------------------------
-- Geld einem Spieler gutschreiben (online oder offline)
-------------------------------------------------------

local function CreditPlayer(identifier, amount)
    if amount <= 0 then return end
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    if xPlayer then
        xPlayer.addAccountMoney('bank', amount)
    else
        MySQL.update('UPDATE users SET accounts = JSON_SET(accounts, "$.bank", JSON_EXTRACT(accounts, "$.bank") + ?) WHERE identifier = ?',
            { amount, identifier })
    end
end

-------------------------------------------------------
-- Anteile (Society/Provision/Versicherung) für einen (Teil-)Betrag berechnen
-- ratio = Anteil dieser Zahlung am Gesamtwert der Rechnung (1.0 = komplette Rechnung)
-------------------------------------------------------

local function ComputeShares(invoice, ratio)
    local commission = math.floor((invoice.commission_amount or 0) * ratio)
    local fee = math.floor((invoice.fee_amount or 0) * ratio)
    local insurance = math.floor((invoice.insurance_covered or 0) * ratio)
    local originalPortion = math.floor((invoice.original_value or invoice.invoice_value) * ratio)
    local society = originalPortion - commission - fee
    if society < 0 then society = 0 end
    return { commission = commission, fee = fee, insurance = insurance, society = society }
end

local function DistributeShares(invoice, shares)
    if invoice.society and invoice.society ~= '' then
        if shares.society > 0 then
            Config.DepositToSociety(invoice.society, shares.society)
        end
        if shares.insurance > 0 then
            Config.WithdrawFromInsurance(shares.insurance, invoice.society)
        end
        if shares.commission > 0 then
            CreditPlayer(invoice.author_identifier, shares.commission)
            local xAuthor = ESX.GetPlayerFromIdentifier(invoice.author_identifier)
            if xAuthor then
                Config.Notify(xAuthor.source, ('Du hast %d$ Provision für Rechnung [%s] erhalten.'):format(shares.commission, invoice.ref_id), 'success')
            end
        end
    else
        -- Persönliche Rechnung: gesamter gezahlter Betrag geht an den Aussteller
        local xAuthor = ESX.GetPlayerFromIdentifier(invoice.author_identifier)
        local totalPersonal = shares.society + shares.commission -- bei persönlichen Rechnungen ist fee/commission = 0, society = voller Betrag
        CreditPlayer(invoice.author_identifier, totalPersonal)
        if xAuthor then
            Config.Notify(xAuthor.source, ('%s hat deine Rechnung [%s] bezahlt.'):format(invoice.receiver_name, invoice.ref_id), 'success')
            TriggerClientEvent('esx_rechnungen:refresh', xAuthor.source)
        end
    end
end

-------------------------------------------------------
-- Rechnung senden (persönlich oder Society), mit mehreren Positionen
-- und optionaler Ratenzahlung
-- items = { { label = '...', price = 100 }, ... }
-------------------------------------------------------

RegisterNetEvent('esx_rechnungen:sendInvoice', function(targetServerId, items, society, notes, installmentParts)
    local src = source
    local xSender = ESX.GetPlayerFromId(src)
    local xTarget = ESX.GetPlayerFromId(targetServerId)

    if not xSender then return end

    if not xTarget then
        Config.Notify(src, 'Spieler nicht gefunden oder offline.', 'error')
        return
    end

    if xTarget.source == xSender.source then
        Config.Notify(src, 'Du kannst dir selbst keine Rechnung ausstellen.', 'error')
        return
    end

    if type(items) ~= 'table' or #items == 0 then
        Config.Notify(src, 'Bitte mindestens eine Position angeben.', 'error')
        return
    end

    local cleanItems = {}
    local amount = 0

    for _, it in ipairs(items) do
        local label = it.label and tostring(it.label):sub(1, 150) or 'Position'
        local price = tonumber(it.price)
        if price and price > 0 then
            price = math.floor(price)
            amount = amount + price
            cleanItems[#cleanItems + 1] = { label = label, price = price }
        end
    end

    if amount <= 0 or #cleanItems == 0 then
        Config.Notify(src, 'Ungültiger Gesamtbetrag.', 'error')
        return
    end

    local societyConfig = nil
    local societyLabel = nil

    if society and society ~= '' then
        societyConfig = Config.Societies[society]
        if not societyConfig then
            Config.Notify(src, 'Ungültige Gesellschaft.', 'error')
            return
        end
        if not HasJobAccess(xSender, { society }) then
            Config.Notify(src, 'Du gehörst dieser Gesellschaft nicht an.', 'error')
            return
        end
        societyLabel = societyConfig.label
    else
        if not Config.AllowPersonalInvoices then
            Config.Notify(src, 'Persönliche Rechnungen sind deaktiviert.', 'error')
            return
        end
        if amount < Config.MinAmount or amount > Config.MaxAmount then
            Config.Notify(src, ('Betrag muss zwischen %d und %d liegen.'):format(Config.MinAmount, Config.MaxAmount), 'error')
            return
        end
    end

    notes = notes and tostring(notes):sub(1, 255) or ''

    -- Zusammenfassungs-Label für die Listenansicht
    local itemSummary = cleanItems[1].label
    if #cleanItems > 1 then
        itemSummary = itemSummary .. (' + %d weitere'):format(#cleanItems - 1)
    end

    local feeAmount = 0
    local commissionAmount = 0
    local originalValue = amount
    local insuranceCovered = 0
    local payableAmount = amount

    if societyConfig then
        feeAmount = math.floor(amount * (societyConfig.feePercent or 0) / 100)
        commissionAmount = math.floor(amount * (societyConfig.authorCommissionPercent or 0) / 100)

        if Config.Insurance.enabled then
            for _, s in ipairs(Config.Insurance.applicableSocieties) do
                if s == society then
                    insuranceCovered = math.floor(amount * Config.Insurance.coveragePercent / 100)
                    payableAmount = amount - insuranceCovered
                    break
                end
            end
        end
    end

    -- Ratenzahlung
    local useInstallments = false
    local parts = tonumber(installmentParts) or 0
    if Config.Installments.enabled and parts >= 2 and parts <= Config.Installments.maxParts
       and payableAmount >= Config.Installments.minAmountForInstallments then
        useInstallments = true
    end

    GenerateRefId(function(refId)
        local sentDate = os.time()
        local dueDate = sentDate + (Config.AutoPay.daysUntilDue * 86400)

        MySQL.insert([[
            INSERT INTO esx_invoices
            (ref_id, receiver_identifier, receiver_name, author_identifier, author_name, society, society_label,
             item, invoice_value, original_value, insurance_covered, fee_amount, commission_amount,
             is_installment, installment_count, status, notes, sent_date, limit_pay_date)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', ?, ?, ?)
        ]], {
            refId,
            xTarget.identifier, GetPlayerName(xTarget),
            xSender.identifier, GetPlayerName(xSender),
            society, societyLabel,
            itemSummary, payableAmount, originalValue, insuranceCovered, feeAmount, commissionAmount,
            useInstallments and 1 or 0, useInstallments and parts or nil,
            notes,
            FormatDate(sentDate), FormatDate(dueDate)
        }, function(insertId)
            if not insertId then
                Config.Notify(src, 'Fehler beim Erstellen der Rechnung.', 'error')
                return
            end

            -- Positionen speichern
            for _, it in ipairs(cleanItems) do
                MySQL.insert('INSERT INTO esx_invoice_items (invoice_id, label, price) VALUES (?, ?, ?)',
                    { insertId, it.label, it.price })
            end

            -- Ratenplan anlegen
            if useInstallments then
                local base = math.floor(payableAmount / parts)
                local remainder = payableAmount - (base * parts)
                for i = 1, parts do
                    local partAmount = base + (i == parts and remainder or 0)
                    local partDue = sentDate + (i * Config.Installments.daysBetweenParts * 86400)
                    MySQL.insert('INSERT INTO esx_invoice_installments (invoice_id, part_number, amount, status, due_date) VALUES (?, ?, ?, "open", ?)',
                        { insertId, i, partAmount, FormatDate(partDue) })
                end
            end

            local insuranceNote = insuranceCovered > 0 and (' (Versicherung übernimmt %d$)'):format(insuranceCovered) or ''
            Config.Notify(src, ('Rechnung [%s] über %d$ an %s gesendet.'):format(refId, payableAmount, GetPlayerName(xTarget)), 'success')
            Config.Notify(xTarget.source, ('Neue Rechnung [%s] über %d$ von %s erhalten.%s'):format(refId, payableAmount, societyLabel or GetPlayerName(xSender), insuranceNote), 'info')

            TriggerClientEvent('esx_rechnungen:refresh', xTarget.source)
            TriggerClientEvent('esx_rechnungen:refresh', src)

            DiscordLog('💸 Neue Rechnung', ('**%s** hat **%s** eine Rechnung über **%d$** ausgestellt.\n**Referenz:** `%s`\n**Grund:** %s\n**Gesellschaft:** %s'):format(
                GetPlayerName(xSender), GetPlayerName(xTarget), payableAmount, refId, itemSummary, societyLabel or 'Persönlich'
            ))
        end)
    end)
end)

-------------------------------------------------------
-- Gruppen-Rechnung: Betrag gleichmäßig auf mehrere Spieler aufteilen
-------------------------------------------------------

RegisterNetEvent('esx_rechnungen:sendGroupInvoice', function(targetServerIds, totalAmount, item, notes)
    local src = source
    local xSender = ESX.GetPlayerFromId(src)
    if not xSender then return end

    if not Config.GroupInvoice.enabled then
        Config.Notify(src, 'Gruppenrechnungen sind deaktiviert.', 'error')
        return
    end

    if type(targetServerIds) ~= 'table' or #targetServerIds == 0 then
        Config.Notify(src, 'Bitte mindestens einen Spieler auswählen.', 'error')
        return
    end

    if #targetServerIds > Config.GroupInvoice.maxPlayers then
        Config.Notify(src, ('Maximal %d Spieler pro Gruppenrechnung.'):format(Config.GroupInvoice.maxPlayers), 'error')
        return
    end

    totalAmount = tonumber(totalAmount)
    if not totalAmount or totalAmount <= 0 then
        Config.Notify(src, 'Ungültiger Betrag.', 'error')
        return
    end
    totalAmount = math.floor(totalAmount)

    item = item and tostring(item):sub(1, 150) or 'Gruppenrechnung'
    notes = notes and tostring(notes):sub(1, 255) or ''

    local targets = {}
    for _, id in ipairs(targetServerIds) do
        local xTarget = ESX.GetPlayerFromId(tonumber(id))
        if xTarget and xTarget.source ~= xSender.source then
            targets[#targets + 1] = xTarget
        end
    end

    if #targets == 0 then
        Config.Notify(src, 'Keine gültigen Spieler gefunden.', 'error')
        return
    end

    local count = #targets
    local base = math.floor(totalAmount / count)
    local remainder = totalAmount - (base * count)
    local groupId = GenerateGroupId()
    local sentDate = os.time()
    local dueDate = sentDate + (Config.AutoPay.daysUntilDue * 86400)

    local created = 0
    for i, xTarget in ipairs(targets) do
        local share = base + (i <= remainder and 1 or 0)

        GenerateRefId(function(refId)
            MySQL.insert([[
                INSERT INTO esx_invoices
                (ref_id, group_id, receiver_identifier, receiver_name, author_identifier, author_name, item, invoice_value, original_value, status, notes, sent_date, limit_pay_date)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', ?, ?, ?)
            ]], {
                refId, groupId,
                xTarget.identifier, GetPlayerName(xTarget),
                xSender.identifier, GetPlayerName(xSender),
                ('%s (Anteil an Gruppenrechnung, %d Personen)'):format(item, count), share, share,
                notes, FormatDate(sentDate), FormatDate(dueDate)
            }, function(insertId)
                created = created + 1
                if insertId then
                    Config.Notify(xTarget.source, ('Du bist Teil einer Gruppenrechnung "%s": dein Anteil beträgt %d$.'):format(item, share), 'info')
                    TriggerClientEvent('esx_rechnungen:refresh', xTarget.source)
                end
                if created == count then
                    Config.Notify(src, ('Gruppenrechnung "%s" über %d$ an %d Spieler gesendet.'):format(item, totalAmount, count), 'success')
                    TriggerClientEvent('esx_rechnungen:refresh', src)
                end
            end)
        end)
    end
end)

-------------------------------------------------------
-- Zentrale Bezahlfunktion für eine vollständige (Nicht-Raten-)Rechnung
-------------------------------------------------------

local function ProcessPayment(invoice, xPlayer, statusOnSuccess, cb)
    local account = Config.PaymentAccount
    local balance
    if account == 'bank' then
        balance = xPlayer.getAccount('bank').money
    else
        balance = xPlayer.getMoney()
    end

    if balance < invoice.invoice_value then
        cb(false, 'Nicht genug Geld, um diese Rechnung zu bezahlen.')
        return
    end

    if account == 'bank' then
        xPlayer.removeAccountMoney('bank', invoice.invoice_value)
    else
        xPlayer.removeMoney(invoice.invoice_value)
    end

    local shares = ComputeShares(invoice, 1.0)
    DistributeShares(invoice, shares)

    MySQL.update('UPDATE esx_invoices SET status = ?, paid_date = NOW() WHERE id = ?', { statusOnSuccess, invoice.id })

    DiscordLog('✅ Rechnung bezahlt', ('**%s** hat Rechnung `%s` über **%d$** bezahlt.'):format(invoice.receiver_name, invoice.ref_id, invoice.invoice_value), 3066993)

    cb(true)
end

-------------------------------------------------------
-- Einzelne Rechnung bezahlen (keine Ratenrechnungen)
-------------------------------------------------------

RegisterNetEvent('esx_rechnungen:payInvoice', function(invoiceId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    MySQL.single('SELECT * FROM esx_invoices WHERE id = ? AND status = "open"', { invoiceId }, function(invoice)
        if not invoice then
            Config.Notify(src, 'Rechnung nicht gefunden oder bereits bezahlt.', 'error')
            return
        end
        if invoice.receiver_identifier ~= xPlayer.identifier then
            Config.Notify(src, 'Diese Rechnung gehört dir nicht.', 'error')
            return
        end
        if invoice.is_installment == 1 then
            Config.Notify(src, 'Diese Rechnung läuft als Ratenzahlung. Bitte einzelne Raten begleichen.', 'error')
            return
        end

        ProcessPayment(invoice, xPlayer, 'paid', function(success, err)
            if not success then
                Config.Notify(src, err, 'error')
                return
            end
            Config.Notify(src, ('Rechnung [%s] über %d$ bezahlt.'):format(invoice.ref_id, invoice.invoice_value), 'success')
            TriggerClientEvent('esx_rechnungen:refresh', src)
        end)
    end)
end)

-------------------------------------------------------
-- Ratenzahlung: einzelne Rate bezahlen
-------------------------------------------------------

RegisterNetEvent('esx_rechnungen:payInstallment', function(installmentId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    MySQL.single('SELECT * FROM esx_invoice_installments WHERE id = ? AND status = "open"', { installmentId }, function(part)
        if not part then
            Config.Notify(src, 'Rate nicht gefunden oder bereits bezahlt.', 'error')
            return
        end

        MySQL.single('SELECT * FROM esx_invoices WHERE id = ?', { part.invoice_id }, function(invoice)
            if not invoice then
                Config.Notify(src, 'Zugehörige Rechnung nicht gefunden.', 'error')
                return
            end
            if invoice.receiver_identifier ~= xPlayer.identifier then
                Config.Notify(src, 'Diese Rate gehört dir nicht.', 'error')
                return
            end

            local balance = Config.PaymentAccount == 'bank' and xPlayer.getAccount('bank').money or xPlayer.getMoney()
            if balance < part.amount then
                Config.Notify(src, 'Nicht genug Geld für diese Rate.', 'error')
                return
            end

            if Config.PaymentAccount == 'bank' then
                xPlayer.removeAccountMoney('bank', part.amount)
            else
                xPlayer.removeMoney(part.amount)
            end

            local ratio = part.amount / invoice.invoice_value
            local shares = ComputeShares(invoice, ratio)
            DistributeShares(invoice, shares)

            MySQL.update('UPDATE esx_invoice_installments SET status = "paid", paid_date = NOW() WHERE id = ?', { part.id })

            Config.Notify(src, ('Rate %d/%d von Rechnung [%s] über %d$ bezahlt.'):format(part.part_number, invoice.installment_count, invoice.ref_id, part.amount), 'success')

            MySQL.scalar('SELECT COUNT(*) FROM esx_invoice_installments WHERE invoice_id = ? AND status = "open"', { invoice.id }, function(openCount)
                if openCount == 0 then
                    MySQL.update('UPDATE esx_invoices SET status = "paid", paid_date = NOW() WHERE id = ?', { invoice.id })
                    Config.Notify(src, ('Rechnung [%s] vollständig abbezahlt.'):format(invoice.ref_id), 'success')
                end
                TriggerClientEvent('esx_rechnungen:refresh', src)
            end)
        end)
    end)
end)

-------------------------------------------------------
-- Alle offenen (Nicht-Raten-)Rechnungen auf einmal bezahlen
-------------------------------------------------------

RegisterNetEvent('esx_rechnungen:payAllInvoices', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    MySQL.query('SELECT * FROM esx_invoices WHERE receiver_identifier = ? AND status = "open" AND is_installment = 0 ORDER BY sent_date ASC', { xPlayer.identifier }, function(invoices)
        if not invoices or #invoices == 0 then
            Config.Notify(src, 'Du hast keine offenen Rechnungen.', 'info')
            return
        end

        local total = 0
        for _, inv in ipairs(invoices) do total = total + inv.invoice_value end

        local balance = Config.PaymentAccount == 'bank' and xPlayer.getAccount('bank').money or xPlayer.getMoney()

        if balance < total then
            Config.Notify(src, ('Du benötigst %d$, um alle offenen Rechnungen zu begleichen, hast aber nur %d$.'):format(total, balance), 'error')
            return
        end

        local paidCount = 0
        for _, inv in ipairs(invoices) do
            ProcessPayment(inv, xPlayer, 'paid', function(success)
                if success then paidCount = paidCount + 1 end
                if paidCount == #invoices then
                    Config.Notify(src, ('%d Rechnungen über insgesamt %d$ bezahlt.'):format(#invoices, total), 'success')
                    TriggerClientEvent('esx_rechnungen:refresh', src)
                end
            end)
        end
    end)
end)

-------------------------------------------------------
-- Rechnung per Referenz-Code bezahlen (auch fremde Rechnungen)
-------------------------------------------------------

RegisterNetEvent('esx_rechnungen:payByReference', function(refId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    refId = tostring(refId or ''):upper():gsub('%s', '')
    if refId == '' then
        Config.Notify(src, 'Bitte gib einen Referenz-Code ein.', 'error')
        return
    end

    MySQL.single('SELECT * FROM esx_invoices WHERE ref_id = ? AND status = "open"', { refId }, function(invoice)
        if not invoice then
            Config.Notify(src, 'Keine offene Rechnung mit diesem Code gefunden.', 'error')
            return
        end
        if invoice.is_installment == 1 then
            Config.Notify(src, 'Diese Rechnung läuft als Ratenzahlung und kann nicht per Referenz auf einmal bezahlt werden.', 'error')
            return
        end

        ProcessPayment(invoice, xPlayer, 'paid', function(success, err)
            if not success then
                Config.Notify(src, err, 'error')
                return
            end
            Config.Notify(src, ('Rechnung [%s] von %s über %d$ bezahlt.'):format(invoice.ref_id, invoice.receiver_name, invoice.invoice_value), 'success')
            TriggerClientEvent('esx_rechnungen:refresh', src)

            local xReceiver = ESX.GetPlayerFromIdentifier(invoice.receiver_identifier)
            if xReceiver and xReceiver.source ~= src then
                Config.Notify(xReceiver.source, ('%s hat deine Rechnung [%s] für dich beglichen.'):format(GetPlayerName(xPlayer), invoice.ref_id), 'info')
                TriggerClientEvent('esx_rechnungen:refresh', xReceiver.source)
            end
        end)
    end)
end)

-------------------------------------------------------
-- Eigene Rechnungen abrufen (für NUI)
-------------------------------------------------------

ESX.RegisterServerCallback('esx_rechnungen:getInvoices', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb({ received = {}, sent = {} }) return end

    local identifier = xPlayer.identifier

    MySQL.query('SELECT * FROM esx_invoices WHERE receiver_identifier = ? ORDER BY sent_date DESC LIMIT 150', { identifier }, function(received)
        MySQL.query('SELECT * FROM esx_invoices WHERE author_identifier = ? ORDER BY sent_date DESC LIMIT 150', { identifier }, function(sent)
            cb({ received = received or {}, sent = sent or {} })
        end)
    end)
end)

-------------------------------------------------------
-- Details einer Rechnung (Positionen + Ratenplan) - für Detailansicht/PDF
-------------------------------------------------------

ESX.RegisterServerCallback('esx_rechnungen:getInvoiceDetail', function(source, cb, invoiceId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb(nil) return end

    MySQL.single('SELECT * FROM esx_invoices WHERE id = ?', { invoiceId }, function(invoice)
        if not invoice then cb(nil) return end

        local isOwner = invoice.receiver_identifier == xPlayer.identifier or invoice.author_identifier == xPlayer.identifier
        if not isOwner and not CanManage(source, xPlayer) then
            cb(nil)
            return
        end

        MySQL.query('SELECT * FROM esx_invoice_items WHERE invoice_id = ?', { invoiceId }, function(items)
            MySQL.query('SELECT * FROM esx_invoice_installments WHERE invoice_id = ? ORDER BY part_number ASC', { invoiceId }, function(installments)
                cb({ invoice = invoice, items = items or {}, installments = installments or {} })
            end)
        end)
    end)
end)

-------------------------------------------------------
-- Spielerliste (online) für "Neue Rechnung"
-------------------------------------------------------

ESX.RegisterServerCallback('esx_rechnungen:getPlayers', function(source, cb)
    local players = {}
    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        if xPlayer.source ~= source then
            players[#players + 1] = { id = xPlayer.source, name = GetPlayerName(xPlayer) }
        end
    end
    cb(players)
end)

-------------------------------------------------------
-- Eigenen Job / verfügbare Societies + Presets für "Neue Rechnung" abrufen
-------------------------------------------------------

ESX.RegisterServerCallback('esx_rechnungen:getContext', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb(nil) return end

    local job = xPlayer.job and xPlayer.job.name
    local societyData = nil

    if job and Config.Societies[job] then
        societyData = {
            key = job,
            label = Config.Societies[job].label,
            items = Config.Societies[job].items
        }
    end

    cb({
        allowPersonal = Config.AllowPersonalInvoices,
        society = societyData,
        canInspect = HasJobAccess(xPlayer, Config.InspectJobs),
        canManage = CanManage(source, xPlayer),
        installmentsEnabled = Config.Installments.enabled,
        installmentsMinAmount = Config.Installments.minAmountForInstallments,
        installmentsMaxParts = Config.Installments.maxParts,
        groupInvoiceEnabled = Config.GroupInvoice.enabled,
        groupInvoiceMaxPlayers = Config.GroupInvoice.maxPlayers
    })
end)

-------------------------------------------------------
-- "Spieler prüfen": offene Rechnungen eines Ziels einsehen
-------------------------------------------------------

ESX.RegisterServerCallback('esx_rechnungen:inspectPlayer', function(source, cb, targetServerId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not HasJobAccess(xPlayer, Config.InspectJobs) then
        cb(nil)
        return
    end

    local xTarget = ESX.GetPlayerFromId(tonumber(targetServerId))
    if not xTarget then
        cb(nil)
        return
    end

    MySQL.query('SELECT * FROM esx_invoices WHERE receiver_identifier = ? AND status = "open" ORDER BY sent_date DESC', { xTarget.identifier }, function(invoices)
        local total = 0
        for _, inv in ipairs(invoices) do total = total + inv.invoice_value end
        cb({
            name = GetPlayerName(xTarget),
            count = #invoices,
            total = total,
            invoices = invoices
        })
    end)
end)

-------------------------------------------------------
-- "Stadt-Rechnungen": alle Rechnungen server-weit verwalten
-------------------------------------------------------

ESX.RegisterServerCallback('esx_rechnungen:getCityInvoices', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not CanManage(source, xPlayer) then
        cb(nil)
        return
    end

    MySQL.query('SELECT * FROM esx_invoices ORDER BY sent_date DESC LIMIT 300', {}, function(invoices)
        cb(invoices or {})
    end)
end)

RegisterNetEvent('esx_rechnungen:cancelInvoice', function(invoiceId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not CanManage(src, xPlayer) then
        Config.Notify(src, 'Keine Berechtigung.', 'error')
        return
    end

    MySQL.update('UPDATE esx_invoices SET status = "cancelled" WHERE id = ? AND status = "open"', { invoiceId }, function(affected)
        if affected and affected > 0 then
            Config.Notify(src, 'Rechnung storniert.', 'success')
        else
            Config.Notify(src, 'Rechnung konnte nicht storniert werden.', 'error')
        end
    end)
end)

-------------------------------------------------------
-- Society-Dashboard / Leaderboard: Umsatz & Anzahl je Mitarbeiter
-------------------------------------------------------

ESX.RegisterServerCallback('esx_rechnungen:getSocietyLeaderboard', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb(nil) return end

    local job = xPlayer.job and xPlayer.job.name
    if not job or not Config.Societies[job] then
        cb(nil)
        return
    end

    MySQL.query([[
        SELECT author_identifier, author_name,
               COUNT(*) AS invoice_count,
               SUM(COALESCE(original_value, invoice_value)) AS total_revenue
        FROM esx_invoices
        WHERE society = ? AND status IN ('paid', 'autopaid')
        GROUP BY author_identifier, author_name
        ORDER BY total_revenue DESC
        LIMIT 15
    ]], { job }, function(rows)
        MySQL.scalar('SELECT COUNT(*) FROM esx_invoices WHERE society = ? AND status = "open"', { job }, function(openCount)
            cb({
                society = Config.Societies[job].label,
                rows = rows or {},
                openCount = openCount or 0
            })
        end)
    end)
end)

-------------------------------------------------------
-- Autopay: prüft periodisch überfällige Rechnungen und Raten von online Spielern
-------------------------------------------------------

if Config.AutoPay.enabled then
    CreateThread(function()
        while true do
            Wait(Config.AutoPay.checkIntervalMinutes * 60 * 1000)

            -- Normale Rechnungen
            MySQL.query('SELECT * FROM esx_invoices WHERE status = "open" AND is_installment = 0 AND limit_pay_date <= NOW()', {}, function(overdue)
                if not overdue then return end
                for _, invoice in ipairs(overdue) do
                    local xPlayer = ESX.GetPlayerFromIdentifier(invoice.receiver_identifier)
                    if xPlayer then
                        local balance = Config.PaymentAccount == 'bank' and xPlayer.getAccount('bank').money or xPlayer.getMoney()
                        if balance >= invoice.invoice_value then
                            ProcessPayment(invoice, xPlayer, 'autopaid', function(success)
                                if success then
                                    Config.Notify(xPlayer.source, ('Rechnung [%s] über %d$ wurde automatisch beglichen (Fälligkeit überschritten).'):format(invoice.ref_id, invoice.invoice_value), 'info')
                                    TriggerClientEvent('esx_rechnungen:refresh', xPlayer.source)
                                end
                            end)
                        end
                    end
                end
            end)

            -- Überfällige Raten
            MySQL.query('SELECT * FROM esx_invoice_installments WHERE status = "open" AND due_date <= NOW()', {}, function(overdueParts)
                if not overdueParts then return end
                for _, part in ipairs(overdueParts) do
                    MySQL.single('SELECT * FROM esx_invoices WHERE id = ?', { part.invoice_id }, function(invoice)
                        if not invoice then return end
                        local xPlayer = ESX.GetPlayerFromIdentifier(invoice.receiver_identifier)
                        if xPlayer then
                            local balance = Config.PaymentAccount == 'bank' and xPlayer.getAccount('bank').money or xPlayer.getMoney()
                            if balance >= part.amount then
                                if Config.PaymentAccount == 'bank' then
                                    xPlayer.removeAccountMoney('bank', part.amount)
                                else
                                    xPlayer.removeMoney(part.amount)
                                end

                                local ratio = part.amount / invoice.invoice_value
                                local shares = ComputeShares(invoice, ratio)
                                DistributeShares(invoice, shares)

                                MySQL.update('UPDATE esx_invoice_installments SET status = "paid", paid_date = NOW() WHERE id = ?', { part.id })
                                Config.Notify(xPlayer.source, ('Rate %d/%d von Rechnung [%s] wurde automatisch beglichen.'):format(part.part_number, invoice.installment_count, invoice.ref_id), 'info')

                                MySQL.scalar('SELECT COUNT(*) FROM esx_invoice_installments WHERE invoice_id = ? AND status = "open"', { invoice.id }, function(openCount)
                                    if openCount == 0 then
                                        MySQL.update('UPDATE esx_invoices SET status = "autopaid", paid_date = NOW() WHERE id = ?', { invoice.id })
                                    end
                                    TriggerClientEvent('esx_rechnungen:refresh', xPlayer.source)
                                end)
                            end
                        end
                    end)
                end
            end)
        end
    end)
end
