Schreibe mir eine Flutter App für Vereine. Die App soll für jeden Verein individualisierbar sein, indem ein Name und ein Wappen gesetzt werden kann. Weiterhin soll jeder Verein Mitglieder anlegen können. Die Mitglieder sollen dann ebenfalls die App herunterladen und sich mittels QR Code mit dem angelegten Account verknüpfen. 

Die App soll folgende Screen haben: 

1. Termine 

2. Stafgelder 

3. Fotogalerie 

4. Ein Spiel namens Knobeln

Als Backend soll eine möglichst kostengünstige AWS Variante verwendet werden.

Alle Updates außer Strafgelder sollen an alle anderen User per Push Notification gehen.

Strafgelder kann nur ein speziell ausgezeichneter User (Spieß) vergeben. Bei der Vergabe eines Strafgeldes tauch dieses beim Empfänger auf und dieser wird per Push Notification benachrichtigt.

Ich möchte in meiner mobilen Flutter App ein Spiel namens Knobeln implementieren.
Ein Spiel Knobeln kann durch jeden Spieler gestartet werden. 
Es kann immer nur ein Spiel gleichzeitig stattfinden. 
Das Spiel findet auf den mobilen Endgeräten aller Mitspieler statt, die auf den Button am Spiel teilnehmen gedrückt haben.
Nachdem das Spiel durch den ersten Mitspieler gestartet wurde, beginnt das Spiel automatisch nach 60 Sekunden.
Jeder hat die Möglichkeit dem Spiel beizutreten. 
Wenn das Spiel startet, wählt jeder Spieler 0-3 Hölzer aus. 
Nach einem Timeout von 30 Sekunden werden automatisch 3 Hölzer gewählt. 
Wenn alle gewählt haben oder ein Timeout von 30 Sekunden vergangen ist, schätzt jeder der Reihe nach die Gesamtanzahl an Hölzern. 
Es beginnt der Spieler, der als erstes am Spiel teilgenommen hat, also das Spiel initiiert hat.
In der zweiten Runde beginnt der Spieler, der als zweites teilgenommen hat, usw.
Wenn jeder einmal begonnen hat, geht es wieder von vorne mit dem Spielinitiator als Startspieler los.
Wer richtig schätzt, scheidet aus und kann sich das Spiel noch weiter anschauen. 
Wer zuletzt übrig bleibt hat verloren. 
In einer Runde dürfen nicht alle die gleiche Anzahl schätzen.
Wenn zum Beispiel alle die gleiche Zahl schätzen, muss der letzte verbleibende eine andere Zahl schätzen.
Ich stelle mir folgende Architektur vor:
* AWS API Gateway (HTTP + WebSocket) → Zwei Schnittstellen:
* HTTP API für normale REST-Aufrufe (z. B. Spiel starten, beitreten, Hölzer setzen, Schätzung abgeben)
* WebSocket API für Echtzeit-Updates an alle Teilnehmer
* AWS Lambda → Spiel-Logik und Statusverwaltung
* AWS DynamoDB → Spielstatus, Spieler und Rundeninformationen speichern
* AWS EventBridge → für Timer/Timeouts (z. B. 60 s bis Spielstart, 30 s bis automatische Hölzerwahl)
Der Ablauf im Backend soll so aussehen:
1. Spiel starten
* Spieler ruft POST /games auf → Lambda erstellt neuen Eintrag in KnobelnGames
* status = waiting, Startzeit = jetzt + 60 Sekunden
* EventBridge-Rule: in 60 Sekunden ruft eine Lambda startGame(gameId) auf
2. Spiel beitreten
* Spieler ruft POST /games/{gameId}/join auf
* Lambda fügt Spieler zur KnobelnGames-Tabelle hinzu
* Benachrichtigung an alle WebSocket-Clients
3. Spielstart
* Nach 60 s triggert EventBridge → Lambda setzt status = running und currentPhase = pick
* EventBridge-Rule für 30 s → falls Spieler nicht gewählt haben, pickedSticks = 3 setzen
4. Hölzer wählen
* Spieler ruft POST /games/{gameId}/pick auf
* Wenn alle gewählt ODER Timeout vorbei → currentPhase = guess setzen
* turnPlayerIndex zeigt an, wer anfängt zu raten
5. Schätzphase
* Jeder Spieler ruft POST /games/{gameId}/guess auf
* Backend prüft:
** Zahl darf noch nicht geraten worden sein
** Falls letzter Spieler dran ist und Zahl schon vergeben → zwingt andere Zahl
* Wenn alle geraten → prüft, wer richtig lag → markiert isEliminated = true
* Falls nur noch einer übrig → status = finished, loserId setzen
* Sonst neue Runde (currentPhase = pick, roundNumber++, turnPlayerIndex++)
6. Echtzeit-Updates
* Jeder Statuswechsel wird via WebSocket an alle Teilnehmer gepusht
* Clients müssen nicht ständig pollen
Ich benötige das vollständige Backend als Terraform Script mit AWS Lambda Functions.

# Strafgeld Screen
Bitte generiere einen Screen namens Strafen in Flutter der Strafen für den aktuellen Benutzer anzeigt

# Spiess Screen
Bitte generiere einen Screen namens Spiess in Flutter. Es sollen alle Mitglieder in einer Liste angezeigt werden. Beim Klick auf ein Mitglied werden dessen Strafen angezeigt. Mit einem Plus soll eine neue Strafe für dieses Mitglied hinzugefügt werden können. Dies wird im AWS Backend gespeichert. Das Mitglied bekommt diese Strafe angezeigt und wird per Push darüber informiert.

Der Spiess Screen soll so angepasst werden, dass er nur dann sichtbar ist, wenn der aktuelle Benutzer ein Spiess ist. Weiterhin soll die Auswahl des Betrags durch Klick auf Euro Münzen erfolgen. 
# Fotogalerie
Bitte generiere einen Screen namens Fotogalerie in Flutter. Es sollen Fotos hochgeladen werden können, die im AWS Backend in S3 gespeichert werden. Alle Fotos aller Mitglieder sollen in einer Galerie angezeigt werden. Ein Admin User soll auch Fotos löschen können.

# Termine

# Knobeln