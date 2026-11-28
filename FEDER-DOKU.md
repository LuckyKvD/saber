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

## 4. Signing (einmalig einzurichten, durch den Projektinhaber)

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

- **Testergebnis (Test):** Winkel, Strichbild, Druckempfindlichkeit und Latenz gut (auch lange Striche); Linkshänder- und Rechtshänder-Test ok; PDF-Export der Kalligrafie-Striche gefüllt und vollständig. Prototyp damit bestanden.
- **Wunsch für Phase 5 (GUI):** Stift-Einstellungen (Federwinkel, Druckempfindlichkeit u. a.) direkt im Dokument erreichbar machen (Stift-Leiste), nicht nur in den Einstellungen. Dazu gehört: Einstellungen pro Stift speichern, Kalligrafie-Feder nach Neustart wiederherstellen.

## 11. Teilstrich-Radierer (Branch `feature/stroke-eraser`)

- Einstellung „Radierer löscht nur berührten Teil“ (Standard: aus = altes Verhalten, ganze Linie). Bei „an“ wird der Strich an der Radierstelle aufgetrennt (Radius = Radierergröße).
- Undo/Redo: ein Radierzug = ein Schritt (`HistoricReplace`). Formen (Kreis/Rechteck aus dem Form-Stift) werden weiter ganz gelöscht.
- Kalligrafie-Striche behalten beim Teilen ihren Federwinkel.
- Offen (Vermutung): Bei sehr schnellem Radieren können kleine Reste stehen bleiben; Radiergröße jetzt einstellbar (Fein 5 … Riesig 60, Standard 10).
- Test Teilstrich-Radierer (Test): alle Tests erfolgreich; Wunsch Radiergröße einstellbar umgesetzt. Spätere GUI: Größe direkt in der Radierer-Leiste.

- **Handflächen-Test (Test):** Handfläche aufgelegt + Stift: keine Probleme, keine Latenz. Kein Code nötig. Phase 3 damit abgeschlossen.

## 12. Phase 4 – Befund Saber-Verschlüsselung (Code gelesen, 24.11.2026)

- Fakt (Code): `Encrypter(AES(passwordKey))` ohne Modusangabe; Schlüssel = einmal SHA-256(Passwort + festes Salz im Quelltext); ein IV pro Konto, für alle Dateien wiederverwendet; der Dateischlüssel (`key`) wird mit demselben IV in `config.sbc` abgelegt.
- Vermutung (Standard des `encrypt`-Pakets, vor Umsetzung gegen Paketquelltext zu prüfen): Standardmodus ist `AESMode.sic` (CTR-artig) – dann ohne Authentifizierung und mit Schlüsselstrom-Wiederverwendung: aus zwei verschlüsselten Dateien lässt sich die XOR-Verknüpfung der Klartexte gewinnen; Manipulation wäre unbemerkt.
- Folge: Feder bekommt ein eigenes Schema (authentifizierte Verschlüsselung, eigenes Nonce pro Datei, echte Schlüsselableitung mit Zufalls-Salt) im eigenen Nextcloud-Ordner. Das alte Schema bleibt nur lesend für den Import aus dem Saber-Ordner.

## 13. Entscheidungen Phase 4 (Test)

- Wiederherstellungsschlüssel beim Einrichten der Verschlüsselung: **ja**.
- Nextcloud-Server: privat gehostet, nur für eigene Tests (keine Server-Adresse und keine Zugangsdaten im Repo).
- Lokale Verschlüsselung: **nach** der Nextcloud-Verschlüsselung.
- Quantencomputer-Sicherheit: umgesetzt über AES-256 bzw. XChaCha20-Poly1305 mit 256-Bit-Schlüsseln und Argon2id; keine asymmetrische Kryptografie in Feder nötig.
- Wunsch: allgemeine WebDAV-Anbindung (Nextcloud, IONOS HiDrive, Synology …); pCloud zunächst per WebDAV (EU: `ewebdav.pcloud.com`, nur Bezahltarif, ohne 2FA); natives pCloud-API später nur falls nötig.

## 14. Schritt 2: eigener Nextcloud-Ordner + Tresor (Branch `feature/crypto`)

- Server-Ordner: `Feder/` (der Ordner `Saber/` wird nie berührt). Tresor-Datei `Feder/feder-vault.json` (nur eingepackter Schlüssel + Argon2id-Parameter + Salz; ohne Passwort wertlos).
- Dateien: `<verschlüsselter Name>.fde`; Dateiname = deterministisch verschlüsselter Pfad (authentifiziert, Base32 klein), Inhalt mit XChaCha20-Poly1305, Pfad als zugehörige Daten.
- Lokal gespeichert wird nur der Hauptschlüssel (sicherer Speicher); das Passwort nie. Der „Login mit Saber-Server“ wurde entfernt.
- Einrichtung: Passwort (min. 12 Zeichen) → Wiederherstellungsschlüssel anzeigen → erst nach Bestätigung wird der Tresor hochgeladen.
- Bekannte Grenzen (Vermutung/Unsicher): gleichzeitige Ersteinrichtung auf zwei Geräten (wird per Prüfung vor dem Upload abgefangen, aber nicht atomar); Passwortwechsel noch ohne Oberfläche; Dateien werden im Hauptprozess ver-/entschlüsselt (große PDFs könnten kurz ruckeln); Pfadlänge: sehr lange Pfade können das 255-Zeichen-Limit der Dateinamen sprengen.

- **Test Schritt 2 (Test):** Anmeldung, Tresor, Wiederherstellungsschlüssel, Sync nach `Feder/` ok. Reines Dart-Argon2id brauchte >20 Minuten auf dem Tab Active 5; ersetzt durch Argon2id in Java (BouncyCastle 1.78.1, MethodChannel `de.luckykvd.feder/crypto`) – danach „rasend schnell“, bestehender Tresor blieb entsperrbar (Dart und Java liefern dasselbe Ergebnis). Speicherplatz-Anzeige lädt jetzt beim Öffnen. Krypto-Schritte 1+2 in `feder` übernommen.

