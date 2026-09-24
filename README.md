# GEG Gastro für MoneyMoney

Eine [MoneyMoney](https://moneymoney.app)-Erweiterung, die das Guthaben und die
Essensbestellungen aus dem Bestellportal von GEG Gastro
(<https://www.bestellung-geggastro.de>) abruft.

Das Portal bietet keine Schnittstelle. Die Erweiterung meldet sich mit den
Zugangsdaten des Kundenkontos an und liest die Seiten »Bestellübersicht« und
»Guthaben« aus.

> [!NOTE]
> Dies ist ein inoffizielles Projekt. Es steht in keiner Verbindung zur
> GEG Gastro Service GmbH oder zu schulmenueplaner.de und wird von diesen
> weder unterstützt noch geprüft. Der Name »GEG Gastro« dient nur dazu, das
> Portal zu bezeichnen, aus dem die Erweiterung Daten abruft.

![Essensbestellungen als Umsätze in MoneyMoney](docs/screenshot.png)

## Was die Erweiterung liefert

- **Ein Konto** pro Portal-Login.
- **Ein Umsatz pro Bestellung.** Das Essen steht im Feld »Name«, das Menü
  (z. B. »Zertifiziert« oder »Veggie«) im Buchungstext und der Name des Kindes
  im Verwendungszweck. Mehrere Kinder werden automatisch erkannt.
- **Echte Preise.** Der Betrag jeder Bestellung stammt aus der Seite
  »Guthaben« des Portals. Die Bestellung wird dort über das Kind und den Tag
  des Essens gefunden.
- **Aufladungen als Habenbuchungen,** z. B. »Überweisungseingang vom …«.
- **Zukünftige Bestellungen als vorgemerkte Umsätze.** Bestellungen ab morgen
  erscheinen als vorgemerkt, Bestellungen bis einschließlich heute als gebucht.
  Wird eine zukünftige Bestellung im Portal storniert, verschwindet der
  vorgemerkte Umsatz beim nächsten Abruf.
- **Saldo passend zu den Umsätzen.** Das Portal zieht den Preis schon bei der
  Bestellung vom Guthaben ab. In MoneyMoney zählen vorgemerkte Bestellungen
  erst am Tag des Essens. Der gebuchte Saldo ist daher das Guthaben im Portal
  zuzüglich der vorgemerkten Bestellungen; der Saldo inklusive vorgemerkter
  Umsätze entspricht dem Guthaben im Portal.

Beim ersten Abruf werden Bestellungen der letzten 10 Jahre und alle Seiten der
Guthaben-Umsätze geladen. Danach holt jeder Abruf die Bestellungen ab einer
Woche vor dem letzten Abruf bis 10 Wochen in die Zukunft und nur so viele
Seiten der Guthaben-Umsätze, wie dafür nötig sind.

## Installation

1. `GEG-Gastro.lua` in den Erweiterungsordner von MoneyMoney kopieren:
   `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
   (in MoneyMoney über »Hilfe« → »Zeige Datenbank im Finder« erreichbar).
2. Solange die Erweiterung nicht von MoneyMoney signiert ist, unter
   »MoneyMoney« → »Einstellungen« → »Erweiterungen« die Option
   »Digitale Signatur von Extensions überprüfen« deaktivieren.
3. In MoneyMoney »Konto« → »Konto hinzufügen« → »Andere« → »GEG Gastro«
   wählen und die Zugangsdaten des Portals eingeben.

## Nicht enthalten

- Stornos bereits gebuchter Bestellungen. Das Portal löscht die Buchung
  einer stornierten Bestellung ohne Gegenbuchung; ein bereits gebuchter Umsatz
  bleibt in MoneyMoney stehen und muss von Hand gelöscht werden.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
