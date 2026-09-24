# GEG Gastro für MoneyMoney

Eine [MoneyMoney](https://moneymoney.app)-Erweiterung, die das Guthaben und die
Essensbestellungen aus dem Bestellportal von GEG Gastro
(<https://www.bestellung-geggastro.de>) abruft.

Das Portal bietet keine Schnittstelle. Die Erweiterung meldet sich mit den
Zugangsdaten des Kundenkontos an und liest die Seite »Bestellübersicht« aus.

## Was die Erweiterung liefert

- **Ein Konto** pro Portal-Login mit dem aktuellen Guthaben als Saldo.
- **Ein Umsatz pro Bestellung.** Das Essen steht im Feld »Name« (einzeilig,
  Gänge mit »|« getrennt), das Menü (z. B. »Zertifiziert« oder »Veggie«) im
  Buchungstext und der Name des Kindes im Verwendungszweck. Mehrere Kinder
  werden automatisch erkannt.
- **Zukünftige Bestellungen als vorgemerkte Umsätze.** Bestellungen ab morgen
  erscheinen in MoneyMoney als vorgemerkt, Bestellungen bis einschließlich
  heute als gebucht.
- **Preis pro Bestellung.** Das Portal zeigt keine Preise. Der Preis kommt aus
  dem Konto-Attribut `pricePerOrder` (Standard `3.00`), das in den
  Kontoeinstellungen von MoneyMoney geändert werden kann. Der Preis gilt für
  alle Umsätze, die beim nächsten Abruf geliefert werden. Bereits importierte
  ältere Umsätze werden nicht neu bewertet. Eine Preis-Historie gibt es nicht.

## Abrufzeitraum

- Beim ersten Abruf werden Bestellungen der letzten 10 Jahre geladen.
- Danach wird ab dem letzten erfolgreichen Abruf (minus 7 Tage Überlappung)
  bis 10 Wochen in die Zukunft geladen. MoneyMoney verwirft bereits bekannte
  Umsätze als Duplikate.
- Fordert MoneyMoney einen früheren Zeitpunkt an, wird dieser verwendet.

## Installation

1. `GEG-Gastro.lua` in den Erweiterungsordner von MoneyMoney kopieren:
   `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
   (in MoneyMoney über »Hilfe« → »Zeige Datenbank im Finder« erreichbar).
2. Solange die Erweiterung nicht von MoneyMoney signiert ist, unter
   »MoneyMoney« → »Einstellungen« → »Erweiterungen« die Option
   »Digitale Signatur von Extensions überprüfen« deaktivieren.
3. In MoneyMoney »Konto« → »Konto hinzufügen« → »Andere« → »GEG Gastro«
   wählen und die Zugangsdaten des Portals eingeben.

Zur Entwicklung verlinkt `./link_ext.sh` die Datei per Hardlink in den
Erweiterungsordner. Fehler und Statusmeldungen zeigt MoneyMoney unter
»Fenster« → »Protokollfenster«.

## Tests

Die Parser laufen offline unter LuaJIT gegen synthetische HTML-Fixtures in
`test/fixtures/`. Die Fixtures enthalten keine echten Daten.

```sh
brew install luajit luarocks
luarocks --lua-version=5.1 install xmlua
test/run.sh
```

Echte, aus dem Portal gespeicherte Seiten gehören nicht ins Repository
(`test.html` und `test/pages/` sind in `.gitignore`).

## Nicht enthalten

- Guthaben-Aufladungen als Habenbuchungen.
- Preis-Historie bei Preisänderungen.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