## 15. Import aus Saber (Branch `feature/saber-import`, in `feder` übernommen)

- Ablauf: Einstellungen → Import aus Saber. Passwort des alten Saber-Kontos eingeben; Feder liest `Saber/config.sbc` und die `.sbe`-Dateien **nur lesend** und legt Kopien unter `Import aus Saber/` an. Danach laufen sie wie alle Notizen durch den Feder-Sync (verschlüsselt nach `Feder/`). Lokale Kopien sind (wie bei Saber) unverschlüsselt; lokale Verschlüsselung folgt später.
- Bereits vorhandene Dateien werden übersprungen (Wiederholung ist ungefährlich). 0-Byte-Dateien (in Saber gelöscht) werden ignoriert.
- Der Sync-Kreis oben rechts zeigt jetzt auch Uploads (vorher nur Downloads).
- **Befund defekte Quelldateien (Fakt):** Einzelne Dateien im alten Saber-Ordner sind auf dem Server abgeschnitten (Dateikopf nennt größere Länge als vorhanden; Größe glatt durch 4096 teilbar). Das ist kein Feder-Fehler. Der Import meldet sie mit Größe, Kopfwert und letztem Byte; Notizen daraus müssen aus der lokalen Saber-Kopie exportiert und per „+“ → Import übernommen werden (Unsicher, ob inklusive Bildern vollständig). Vorschaubilder (`.p`) werden von der App neu erzeugt (Vermutung).
- **Offener Prüfpunkt:** Schneidet der Server große Uploads ab? Test: Größe einer großen `.fde`-Datei = lokale Größe + 44 Byte.
- **Wunsch Phase 5:** Statt des Fortschrittskreises eine Prozentanzeige; die Anzeige braucht einen eigenen Takt, weil sie sich bisher nur bei Änderungen der Warteschlange oder beim Neuaufbau der Seite aktualisiert (Vermutung).

## 16. Lokale Verschlüsselung (Branch `feature/local-crypto`, in `feder` übernommen)

- **Umfang Stufe 1:** Notizdateien (`.sbn2`, `.sbn`), Vorschaubilder (`.sbn2.p`) und Anhänge (`.sbn2.N`: Fotos, SVG, PDF). Nicht verschlüsselt: Ordnerstruktur und Dateinamen (Klartext im App-Ordner), Einstellungen.
- **Format:** `FDL1` + 24 Byte Nonce + Chiffretext + 16 Byte MAC (XChaCha20-Poly1305). Schlüssel per HKDF (`feder-local-file-v1`) aus dem Hauptschlüssel, getrennt vom Sync-Schlüssel. Pfad wird nicht gebunden (Umbenennen/Verschieben bleibt möglich).
- **Wann:** Beim Schreiben (`FileManager.writeFile`), sobald der Schlüssel vorliegt. Lesen über `FileManager.readBytes` (entschlüsselt bei Bedarf, liest Klartext-Altdateien unverändert). Bilder über `DecryptedFileImage`, PDFs aus dem Speicher, SVGs als String.
- **Automatische Umwandlung** beim Start nach der Anmeldung (`LocalMigration.encryptAll`): Zwischendatei, Rücktest, atomares Umbenennen, Zeitstempel bleibt erhalten, Änderung während der Umwandlung führt zum Überspringen. Fortschritt im Durchsuchen-Bildschirm.
- **Abmelden** entschlüsselt vorher alles (zwei Durchläufe); schlägt eine Datei fehl, wird nicht abgemeldet.
- **Anzeige:** Einstellungen → „Lokale Verschlüsselung" zählt verschlüsselte/unverschlüsselte Dateien; Antippen verschlüsselt Rest.
- **Tests (Praxis):** Altdaten wurden automatisch verschlüsselt (Geschwindigkeit ok), Anzeige und Import ok, Foto-/PDF-/SVG-Anzeige ok.
- **Offen/Grenzen (Vermutung/Unsicher):** Geht der Hauptschlüssel verloren (Gerät zurückgesetzt) und fehlen Passwort und Wiederherstellungsschlüssel, sind lokale Daten und die Nextcloud-Kopie nicht lesbar – so gewollt. Reines Dart-XChaCha20 im Hintergrund-Isolate; sehr große Dateien (> 50 MB) ungetestet. Dateinamen sind lokal und in Statusmeldungen lesbar.

## 17. Stand 26.11.2026 (in `feder` übernommen: Regale, Blättern, Stifte, Widget)

Zusammengeführte Zweige: `feature/regal`, `feature/blaettern`, `feature/widget`.

