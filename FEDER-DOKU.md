# Feder – Projektdokumentation

Feder ist ein Fork von [Saber](https://github.com/saber-notes/saber) (GPL-3.0) für Android.
Dieses Dokument ist die gemeinsame Gedächtnisstütze über Chat-Sitzungen hinweg.
Jede Aussage ist als **Fakt** (im Code/Build geprüft), **Vermutung** oder **Unsicher** gekennzeichnet.

## 1. Entscheidungen

| Datum | Entscheidung |
|---|---|
| 2026-11-23 | Fork behalten, kein Neubau. Gründe: Zeichenkern, PDF, Sync existieren und laufen; ein Neubau hätte lange keine testbare Basis. |
| 2026-11-23 | Name **Feder**, applicationId `de.luckykvd.feder`. Der frühere Arbeitsname war wegen Verwechslungsgefahr mit Samsung-Produktnamen ungeeignet und ist entfernt. Der Name ist ein Arbeitsname und jederzeit änderbar (vor der ersten Installation kostenlos). |
| 2026-11-23 | Fork läuft parallel zu Saber (andere applicationId). Saber-Notizen werden **kopiert importiert**, die Originale bleiben unverändert. |
| 2026-11-23 | Eigener Nextcloud-Ordner für Feder. Der Saber-Ordner wird nie beschrieben. |
| 2026-11-23 | Schutzziele der lokalen Verschlüsselung: Verlust/Diebstahl des Geräts, Zugriff anderer Apps, USB-Zugriff. |
| 2026-11-23 | Neues Aussehen (Symbol, Farben, Startseite, Notizbuch-Regal) kommt gesammelt in Phase 5. Stil: gezeichnete Schreibfeder, Nachtblau und Gold, eigenes Original-Symbol. |
| 2026-11-23 | Startseite zeigt die Zeile "Idee & Veränderung: LuckyKvD · Ausführung: Claude" und darunter den Saber-Urhebervermerk (GPL-3.0, darf nicht entfallen). Bauteil: `lib/components/home/credits_line.dart`. |
| 2026-11-23 | Handballe: Es bleibt bei "Stift erkannt → Fingerzeichnen aus" (wie Saber). Der Zwei-Pointer-Zweig in `isDrawGesture` wird trotzdem geprüft. |

## 2. Stand der Basis (Phase 0)

- **Fakt:** Basis ist Saber v1.37.2 (`d9a8a15`), Flutter 3.50, Dateiformat `sbnVersion = 19` (BSON-Container `.sbn2` plus Assets `.sbn2.N`).
- **Fakt:** Dateien mit höherer Versionsnummer öffnet Saber nur lesend. Feder-Notizen im Format 20 sind für Saber daher schreibgeschützt. Das ist gewollt.
- **Fakt:** Das Original enthielt `android/fallback-key.jks` samt Passwörtern öffentlich im Repo, und der frühere Build-Workflow hat damit signiert. Beides ist entfernt. Die zwei Test-APKs vom 17.11. waren mit diesem öffentlichen Schlüssel signiert und dürfen nicht installiert bleiben.
- **Fakt:** `allowBackup="false"` ist im Manifest gesetzt. Notizen liegen standardmäßig im app-privaten Ordner (`getApplicationDocumentsDirectory`). Ein benutzerdefinierter Datenordner (`customDataDir`) ist möglich und würde die Notizen aus dem geschützten Bereich nehmen. Für Feder wird diese Option geprüft und voraussichtlich gesperrt.
- **Fakt:** Es gibt keine App-Sperre und keine lokale Verschlüsselung.
- **Fakt (Nextcloud-Verschlüsselung in Saber):** fester Salt im Quelltext, Schlüssel = einmaliges SHA-256 aus Passwort + Salt, ein IV pro Konto für alle Dateien. **Unsicher:** der AES-Modus (Standard des `encrypt`-Pakets) ist noch nicht verifiziert. Das wird vor Phase 4 geklärt.
- **Fakt:** Zielgerät Galaxy Tab Active5: Exynos 1380, Mali-G68 MP5, 8" 1920×1200 TFT bis 120 Hz, 6 oder 8 GB RAM (256-GB-Variante: 8 GB).

## 3. Sicherheitskonzept (Entwurf, Phase 2 und 4)

- **App-Sperre:** Biometrie mit Geräte-PIN als Rückfall; Sperre beim Wechsel in den Hintergrund; Inhalt in der App-Übersicht verbergen. **Unsicher:** Paket `local_auth` muss vor dem Einbau auf pub.dev geprüft werden (Version, Lizenz, Pflegezustand).
- **Lokale Verschlüsselung:** Notizdatei, Anhänge, Vorschaubilder und Caches werden verschlüsselt abgelegt, Schlüssel im Android-Keystore, Freigabe nach Biometrie. Wiederherstellungsschlüssel wird dem Nutzer einmalig angezeigt und offline gesichert (Schlüsselverlust sonst = lokaler Datenverlust).
- **Nextcloud (neu):** eigenes Verfahren mit authentifizierter Verschlüsselung, Zufallswert pro Datei und echter Schlüsselableitung. Das alte Saber-Verfahren wird nur **lesend** für den Import unterstützt.
- **Vermutung:** Der Import aus Saber läuft über dessen Nextcloud-Ordner (nur lesen), weil eine App den privaten Ordner einer anderen App nicht lesen kann.

## 4. Signing (einmalig einzurichten, durch Kay)

Ohne diese Schritte baut der Workflow bewusst nicht (kein Fallback-Key).

**Warum zuerst offline erzeugen?** Das Repo ist öffentlich. Artefakte öffentlicher Repos kann jeder angemeldete GitHub-Nutzer herunterladen. Der Schlüssel darf deshalb weder im Repo noch als Artefakt liegen.

### 4.1 Schlüssel erzeugen (Windows-PC, z. B. Asus Flow Z13)

1. Windows-Taste drücken, "PowerShell" tippen, **Windows PowerShell** öffnen.
2. Java suchen: `winget search openjdk` und die Zeile **Microsoft.OpenJDK** mit der höchsten Zahl merken (Unsicher: genaue Paketnummer ändert sich).
3. Installieren, z. B.: `winget install Microsoft.OpenJDK.21` (Nummer aus Schritt 2 einsetzen). PowerShell danach schließen und neu öffnen.
4. Eigenen Ordner anlegen und hineinwechseln: `mkdir $HOME\feder-key; cd $HOME\feder-key`. (Nicht in "Dokumente": Der Windows-Ransomware-Schutz kann dort das Schreiben durch Java blockieren, Meldung `FileNotFoundException`.)
5. Schlüssel erzeugen (Passwort nur aus Buchstaben und Ziffern, mindestens 16 Zeichen; Passwortmanager nutzen):
   `keytool -genkeypair -v -keystore feder-release.jks -alias feder -keyalg RSA -keysize 4096 -validity 10000`
6. Auf die Fragen antworten (Name, Ort usw. frei, "Ja" zum Bestätigen). Beim Schlüsselpasswort einfach Enter (gleiches Passwort).
7. Datei `feder-release.jks` und das Passwort **sofort doppelt offline sichern** (Passwortmanager als Anhang plus USB-Stick). **Ohne diese Datei sind keine Updates über die installierte App möglich.**

### 4.2 Secrets in GitHub eintragen

1. Fork `LuckyKvD/saber` auf github.com öffnen, **Settings → Secrets and variables → Actions → New repository secret**.
2. Drei Secrets anlegen:
   - `FEDER_KEYSTORE_PASSWORD` = dein Passwort
   - `FEDER_KEY_ALIAS` = `feder`
   - `FEDER_KEYSTORE_BASE64` = Ausgabe von diesem PowerShell-Befehl (landet in der Zwischenablage):
     `[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path .\feder-release.jks).Path)) | Set-Clipboard` (im selben Ordner wie die Datei ausführen)
3. Danach in **Actions → Feder Android APK → Run workflow** (Branch `feder`).

## 5. Backup deiner Saber-Daten (vor der ersten Installation von Feder)

**Fakt:** Saber hat keine Backup-Funktion in den Einstellungen (Suche im Code ohne Treffer). Die Notizen liegen app-privat und sind ohne Root nicht kopierbar. Feder wird Saber **nicht** verändern. Das Risiko liegt also beim Gerät, nicht bei der Installation. Trotzdem:

1. In Saber prüfen, ob der Nextcloud-Sync aktiv und aktuell ist (Einstellungen → Nextcloud, kein offener Sync-Fehler). **Vermutung:** Das ist deine vollständige Sicherung.
2. In der Nextcloud-Weboberfläche den Saber-Ordner als ZIP herunterladen und offline ablegen. Die Dateinamen sind dort verschlüsselt, lesbar nur mit Saber und deinem Verschlüsselungspasswort. **Dieses Passwort gehört in deinen Passwortmanager.**
3. Von den 5 wichtigsten Notizen zusätzlich eine PDF-Kopie exportieren.
4. Feder installieren erst, nachdem 1 und 2 erledigt sind.

## 6. Phasen

| Phase | Inhalt | Status |
|---|---|---|
| 0 | Analyse und Machbarkeit | erledigt |
| 1 | Fundament: Name, Signing, Workflow, Doku | abgeschlossen (Build grün, Test auf Tab Active 5 bestanden) |
| 2 | App-Sperre (Biometrie/Geräte-PIN, FLAG_SECURE) | abgeschlossen, auf Tab Active 5 getestet, in `feder` |
| 3 | Eingabe: Stift-Priorität, Druckkurve, Strichradierer | 3a Druckkurve gebaut (Branch `feature/pressure-curve`, Build grün, Test offen). Offen: Teilstrich-Radierer, Prüfung Handfläche+Stift |
| 4 | Neue Verschlüsselung, lokale Verschlüsselung, Format 20, Import als Kopie | offen |
| 5 | Notizbuch, Deckblatt, Vorlagen, Seitenübersicht | offen |
| 6 | Lasso mit Skalieren/Drehen, Bilder über Seiten, PDF-Import härten | offen |
| 7 | Lineal, Dekoband, Schreibfeld, A4-Export, Druck, Härtetest | offen |

## 7. Lizenz (GPL-3.0)

- Der Quelltext von Feder bleibt GPL-3.0; Lizenztext und Urheberhinweise von Saber (Adil Hanney und Mitwirkende) bleiben erhalten.
- **Vermutung (keine Rechtsberatung):** Gibst du eine APK an Dritte weiter, musst du denen auf Anfrage den vollständigen Quelltext (deinen Fork) unter GPL-3.0 bereitstellen. Der öffentliche Fork erfüllt das. Für die private Nutzung auf eigenen Geräten ergibt sich keine Pflicht.
- Der Name "Saber" und das Original-Logo gehören dem Originalprojekt. Vor einer Weitergabe prüfe ich App-Icon und Texte auf Reste.
- Der in dieser Phase gesetzte App-Titel ist "Feder"; das Icon ist noch das von Saber (offen).

## 8. Bekannte Fehler und offene Punkte

- App-Icon und Texte enthalten noch Saber-Reste (Phase 7).
- Samsung-Mehrfenster und Manifest-Attribute nicht geprüft.
- AES-Modus der Saber-Nextcloud-Verschlüsselung nicht verifiziert.

## 9. Technische Notizen Phase 2 und 3

- App-Sperre: `lib/components/security/app_lock.dart`, Pref `appLockEnabled`, Karenzzeit 30 s, MethodChannel `de.luckykvd.feder/secure` (FLAG_SECURE) in `MainActivity.kt`. Pakete: `local_auth 3.0.2`, `local_auth_android 2.3.0` (Fakt, Build-Log). **Unsicher:** Paketlizenz (vermutlich BSD-3) vor Weitergabe prüfen.
- Die Sperre schützt nicht die Dateien (siehe Abschnitt 3, lokale Verschlüsselung folgt in Phase 4).
- Druckkurve: `lib/data/pressure_curve.dart`, Pref `pressureCurve` (Prozent, 100 = normal), Formel `druck^(prozent/100)`, angewendet in `canvas_gesture_detector.dart`. Dateiformat unverändert; gespeichert wird der bereits gekrümmte Druck. Wirkt nur bei Werkzeugen mit Druckauswertung (Füller), nicht beim Kugelschreiber. Pro-Stift-Kurve ist noch nicht umgesetzt.
- Workflow: Analyze prüft nur `lib/` und bricht bei Fehlern ab.


## 10. Prototyp Kalligrafie-Feder (Branch `feature/calligraphy`)

- Neuer Stift „Kalligrafie-Feder“ (Federspitze flach, fester Winkel, einstellbar in den Einstellungen: 15–75°). Linienbreite hängt von der Strichrichtung ab, nicht vom Druck.
- Gespeichert als Füller (`ty = fountainPen`) plus Zusatzschlüssel `na` (Winkel). Original-Saber ignoriert `na` und zeigt eine einfache Linie. **Nur Testdaten – sauberes Format folgt in Phase 4 (Format 20).**
- Neu: Einstellung „Druckempfindlichkeit des Füllers“ (`thinning`: Keine / Normal 50 / Stark 75 / Maximal 95).
- Bekannte Risiken (Vermutung): PDF-Export mehrerer Teilpfade, Leistung bei sehr langen Strichen auf dem Tab Active 5.

- **Testergebnis (Kay, 24.11.2026):** Winkel, Strichbild, Druckempfindlichkeit und Latenz gut (auch lange Striche); Linkshänder- und Rechtshänder-Test (Ehefrau) ok; PDF-Export der Kalligrafie-Striche gefüllt und vollständig (Testseite PDFTestFeder.pdf). Prototyp damit bestanden.
- **Wunsch für Phase 5 (GUI):** Stift-Einstellungen (Federwinkel, Druckempfindlichkeit u. a.) direkt im Dokument erreichbar machen (Stift-Leiste), nicht nur in den Einstellungen. Dazu gehört: Einstellungen pro Stift speichern, Kalligrafie-Feder nach Neustart wiederherstellen.

## 11. Teilstrich-Radierer (Branch `feature/stroke-eraser`)

- Einstellung „Radierer löscht nur berührten Teil“ (Standard: aus = altes Verhalten, ganze Linie). Bei „an“ wird der Strich an der Radierstelle aufgetrennt (Radius = Radierergröße).
- Undo/Redo: ein Radierzug = ein Schritt (`HistoricReplace`). Formen (Kreis/Rechteck aus dem Form-Stift) werden weiter ganz gelöscht.
- Kalligrafie-Striche behalten beim Teilen ihren Federwinkel.
- Offen (Vermutung): Bei sehr schnellem Radieren können kleine Reste stehen bleiben; Radiergröße jetzt einstellbar (Fein 5 … Riesig 60, Standard 10).
- Test Teilstrich-Radierer (Kay, 24.11.2026): alle Tests erfolgreich; Wunsch Radiergröße einstellbar umgesetzt. Spätere GUI: Größe direkt in der Radierer-Leiste.
