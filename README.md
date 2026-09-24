# GEG Gastro für MoneyMoney

Eine [MoneyMoney](https://moneymoney.app)-Erweiterung, die das Guthaben und die
Essensbestellungen aus dem Bestellportal von GEG Gastro
(<https://www.bestellung-geggastro.de>) abruft.

Das Portal bietet keine Schnittstelle. Die Erweiterung meldet sich mit den
Zugangsdaten des Kundenkontos an und liest die Seite »Bestellübersicht« aus.

![Essensbestellungen als Umsätze in MoneyMoney](docs/screenshot.png)

## Was die Erweiterung liefert

- **Ein Konto** pro Portal-Login mit dem aktuellen Guthaben als Saldo.
- **Ein Umsatz pro Bestellung.** Das Essen steht im Feld »Name«, das Menü
  (z. B. »Zertifiziert« oder »Veggie«) im Buchungstext und der Name des Kindes
  im Verwendungszweck. Mehrere Kinder werden automatisch erkannt.
- **Zukünftige Bestellungen als vorgemerkte Umsätze.** Bestellungen ab morgen
  erscheinen als vorgemerkt, Bestellungen bis einschließlich heute als gebucht.
- **Preis pro Bestellung.** Das Portal zeigt keine Preise. Der Preis kommt aus
  dem Konto-Attribut `pricePerOrder` (Standard `3.00`), das in den
  Kontoeinstellungen von MoneyMoney geändert werden kann. Eine Änderung wirkt
  auf die Umsätze ab dem nächsten Abruf; bereits importierte Umsätze bleiben
  unverändert.

Beim ersten Abruf werden Bestellungen der letzten 10 Jahre geladen, danach
jeweils ab dem letzten Abruf bis 10 Wochen in die Zukunft.

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

- Guthaben-Aufladungen als Habenbuchungen.
- Preis-Historie bei Preisänderungen.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