- **Regale und Sync:** Regal verschieben/umbenennen meldet dem Sync die alten Pfade; vorgemerkte Löschungen (`fileSyncPendingDeletes`) verhindern das Zurückladen. Löschungen auf dem Server sind 0-Byte-Dateien („Löschmarken“). Einstellungen → „Server aufräumen“ löscht sie nach Rückfrage (nur sicher, wenn alle Geräte synchron sind; `feder-vault.json` bleibt unangetastet).
- **Blättern:** horizontales Blättern mit Umblätter-Effekt, Quermodus (Seite füllt die Breite, senkrecht scrollbar), Werkzeugleiste ausblendbar. Schnelleres Laden durch eigenen BSON-Leser (`fast_bson.dart`).
- **Stifte:** Bleistift im Stiftmenü; Pinsel, Fineliner (harte, eckige Linie), Muster-Stift (gestrichelt, Punkte, Sterne, Herzen, Kreuze, Ausrufezeichen, Doppelstriche, Pfeile), Glitzer (Regenbogen oder einfarbig), gerader Textmarker, Text-Stempel (als Bild, frei skalierbar). Jeder Stift merkt sich seine letzte Farbe. Neue Strichstile werden als Zusatzschlüssel `ps` gespeichert; ältere Versionen zeigen eine normale Linie.
- **Hilfsmittel:** Lineal und Winkelmesser wechseln beim Loslassen auf die Nachbarseite; das Schreibfeld darf über den Seitenrand gezogen werden.
- **Werkzeugleiste:** gestrafft; „Hilfsmittel“ und „Mehr“ sind Aufklappmenüs.
- **Widget „Schnellnotiz“:** gelber Zettel mit roter Nadel (Farbe wählbar). Ein Tipp öffnet die feste Notiz `/Schnellnotiz`. Die Vorschau (erste Seite) liegt unverschlüsselt im privaten App-Speicher und ist auf dem Startbildschirm sichtbar; abschaltbar in den Einstellungen (löscht sie sofort).
- **Offen:** SVG-Export der Muster-Zeichen (nur normale Linie), Doppelseite im Quermodus, dauerhafte Stempel-Bilder, mehrere Seiten im Widget, Saber-Upstream-Update prüfen.

## 18. Aufgaben aus Handschrift (Branch `feature/aufgaben`, Stand 26.11.2026)

- **Ablauf:** Lasso um die handgeschriebene Aufgabe → „Als Aufgabe“ in der Auswahlleiste → Bestätigungsfenster (Text korrigieren, Liste wählen, Fälligkeit) → Aufgabe landet per CalDAV (VTODO) direkt auf dem eigenen Nextcloud-Server. Es läuft nichts über Fremddienste.
- **Erkennung:** Googles ML Kit „Digital Ink Recognition“ (Android, nativ in `InkRecognizer.kt`, Kanal `de.luckykvd.feder/ink`). Die Erkennung läuft auf dem Gerät; nur das deutsche Sprachmodell (ca. 20 MB) wird einmalig geladen (Internet nötig). Gelesen werden die Strichdaten, nicht ein Bild. Textmarker und Klebeband zählen nicht mit.
- **Fälligkeit:** Pflichtfeld. Aus dem Text abgeleitet (`due_date_parser.dart`: heute, morgen, übermorgen, Wochentage, „in 2 Wochen“, Monatsende, 15.12., 15. Dezember, Uhrzeiten), immer zur Kontrolle sichtbar. Tests: `test/due_date_parser_test.dart`.
- **Liste:** wird jedes Mal gewählt (letzte Wahl nur als Vorauswahl). Gefunden werden alle Kalender, die Aufgaben erlauben.
- **Kein Bildanhang:** Ein Anhang mit dem Handschrift-Bild wurde probiert und wieder entfernt (funktionierte nicht, wird nicht gebraucht). Es geht nur der Text an Nextcloud.
- **Grenzen (Vermutung/Unsicher):** Erkennungsqualität bei Schreibschrift ist erst im Praxistest bekannt; mehrzeilige Auswahl wird schlechter gelesen als eine Zeile. Die Google-Bibliothek ist proprietär (für Privatgebrauch unkritisch; bei einer Weitergabe von Feder lizenzrechtlich zu klären).


### 18a. Termine und Kontakte (Branch `feature/aufgaben`)
- Lasso-Auswahl → Menü „An Nextcloud" → Aufgabe / Termin / Kontakt. Die Handschrifterkennung läuft wie bei Aufgaben auf dem Gerät.
- Termin: Kalender wird jedes Mal gewählt (letzte Wahl vorbelegt), Datum und Uhrzeit aus dem Text vorgeschlagen, Ende standardmäßig +1 Stunde, optional ganztägig. Speicherung per CalDAV (VEVENT, Zeiten als UTC).
- Kontakt: Name, Telefon und E-Mail werden aus dem Text vorbelegt (zum Korrigieren), Adressbuch wird gewählt. Speicherung per CardDAV (vCard 3.0).
- Automatisch erzeugte Sammlungen (Geburtstage, Papierkorb) werden nicht angeboten.

### 18b. Whiteboard entfernt (27.11.2026)
- Die Whiteboard-Seite, ihre Einstellung ("automatisch löschen") und die zugehörige Logik sind entfernt. Der Dateipfad `/_whiteboard` bleibt nur als reservierter Name, damit eine alte Whiteboard-Datei nicht im Regal auftaucht.

## 19. Mathe-Solver (Branch `feature/mathe`, Stand 27.11.2026)
- Lasso-Auswahl → „Rechnen". Die Handschrift wird wie bei Aufgaben auf dem Gerät gelesen (ML Kit), danach rechnet ein eigener Rechner in Dart. Nichts verlässt das Gerät.
- Kann: + − · ÷ ^, Klammern, √, Dezimalzahlen (Komma/Punkt), Brüche exakt, Gleichungen mit einer Unbekannten bis x² mit Rechenweg und Probe (linear).
- Grenzen: Die Texterkennung liest keine Formelschrift (Brüche mit Strich, Hochzahlen oben, Integrale). Deshalb Schreibweise mit Zeichen: `3x+5=20`, `x^2-4=0`, `(12+8)*3/4`. Das erkannte Ergebnis lässt sich im Fenster korrigieren, das Ergebnis wird live neu gerechnet.
- Tests: `test/math_solver_test.dart`.
- Ergebnis schreiben: Im Fenster „In Notiz schreiben" setzt das Ergebnis in Handschrift-Optik (Schrift Neucha, Farbe der Aufgabe) rechts hinter die Aufgabe, bei Platzmangel darunter. Es ist ein verschiebbares Bild und mit Rückgängig entfernbar. Ein schlecht gelesenes Gleichheitszeichen am Ende der Aufgabe wird ignoriert.

