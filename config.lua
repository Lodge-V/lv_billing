Config = {}

-------------------------------------------------------
-- Allgemein
-------------------------------------------------------

Config.Command      = 'rechnungen'   -- öffnet die NUI
Config.Key           = 'F7'           -- Standard-Keybind
Config.PaymentAccount = 'bank'        -- 'bank' oder 'money' (Bargeld)

-- Grenzen für persönliche Rechnungen
Config.MinAmount = 1
Config.MaxAmount = 500000

-- Erlaubt Rechnungen ohne Gesellschaft/Job (Spieler an Spieler)
Config.AllowPersonalInvoices = true

-------------------------------------------------------
-- Autopay: unbezahlte Rechnungen werden nach X Tagen automatisch belastet
-------------------------------------------------------

Config.AutoPay = {
    enabled     = true,
    daysUntilDue = 3,       -- Tage bis zur Fälligkeit
    checkIntervalMinutes = 15 -- wie oft der Autopay-Check online Spieler prüft
}

-------------------------------------------------------
-- Gesellschaften / Jobs mit vorkonfigurierten Rechnungspositionen
-- society = interner Job-Name (xPlayer.job.name)
-- items   = vorkonfigurierte Bußgelder/Positionen, die im "Neue Rechnung"-Tab
--           als Schnellauswahl auftauchen (Preis kann trotzdem angepasst werden)
-- feePercent   = wie viel % des Rechnungswerts als "Steuer" NICHT an die Society geht
-- authorCommissionPercent = wie viel % der Aussteller (Spieler) persönlich als Provision erhält
-------------------------------------------------------

Config.Societies = {
    police = {
        label = 'Los Santos Police Department',
        feePercent = 10,
        authorCommissionPercent = 5,
        items = {
            { label = 'Falschparken',            price = 250  },
            { label = 'Rotlichtverstoß',          price = 400  },
            { label = 'Geschwindigkeitsüberschreitung', price = 600  },
            { label = 'Widerstand gegen Vollstreckungsbeamte', price = 1500 },
            { label = 'Waffenbesitz ohne Lizenz', price = 2500 },
        }
    },
    ambulance = {
        label = 'Los Santos EMS',
        feePercent = 0,
        authorCommissionPercent = 10,
        items = {
            { label = 'Erstversorgung',   price = 400  },
            { label = 'Krankenhausaufenthalt', price = 1200 },
            { label = 'Operation',        price = 3500 },
        }
    },
    mechanic = {
        label = 'Bennys Werkstatt',
        feePercent = 0,
        authorCommissionPercent = 15,
        items = {
            { label = 'Kleine Reparatur', price = 300  },
            { label = 'Große Reparatur',  price = 900  },
            { label = 'Tuning',           price = 2000 },
        }
    },
}

-------------------------------------------------------
-- Berechtigungen für Zusatzmenüs
-------------------------------------------------------

-- Jobs, die "Spieler prüfen" (offene Rechnungen eines Ziels einsehen) nutzen dürfen
Config.InspectJobs = { 'police', 'ambulance' }

-- Jobs, die das Verwaltungsmenü "Stadt-Rechnungen" (alle Rechnungen server-weit) nutzen dürfen
Config.ManageJobs = { 'police' }

-- Zusätzlich: ESX-Ace-Permission, die IMMER Zugriff auf "Stadt-Rechnungen" hat (Admin-Override)
Config.ManageAcePermission = 'command'

-------------------------------------------------------
-- Ratenzahlung: große Rechnungen können in Teilbeträge gesplittet werden
-------------------------------------------------------

Config.Installments = {
    enabled = true,
    minAmountForInstallments = 1000, -- ab diesem Betrag darf in Raten gezahlt werden
    maxParts = 6,                    -- maximale Anzahl Raten
    daysBetweenParts = 7             -- Fälligkeit jeder weiteren Rate (Tage nach Ausstellung)
}

-------------------------------------------------------
-- Gruppen-Rechnung: Betrag gleichmäßig auf mehrere Spieler aufteilen
-------------------------------------------------------

Config.GroupInvoice = {
    enabled = true,
    maxPlayers = 8
}

-------------------------------------------------------
-- Versicherung: übernimmt automatisch einen Teil bestimmter Society-Rechnungen
-- (z.B. Krankenkasse für EMS-Rechnungen)
-------------------------------------------------------

Config.Insurance = {
    enabled = true,
    coveragePercent = 50,                 -- wie viel % automatisch übernommen werden
    applicableSocieties = { 'ambulance' }  -- für welche Societies das gilt
}

-- Hook: wird aufgerufen, wenn die Versicherung einen Anteil übernimmt.
-- Standard: nutzt esx_banking (falls installiert, siehe eigenständiges Banking-Script),
-- sonst nur Logging.
function Config.WithdrawFromInsurance(amount, society)
    if GetResourceState('esx_banking') == 'started' then
        exports['esx_banking']:WithdrawFromInsurance(amount, society)
    else
        print(('[esx_rechnungen] Versicherung übernimmt %d$ für Society "%s" - bitte Config.WithdrawFromInsurance an eure Versicherungskasse anbinden.'):format(amount, society))
    end
end

-------------------------------------------------------
-- Discord Logs (optional)
-------------------------------------------------------

Config.DiscordLogs = {
    enabled = false,
    webhook = '',
    color = 3900151
}

-------------------------------------------------------
-- Notify (an euer eigenes Notify-System anpassbar, z.B. ox_lib)
-------------------------------------------------------

function Config.Notify(source, message, type)
    TriggerClientEvent('esx_rechnungen:notify', source, message, type or 'info')
end

-------------------------------------------------------
-- Hook: wird aufgerufen, wenn eine Society-Rechnung bezahlt wird,
-- damit ihr das Geld in euer Gesellschaftskonto (esx_society / okokBanking / etc.) einzahlen könnt.
-- Standard: versucht esx_addonaccount, sonst wird das Geld ignoriert (nur geloggt).
-------------------------------------------------------

-------------------------------------------------------
-- Hook: wird aufgerufen, wenn eine Society-Rechnung bezahlt wird,
-- damit ihr das Geld in euer Gesellschaftskonto einzahlen könnt.
-- Standard: nutzt esx_banking (falls installiert, siehe eigenständiges Banking-Script:
-- Gesellschaftskonten dort), sonst Fallback auf esx_society (auskommentiert) oder Logging.
-------------------------------------------------------

function Config.DepositToSociety(society, amount)
    if GetResourceState('esx_banking') == 'started' then
        exports['esx_banking']:DepositToSociety(society, amount)
        return
    end

    -- Beispiel-Fallback für esx_society (auskommentiert, je nach Serverstruktur anpassen):
    -- exports['esx_society']:getSocietyAccount(society, function(account)
    --     if account then account.addMoney(amount) end
    -- end)

    print(('[esx_rechnungen] %d$ sollten an Society "%s" ausgezahlt werden - bitte Config.DepositToSociety in config.lua an euer Gesellschaftssystem anbinden.'):format(amount, society))
end
