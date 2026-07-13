# ESX Rechnungssystem V2 (esx_rechnungen)

Umfangreiches Rechnungs-/Billing-System für ESX, funktional und optisch an **okokBilling**
angelehnt (Society-Rechnungen, Referenz-Zahlungen, Autopay, Verwaltungsmenü), aber komplett
eigenständig programmiert und ohne Fremdabhängigkeiten zu okok-Produkten.

## Features

- **Persönliche Rechnungen**: Spieler an Spieler, frei wählbarer Betrag & Grund.
- **Society-/Job-Rechnungen**: Polizei, EMS, Mechaniker etc. mit vorkonfigurierten Positionen
  (Bußgeldkatalog) inkl. Preis – direkt im Config-File erweiterbar.
- **Mehrere Positionen pro Rechnung**: beliebig viele Positionen (Grund + Preis) pro Rechnung,
  Gesamtsumme wird automatisch berechnet.
- **Ratenzahlung**: Rechnungen ab einem konfigurierbaren Mindestbetrag können in 2–6 Raten
  aufgeteilt werden, jede Rate hat eine eigene Fälligkeit und wird einzeln bezahlt/autopaid.
- **Gruppen-Rechnung**: Betrag gleichmäßig auf mehrere ausgewählte Online-Spieler aufteilen
  (z.B. Restaurantrechnung), jeder erhält seinen Anteil als eigene Rechnung.
- **Provisionen**: Aussteller einer Society-Rechnung kann prozentual am Betrag beteiligt werden.
- **Steuer/Fee-Anteil**: Ein konfigurierbarer Prozentsatz wird vom Society-Anteil abgezogen (VAT-Logik).
- **Versicherungssystem**: Für konfigurierte Societies (z.B. EMS) übernimmt eine "Versicherung"
  automatisch einen Prozentsatz der Rechnung – der Spieler zahlt nur den Rest, die Society
  bekommt trotzdem den vollen Anteil (Versicherungsanteil über `Config.WithdrawFromInsurance`-Hook).
- **Alle Rechnungen auf einmal bezahlen** ("Alle bezahlen"-Button im Dashboard).
- **Referenz-Code-Zahlung**: Jede Rechnung erhält einen 6-stelligen Code, mit dem *jeder* Spieler
  sie begleichen kann (z.B. Kollege zahlt Bußgeld eines anderen).
- **Spieler prüfen**: Job-geschützte Ansicht, wie viele offene Rechnungen ein Ziel-Spieler hat.
- **Team-Dashboard / Leaderboard**: Umsatz und Anzahl bezahlter Rechnungen je Mitarbeiter
  innerhalb der eigenen Society, sortiert als Rangliste.
- **Stadt-Rechnungen**: Verwaltungsübersicht über alle Rechnungen server-weit (Job- oder
  Ace-Permission-geschützt), inkl. Stornieren offener Rechnungen.
- **Suche, Filter & Sortierung**: in allen Listen (Übersicht, Gesendet, Stadt-Rechnungen) nach
  Status, Freitext (Grund/Name/Referenz) und Sortierung (Datum/Betrag).
- **PDF-Export**: jede Rechnung lässt sich als PDF-Dokument herunterladen (inkl. Positionen und
  ggf. Ratenplan), erzeugt clientseitig über jsPDF.
- **Autopay**: Unbezahlte Rechnungen (und einzelne Raten) werden nach konfigurierbarer Frist
  automatisch belastet, sofern der Spieler online ist und genug Geld hat.
- **Discord-Logs** (optional, per Webhook).
- Eigenständiges NUI-Design: dunkles Glass-/Fintech-Interface mit Sidebar-Navigation und
  Referenz-Code als "Ticket-Stub"-Element.

## Voraussetzungen

- `es_extended` (ESX Legacy oder kompatibel)
- `oxmysql`

## Installation

1. Ordner `esx_rechnungen` nach `resources/` kopieren.
2. `sql/install.sql` in eure Datenbank importieren.
3. `config.lua` an eure Server-Jobs (Societies), Berechtigungen und ggf. Discord-Webhook anpassen.
4. In der `server.cfg` (nach `es_extended` und `oxmysql`):
   ```
   ensure oxmysql
   ensure es_extended
   ensure esx_rechnungen
   ```