## 20. Tabellen (Branch `feature/tabelle`, Stand 27.11.2026)
- Einfügen: ⋮-Menü → „Tabelle einfügen". Wahl von Spalten, Zeilen, Zellhöhe (1 / 1,5 / 2 / 3 Kästchen) und Zellbreite (2 / 3 / 4 / 6 Kästchen). Die Tabelle erscheint in der Bildmitte, am Kästchenraster ausgerichtet.
- Aussehen: Jede Linie ist ein normaler Strich im aktuellen Stift (Farbe, Dicke), leicht wellig und schief mit kleinem Überstand, damit sie handgezogen wirkt. Gespeichert mit Zusatzschlüssel `tb` (1 waagerecht, 2 senkrecht); ältere Versionen zeigen normale Linien.
- Schreiben: Zellen werden einfach mit dem Stift beschrieben (Handschrift), die Tabelle ist nur Rahmen.
- Erweitern: Lasso um die ganze Tabelle → „Tabelle" → Zeilen unten / Spalten rechts anfügen. Die Tabelle wird aus den markierten Linien erkannt, es gibt kein eigenes Tabellenobjekt. Inhalte werden dabei nicht verschoben; unter der Tabelle muss Platz sein.
- Grenzen: Sonderstifte (Glitzer, Muster, gestrichelt) werden für die Linien als normale Linie gezeichnet. Zeilen oder Spalten in der Mitte einfügen und einzelne Spaltenbreiten ziehen gibt es noch nicht.
- Lasso „Strichdicke und Größe" (Symbol Regler): markierte Striche dünner/dicker (±25 %) oder vergrößern/verkleinern (125 % / 80 %, Ankerpunkt oben links der Auswahl). Mit Rückgängig. Gilt für alle freien Striche, auch für Tabellen samt Inhalt; Bilder und Formstriche (Kreis, Rechteck) bleiben unverändert.
- Smartphone: Rückgängig und Wiederholen bleiben in der Werkzeugleiste sichtbar; die Knopfbreite wird gemessen, damit der ⋮-Knopf nicht abgeschnitten wird.

## 21. Notizvorlagen (Besprechung, Jour fixe)

- Im Editor: ⋮-Menü → **Vorlage einfügen** → *Besprechung* oder *Jour fixe*. Die Vorlage wird in die **geöffnete Notiz** an die sichtbare Stelle der aktuellen Seite gesetzt. Vorhandener Inhalt bleibt unberührt, es entsteht keine neue Notiz.
- Aufbau ohne neues Dateiformat: Beschriftungen als Handschrift-Bilder (Neucha), Schreiblinien und Tabellen als normale Striche (wie in Abschnitt 20). Alles ist danach frei bearbeitbar.
- Einfügen ist **ein** Rückgängig-Schritt. Passt ein Abschnitt nicht mehr auf die Seite, wird er weggelassen und ein Hinweis gezeigt.
- Layout in Kästchen-Einheiten (`lib/data/templates/note_templates.dart`), Tests: `test/note_templates_test.dart`.

## 22. Tabelle erweitern verschiebt Inhalt darunter

- Beim Erweitern um Zeilen (Lasso → Tabelle) wird alles, was unterhalb der Tabelle liegt, um die neue Höhe nach unten geschoben (eigener Rückgängig-Schritt).
- Grenzen: es zählt die ganze Seitenbreite unterhalb der Tabelle; ragt Inhalt dadurch über das Seitenende, erscheint ein Hinweis (nichts geht verloren, liegt aber außerhalb).

## 23. Freie Stelle beim Einfügen

- Neue Tabellen und Vorlagen werden nicht mehr über vorhandenen Inhalt gesetzt: Der Editor sucht ab der gewünschten Stelle den nächsten freien Streifen auf der Seite (zuerst nach unten, dann nach oben). Gibt es keinen, bleibt es bei der gewünschten Stelle.
- Grund: Beim Lasso um eine Tabelle würde sonst der Text darunter mit ausgewählt und am Lassorand zerschnitten.
- Grenze: Prüfung nur nach Höhe (ganze Seitenbreite), nicht nach Fläche.

## 24. Tabelle vergrößern/verkleinern schiebt Inhalt mit

- Lasso → Regler → Verkleinern/Vergrößern: Enthält die Auswahl Tabellenlinien, wird der Inhalt unterhalb um die Höhenänderung nach unten bzw. oben mitgeschoben (eigener Rückgängig-Schritt).
- Skaliert wird um die linke obere Ecke der Auswahl. Inhalt neben der Tabelle (gleiche Höhe) bleibt stehen, was darunter liegt wandert über die ganze Seitenbreite.

## 25. Textbänder mit eigenen Texten

- Klebeband-Muster 11–15 sind „Textband 1–5": farbiges Band (blau, schwarz, dunkelrot, grün, violett) mit weißer, wiederholter Schrift.
- Die Texte werden in den Einstellungen („Texte für Textbänder") eingegeben und liegen nur lokal in den App-Einstellungen, nicht im Code und nicht im Repository. Leere Textbänder erscheinen im Stift-Menü nicht.
- Die Bandfarbe jedes Textbands wählst du im selben Dialog aus 12 Farben (nur lokal gespeichert).
- Der Text steht nicht im Strich: Ändert man ihn später, ändern sich alle bereits gezeichneten Bänder dieser Nummer. Alte Bänder mit festem Namen (frühere Muster 11/12) zeigen jetzt den Text von Textband 1 bzw. 2.

## 26. Fehlersuche Vorlagen (Doppellinien, verfälschtes Titelbild)

- Vorlagen-Linien nutzen jetzt immer einen festen Kugelschreiber-Strich, nicht mehr den aktuell gewählten Stift (Spezialstifte konnten Linien doppeln).
- Handschrift-Bilder (Vorlagen-Beschriftung, Mathe-Ergebnis) werden nach dem Rendern geprüft: Enthalten sie fremde Farben (Grafikspeicher-Reste), wird bis zu 4-mal neu gerendert. Test: `test/handwriting_pixels_test.dart`.
- Gemeinsamer Renderer `lib/data/images/safe_render.dart` (`renderInkPng`): wird von Handschrift-Bildern **und Text-Stempeln** genutzt, gibt Zeichnung und Bild immer frei und rendert bei fremden Farben neu.
- Beides ist eine Vermutung, die Ursache wurde nicht auf dem Gerät nachgestellt. Offen: Tritt der Fehler erst beim Anzeigen auf (Bytes sauber), hilft die Prüfung nicht.

## 27. Eigene Vorlagen

- Lasso-Auswahl → Lesezeichen-Symbol **„Als Vorlage speichern"** → Name vergeben (gleicher Name: Rückfrage zum Ersetzen). Gespeichert werden Striche (auch Tabellen, Linien, Formen) und PNG-Bilder (auch Handschrift-Beschriftungen) der Auswahl.
- Einfügen: ⋮ → **Vorlage einfügen** → Abschnitt „Eigene Vorlagen". Sie landet horizontal zentriert an der sichtbaren, freien Stelle der Seite (wie Abschnitt 23), ein Rückgängig-Schritt. Löschen über das Papierkorb-Symbol in der Liste (löscht auch auf den anderen Geräten).
- **Format:** Eine Vorlage ist eine normale Feder-Notiz (`.sbn2`) mit einer Seite im versteckten Ordner `/_Vorlagen` (`lib/data/templates/custom_templates.dart`). Daher gelten lokale Verschlüsselung und der Nextcloud-Abgleich (Ordner `Feder/_Vorlagen`) automatisch, ein Gerät sieht die Vorlagen der anderen nach dem nächsten Abgleich.
- Der Ordner `_Vorlagen` ist in Dateilisten, Verschieben-Dialog und Zuletzt-Liste ausgeblendet. „Alles neu synchronisieren" nimmt ihn mit.
- Erste Fassung (JSON-Datei, nur lokal) hat nicht funktioniert: Striche enthalten BSON-Binärdaten, die `jsonEncode` nicht schreiben kann.
- Grenzen: gedrehte Bilder verlieren die Drehung; SVG-/PDF-Bilder und nicht lesbare Bilder werden übersprungen (Hinweis). Text-Felder (Quill) gehören nicht zur Lasso-Auswahl.

## 28. Seitenübersicht als Vollbild-Raster

- Raster-Symbol in der Notiz-Leiste öffnet jetzt einen Vollbild-Bildschirm (`lib/components/toolbar/page_overview.dart`) statt des schmalen Dialogs.
- Miniaturen in 2–6 Spalten je nach Breite, Seitenzahl unter jeder Miniatur, aktuelle Seite farbig umrandet.
- Tippen springt zur Seite und schließt die Übersicht. Lang drücken und auf eine andere Miniatur ziehen sortiert um. Das Umsortieren ist ein Rückgängig-Schritt im Editor (`HistoricPageReorder`).
- „Auswählen": mehrere Seiten markieren, dann Kopieren/Verschieben in ein anderes Notizbuch, Duplizieren oder Löschen (Löschen mit Rückfrage, per Rückgängig im Editor wiederholbar). „+" fügt am Ende eine Seite ein.
- Der alte Dialog (`EditorPageManager`) bleibt im Code, wird aber nicht mehr geöffnet.
- Offen: Ob Fotos in Miniaturen von nicht sichtbaren Seiten sofort erscheinen, ist ungeprüft (Unsicher).

## 29. Handschrift-Suche (Branch `feature/handschrift-suche`)

- Lupe in der Startseiten-Leiste → Suchseite. Gesucht wird in Handschrift **und** getipptem Text aller Notizen. Treffer zeigen Notiz, Seite und die erkannte Zeile; Tippen öffnet die Notiz direkt auf der Seite (`/edit?path=…&page=N`).
- **Index:** Pro Notiz werden die Seiten gelesen. Striche werden anhand ihrer Lage zu Zeilen gebündelt (`LineGrouper`; Linien, Tabellen, Formen und große Zeichnungen werden übersprungen), jede Zeile wird mit der vorhandenen Handschrift-Erkennung (ML Kit, auf dem Gerät) gelesen. Gespeichert werden bis zu 3 Kandidaten je Zeile. Getippter Text kommt unverändert in den Index.
- **Aktualisierung:** Beim Öffnen der Suche werden nur neue oder geänderte Notizen (Änderungszeit) neu gelesen, gelöschte entfernt. Menü: „Index aktualisieren", „komplett neu aufbauen". Der erste Lauf kann bei vielen Notizen dauern; die Suche funktioniert währenddessen mit dem bisherigen Stand.
- **Unscharfe Suche** (`SearchText`): Umlaute/Akzente vereinfacht, Teilwörter und Wortanfänge, bei längeren Wörtern 1–2 Zeichen Abweichung (4 Zeichen und kürzer exakt). Alle Suchwörter müssen auf der Seite vorkommen.
- **Datenschutz:** Der Index liegt nur lokal im App-Ordner (`feder_suche/index.bin`), wird bei aktiver lokaler Verschlüsselung verschlüsselt, **nicht** mit Nextcloud abgeglichen und nicht im Repo. Jedes Gerät baut seinen eigenen Index. Der Ordner `_Vorlagen` wird nicht indexiert.
- **Grenzen (Vermutung/Unsicher):** Erkennungsqualität hängt an der Schrift; Fotos, PDF-Text und Handschrift-Beschriftungen als Bild (Vorlagen) werden nicht gelesen; erste Erkennung braucht einmalig Internet für das Sprachmodell.

### 29a. Hintergrund-Indexierung

- Nach dem Speichern einer Notiz wird nach 30 s Ruhe nur diese Notiz neu gelesen. Beim Start der App (nach 45 s) und beim Zurückkehren (nach 90 s) werden neue oder geänderte Notizen leise nachgezogen (eine Notiz nach der anderen, kurze Pausen).
- Alle Indexläufe (Suchseite, Speichern, Hintergrund) laufen nacheinander, nie gleichzeitig.
- Abschaltbar in den Einstellungen („Suchindex im Hintergrund pflegen"). Ohne Handschrift-Erkennung (nicht Android) bleibt es aus.
- Schnellnotiz wird nicht im Hintergrund indexiert.

## 30. Dateiformat .fba (Branch `feature/fba-format`)
- Export (Teilen, Export-Leiste, Startseite) erzeugt jetzt `.fba` statt `.sba`. Inhalt und Aufbau sind unverändert (Zip mit `main.sbn2` und Anhängen).
- Import liest `.fba`, `.sba`, `.sbn`, `.sbn2` (alte Saber-Dateien bleiben importierbar, nur als Kopie).
- Android-Doppeltipp („Öffnen mit“) ist nur noch für `.fba` auf Feder eingetragen, damit Saber seine eigenen Dateien behält, wenn beide Apps installiert sind. Teilen-an-Feder (SEND) akzeptiert weiterhin alle Typen.

## 31. Mehrere Textfelder, Textformatierung, Inhaltsverzeichnis (Branch `feature/textfelder-verzeichnis`)
- **Textfelder:** In der Textfunktion (Symbol „T“) ein Rechteck mit dem Stift aufziehen (mit eingeschaltetem Fingerzeichnen auch mit dem Finger); dort entsteht ein Textfeld, beliebig viele pro Seite. Zusätzlich gibt es links in der Leiste „Textfeld hinzufügen“. Der alte Seitentext oben links ist nur noch bei Notizen aktiv, die schon Text darauf haben. Das Feld lässt sich über den Griff oben links verschieben, über den Griff unten rechts in der Größe ändern und über das Kreuz oben rechts löschen. Alles ist rückgängig machbar. Der bisherige Seitentext bleibt unverändert erhalten (alte Notizen laden wie vorher).
- Speicherformat: pro Seite optionaler Schlüssel `tb` (Liste der Felder mit Position, Größe, Text). Alte Feder-/Saber-Versionen ignorieren ihn (Text der Felder ginge dort nicht verloren, würde aber nicht angezeigt).
- **Formatierung:** Schriftart, Größe, Farbe, Hintergrundfarbe, Überschriften, Aufzählung/Nummerierung, Ausrichtung inkl. Blocksatz, Durchstreichen, Format löschen, Suchen in der Textleiste.
- **Inhaltsverzeichnis:** Symbol „Lesezeichen“ neben der Seitenübersicht. Zeigt alle Seiten mit Lesezeichen (Name, Seitenzahl), Tippen springt zur Seite; unten Lesezeichen für die aktuelle Seite setzen oder umbenennen. Speicherformat: pro Seite `bm`. Lesezeichen und Text in Textfeldern sind auch in der Suche auffindbar.
- Nicht enthalten: Tabellen im Text, Rechtschreibprüfung, Word-Export, PDF-Export einzelner Seiten (folgen).
- **Haken im Werkzeugmenü:** „Farbleiste“, „Export“ und „Fingerzeichnen“ aktualisierten ihren Haken nicht sofort; behoben.
- **Textfarbe:** Die Farbleiste war im Textmodus ausgegraut (sie kannte keine Textfarbe); jetzt aktiv, der Haken zeigt die Farbe des markierten Textes. Die Eckgriffe der Textfelder sind größer.
- **Hintergrund:** Jedes Textfeld hat unten links einen Knopf (Farbeimer), der zwischen Seitenhintergrund und weißem Hintergrund umschaltet (rückgängig machbar, wird gespeichert, auch im PDF).
- **Nachbesserung (Runde 2):** Schriftgrößen funktionierten nicht, weil die Stufen Klein/Groß/Riesig in der App alle auf dieselbe Größe gesetzt waren. Jetzt echte Größen und eine Zahlenliste (14–96). Schriftarten: Handschrift, Dekko, Lesbar, Schreibmaschine, Serif, Sans. Die Textfarbe kommt aus der normalen Farbleiste (im Textmodus färbt sie den markierten Text); die eigene Farbwahl der Textleiste ist entfernt.
- **PDF aus der Seitenübersicht:** „Auswählen“, Seiten markieren, „Als PDF“. Das PDF enthält nur die markierten Seiten in ihrer Reihenfolge. Die Seitenübersicht hat auch das Inhaltsverzeichnis (Symbol oben) und zeigt Lesezeichen-Namen unter den Seiten.
- **Suche in einer Notiz oder einem Ordner:** Lupe im Editor sucht nur in dieser Notiz, Lupe in der Dateiliste nur im aktuellen Ordner. In der Suche lässt sich „Nur in …“ ein- und ausschalten.

## 32. Handschrift in Text umwandeln (Branch `feature/handschrift-zu-text`)
- Lasso um die Handschrift ziehen, in der Auswahlleiste „In Text“. Die Erkennung läuft auf dem Gerät, Zeile für Zeile (gleiche Technik wie bei der Suche). Ein Fenster zeigt den erkannten Text zum Korrigieren; optional „Handschrift danach löschen“.
- Ergebnis ist ein normales Textfeld an der Stelle der Handschrift (verschiebbar, formatierbar). Rückgängig: erst das Textfeld, dann (falls gelöscht) die Handschrift.
- Voraussetzung: einmalig Internet für das Sprachmodell; die Qualität hängt von der Handschrift ab.

## 33. Notizen verlinken, zwei Notizen nebeneinander, Rechtschreibung (Branch `feature/verlinken-fenster`)
- **Verknüpfung:** In der Textfunktion links in der Leiste „Verknüpfung zu einer Notiz“. Notiz wählen, Zielseite eingeben; es entsteht ein Textfeld mit hellem Hintergrund. Außerhalb der Textfunktion öffnet ein Tipp darauf die Ziel-Notiz an der Seite. Speicher: pro Textfeld `lp` (Pfad) und `lg` (Seite). Gelöschte Zielnotiz → Hinweis. Wird die Ziel-Notiz später verschoben oder umbenannt, bricht der Link (Pfad ist fest).
- **Zwei Notizen nebeneinander:** Symbol „geteilter Bildschirm“ in der Editor-Leiste. Beide Seiten sind volle Editoren; Trenner in der Mitte ist verschiebbar; „Andere Notiz“ pro Seite. Beide Notizen müssen verschieden sein. Innerhalb von Feder, nicht über Android-Mehrfenster.
- **Rechtschreibung:** Nicht umgesetzt. Die verwendete Editor-Bibliothek bietet keine Anbindung an die Android-Rechtschreibprüfung (Compiler-Test: Parameter existiert nicht). Offen: eigene Prüfung mit Wörterbuch.
- Handschrift → Text: Text jetzt in Zeilenhöhe-Größe.

## 34. Schreibfeld-Höhe, Korrekturwörterbuch, Lasso-Link, Zwei-Notizen-X

- Schreibfeld: Das Symbol links in der Leiste des Feldes (Pfeile hoch/runter) ziehen = Eingabefläche höher oder niedriger. Der Wert bleibt gespeichert (`easyWritingHeight`); der blaue Rahmen auf dem Blatt passt sich an.
- Zwei Notizen: Jede Seite hat ein X. Schließt man eine Seite, bleibt die andere Notiz allein im Vollbild.
- Korrekturwörterbuch (`correction_dictionary.dart`): Beim Bestätigen von „Handschrift in Text" werden geänderte Wörter (erkannt → richtig) gemerkt, sofern der Text gleich viele Wörter hat. Beim nächsten Umwandeln und bei der Indexierung für die Suche wird das Wörterbuch angewandt. Die Einträge liegen nur lokal in den Einstellungen, nicht im Code.
- Lasso-Link: Auswahl → „Link" → Ziel-Notiz und Seite wählen. Über der Auswahl liegt ein leicht getönter Link-Bereich (technisch ein Verknüpfungs-Textfeld ohne Text); Antippen öffnet das Ziel.

## 35. Textfeld → Nextcloud

Im Textmodus gibt es in der Leiste neben „Textfeld hinzufügen" ein Wolken-Symbol: markierter Text (sonst der ganze Inhalt des zuletzt benutzten Textfelds) kann als Aufgabe, Termin oder Kontakt an Nextcloud gesendet werden. Das Lasso wählt weiterhin nur Handschrift, keine Textfelder.

## 36. Zwei Seiten nebeneinander

- Senkrechtes Scrollen, Querformat: Wird weit genug ausgezoomt, stehen zwei Seiten pro Zeile nebeneinander; Einzoomen schaltet zurück auf eine Seite. Die Umschaltung hat eine Hysterese (Eintritt früher als Rückkehr), die Ansicht bleibt dabei auf der gleichen Stelle. Sprünge zu einer Seite (Seitenübersicht, neue Seite) schalten auf eine Seite pro Zeile zurück.
- Buch-Blättern, Querformat: Doppelblatt wie ein echtes Buch (Seite 1 allein rechts, dann 2/3, 4/5 …; letzte Seite allein links). Jede Seite passt komplett ins Bild. Blättern geht um ein Blatt; statt des Blätter-Effekts gleitet das Blatt seitlich.
- Im Hochformat bleibt alles wie bisher (eine Seite).

### Nachbesserung Doppelblatt
- Tippen auf die äußeren ~35 % der rechten/linken Buchseite blättert; die rechte Seite rollt über den Falz und blendet am Falz aus (rückwärts umgekehrt). Wischen blättert ebenso.
- Lineal und Winkelmesser lassen sich über den Falz auf die Nachbarseite ziehen und von dort auch wieder greifen.

### Nachbesserung Doppelblatt, Runde 2
- Echtes Buch-Umblättern (`book_flip_painter.dart`): Das Blatt klappt um den Falz. Erst die alte rechte Seite, nach der Hälfte die Rückseite (= neue linke Seite), die links liegen bleibt; darunter kommt die neue rechte Seite zum Vorschein. Rückwärts läuft es umgekehrt. Sind die benötigten Seiten noch nicht gerendert, wird seitlich gewechselt statt zu blättern.
- Tempo: Im Doppelblatt wird nur das sichtbare Blatt gerendert; die Nachbarblätter folgen erst nach kurzer Ruhe (450 ms) im Hintergrund. Die Bilder für den Blättereffekt entstehen mit geringerer Auflösung (max. 1,5-fach).
- Beim Öffnen und beim Drehen wird die Ansicht mit den echten Maßen der Fläche auf das Blatt gesetzt (vorher: Bildschirmbreite, dadurch eine Lücke zwischen den Seiten).
- Textfelder lassen sich über den Seitenrand auf die Nachbarseite ziehen (Doppelblatt und Zwei-Seiten-Ansicht), mit Rückgängig (`HistoricTextBoxMove`).
- Lineal/Winkelmesser: Das Ausschalten wirkt auf die Seite, auf der das Hilfsmittel liegt (vorher: wurde es auf der linken Seite neu angelegt).

### Nachbesserung Doppelblatt, Runde 3
- Blätter-Effekt: Das Blatt biegt sich jetzt beim Umklappen (freie Kante eilt dem Falz voraus), mit Perspektive, Schattierung nach Neigung und Schatten auf der darunterliegenden Seite. Vorher klappte es starr wie ein Brett.
- Fehler beim schnellen Blättern behoben: Tipps während der Bildaufnahme starteten ein zweites Umblättern gleichzeitig; ein Antippen mitten im Umblättern ließ das Doppelblatt auf dem alten Blatt stehen. Jetzt gibt es eine Sperre, und ein Abbruch schließt das Umblättern sofort ab.
- Einstellungen → „Leistungsanzeige": zeigt die Flutter-Messbalken (UI und Raster), um Ruckeln zu analysieren.

### Nachbesserung Runde 4 (Blättern/Rendern)
- Blätteranimation startet immer bei 0 (kein Rest-Wert der letzten Animation).
- Tipp-Blättern merkt sich die Zielseite des letzten Blätterns, solange die Ansicht unverändert ist (gegen Rückwärts-Sprünge).
- PDF-Seiten werden mit höchstens 170 dpi gerendert (vorher 300 dpi).
- Schnelles Tippen während einer Blätteranimation wird vorgemerkt (höchstens 3) statt verschluckt.
- Tipp-Blättern: Der Einrast-Timer der Tipp-Geste läuft nicht mehr gegen ein laufendes oder vorbereitetes Blättern (Ursache für Hin-und-her-Springen, Vermutung).
- Blätter-Protokoll: Tippen, Blättern und Einrasten schreiben Zeilen („Blaettern | …“) ins Protokoll (Einstellungen → Protokoll anzeigen), um Fehler beim Tippen mit echten Daten zu finden.

## 37. Geodreieck, Zirkel und Hilfsmittel-Menü
- Ein Werkzeugleisten-Symbol „Zeichenhilfen" öffnet ein Menü: Lineal, Winkelmesser (Halbkreis/Vollkreis), Geodreieck, Zirkel. Mehrere können gleichzeitig sichtbar sein.
- Geodreieck: gleichschenklig-rechtwinklig (Hypotenuse 16 cm), cm-Skala an allen Kanten, Griff in der Mitte zum Drehen; Stifte rasten an allen drei Kanten ein.
- Zirkel: Nadelspitze verschieben, Griff am Kreisrand stellt Radius (1–12 cm) und Richtung ein; der Stift rastet auf dem Kreis ein.
- Maße gehen von 21 cm Seitenbreite aus (wie beim Lineal).
- **Ursache Rückwärts-Sprung (Protokoll vom Test, Build 165, Fakt aus den Zeilen):** Nach einem Tipp-Blättern stand die Ansicht 155 px neben dem Blatt (Gleit-Animation mittendrin gestoppt); der Einrast-Timer las das als „mehr als 1/7 gezogen" und blätterte von selbst zurück oder vor. Behebung: ein angehaltenes Gleiten wird sofort ans Ziel gesetzt, und nach einem Tipp-Blättern rastet die Ansicht nur noch auf der Zielseite ein, bis ein Finger aufgesetzt wird (`_settlePage`).
- Einstellungen → „Blätter-Protokoll als Datei teilen“ speichert nur die Blätter-Zeilen als Textdatei (Teilen-Dialog).
- Nachbarblätter werden nach 200 ms Ruhe vorgerendert (vorher 450 ms), damit beim schnellen Tippen weniger oft auf das seitliche Gleiten ohne Blättereffekt ausgewichen wird (Vermutung, Protokoll zeigte Gleiten bei großen PDF-Seiten).

## 38. Ordner verschieben und Notizbuch-Auswahl (Teilen-Ansicht)

- **Ordner in andere Ordner/Notizbücher verschieben:** In der aufgeklappten Ordnerkarte gibt es jetzt die Schaltfläche „Verschieben …". Sie öffnet die Ordnerauswahl (`pickFolder`, `/` = Hauptregal) und ruft `FileManager.moveDirectory` auf. Verboten sind: in sich selbst oder einen Unterordner verschieben, und ein Ziel mit gleichem Namen (dann wird ein eindeutiger Name vergeben).
- **Notizbuch-Auswahl für die zweite Hälfte der geteilten Ansicht** (`pick_notebook_dialog.dart`): Titel groß, Ordner klein und grau darunter; „Zuletzt geöffnet" steht oben; Ordner-Schnellfilter als Chips; Vorschaubild (dieselbe `.p`-Datei wie auf der Startseite, ggf. entschlüsselt), ersatzweise ein Buch-Symbol.

## 39. Feste Regale, Konfliktkopie, PDF-Laden

- **Feste Regale „Dienst" und „Privat":** stehen immer neben Schnellnotiz und Hauptregal in der Leiste. Das Regal wird beim ersten Antippen angelegt. Umbenennen/Löschen per Langdruck ist für sie gesperrt.
- **Konfliktkopie (Nextcloud):** Pro Notiz wird der Zeitstempel der zuletzt abgeglichenen Version gespeichert (`KnownMtimes`, Einstellung `fileSyncKnownMtimes`). Haben beide Seiten (lokal und Server) die Notiz seit dem letzten Abgleich verändert, wird die unterlegene Version als eigene Notiz „… (Konflikt JJJJ-MM-TT HH.mm)" gesichert und synchronisiert, statt stillschweigend überschrieben zu werden. Das gilt für das Herunterladen (lokale Änderungen werden gesichert) und das Hochladen (Server-Stand wird gesichert). Grenze: Notizen ohne gemerkten Stand (erster Abgleich nach dem Update) werden nicht geprüft; es wird nichts zusammengeführt.
- **PDF-Laden:** Beim Öffnen jeder PDF-Seite wurde die komplette Datei neu gelesen und ggf. entschlüsselt, auch wenn das Dokument schon im Cache lag. Jetzt wird die Datei nur noch bei einem Cache-Fehlgriff gelesen (`PdfDocumentCache.load(readBytes: …)`).