5. `Config.DepositToSociety` in `config.lua` an euer Gesellschaftssystem (z.B. `esx_society`)
   anbinden, damit der Society-Anteil bezahlter Rechnungen korrekt eingezahlt wird. Aktuell wird
   das nur ins Serverlog geschrieben (Platzhalter, s. Kommentare in der Datei).

## Nutzung

- `/rechnungen` oder Taste **F6** öffnet die NUI.
- **Übersicht**: erhaltene Rechnungen, Statistik-Karten, "Alle bezahlen".
- **Gesendet**: eigene ausgestellte Rechnungen.
- **Neue Rechnung**: Umschalter Persönlich/Gesellschaft (Gesellschaft nur sichtbar, wenn der
  Spieler einen entsprechenden Job in `Config.Societies` hat), mit Preisvorlagen.
- **Referenz bezahlen**: 6-stelligen Code eingeben, um eine beliebige offene Rechnung zu begleichen.
- **Spieler prüfen** *(nur `Config.InspectJobs`)*: offene Rechnungen eines Ziel-Spielers einsehen.
- **Stadt-Rechnungen** *(nur `Config.ManageJobs` oder Ace-Permission)*: alle Rechnungen einsehen
  und offene stornieren.

## Konfiguration (`config.lua`) – wichtigste Punkte

| Option | Beschreibung |
|---|---|
| `Config.Command` / `Config.Key` | Öffnet die NUI (Standard: `/rechnungen`, F6) |
| `Config.PaymentAccount` | `'bank'` oder `'money'` |
| `Config.Societies` | Jobs mit Preisliste, Fee- und Provisions-Prozentsatz |
| `Config.InspectJobs` / `Config.ManageJobs` | Berechtigungen für die Zusatzmenüs |
| `Config.ManageAcePermission` | Admin-Override für "Stadt-Rechnungen" |
| `Config.AutoPay` | Autopay aktivieren, Frist in Tagen, Prüfintervall |
| `Config.Installments` | Ratenzahlung aktivieren, Mindestbetrag, max. Anzahl Raten, Tage zwischen Raten |
| `Config.GroupInvoice` | Gruppenrechnungen aktivieren, max. Anzahl Spieler |
| `Config.Insurance` | Versicherung aktivieren, Deckungsprozentsatz, betroffene Societies |
| `Config.DiscordLogs` | Webhook für Rechnungs-Logs |
| `Config.DepositToSociety(society, amount)` | Hook, um bezahlte Society-Anteile eurem Gesellschaftskonto gutzuschreiben |
| `Config.WithdrawFromInsurance(amount, society)` | Hook, um den Versicherungsanteil aus eurer Versicherungs-/Staatskasse abzuziehen |

## Hinweis zu PDF-Export

Der PDF-Export läuft komplett im Browser (jsPDF, per CDN eingebunden) und läst sich in der
FiveM-NUI direkt als Datei herunterladen. Sollte der Download im Spiel-Client aus irgendeinem
Grund nicht auslösen (abhängig von CEF-Konfiguration einzelner Server), könnt ihr alternativ
`window.print()` mit einer eigenen Druck-Stylesheet ergänzen, um über den Browser-Druckdialog
"Als PDF speichern" zu nutzen.

## Browser-Vorschau

Im Ordner `html/` liegt `preview.html` – einfach doppelklicken, um das Design mit Testdaten
(inkl. Society-Kontext, Stadt-Rechnungen, Spieler-prüfen-Ergebnis) direkt im Browser zu sehen,
ganz ohne FiveM-Server.

## Hinweis zu React

Die NUI ist bewusst als reines HTML/CSS/JS ohne Build-Schritt umgesetzt. Die NUI-Callback-Namen
(`payInvoice`, `payAllInvoices`, `payByReference`, `sendInvoice`, `cancelInvoice`,
`inspectPlayer`, `getCityInvoices`, `close`, `refreshData`) und die `postMessage`-Events
(`open`, `close`, `setInvoices`, `setPlayers`, `setContext`) sind stabil, d.h. der `html/`-Ordner
lässt sich später 1:1 durch eine gebaute React-App ersetzen, ohne die Lua-Seite anzufassen.
