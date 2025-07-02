Schreibe mir eine Flutter App für Vereine. Die App soll für jeden Verein individualisierbar sein, indem ein Name und ein Wappen gesetzt werden kann. Weiterhin soll jeder Verein Mitglieder anlegen können. Die Mitglieder sollen dann ebenfalls die App herunterladen und sich mittels QR Code mit dem angelegten Account verknüpfen. 

Die App soll folgende Screen haben: 

1. Termine 

2. Stafgelder 

3. Fotogalerie 

4. Ein Spiel namens Knobeln

Als Backend soll eine möglichst kostengünstige AWS Variante verwendet werden.

Alle Updates außer Strafgelder sollen an alle anderen User per Push Notification gehen.

Strafgelder kann nur ein speziell ausgezeichneter User (Spieß) vergeben. Bei der Vergabe eines Strafgeldes tauch dieses beim Empfänger auf und dieser wird per Push Notification benachrichtigt.

Knobeln kann durch jeden Spieler gestartet werden. Jeder hat die Möglichkeit der Runde beizutreten. Wenn das Spiel startet, wählt jeder Spieler 0-3 Hölzer aus. Nach einem Timeout von 30 Sekunden werden automatisch 3 Hölzer gewählt. Wenn alle gewählt haben oder ein Timeout von 30 Sekunden vergangen ist, schätzt jeder der Reihe nach die Gesamtanzahl an Hölzern. Es beginnt immer der Spieler links von denjenigem der in der letzten Runde begonnen hat. Wer richtig schätzt scheidet aus. Wer zuletzt übrig bleibt hat verloren. Es dürfen nicht alle verbleibenden die gleiche Anzahl schätzen.



# Strafgeld Screen
Bitte generiere einen Screen namens Strafen in Flutter der Strafen für den aktuellen Benutzer anzeigt

# Spiess Screen
Bitte generiere einen Screen namens Spiess in Flutter. Es sollen alle Mitglieder in einer Liste angezeigt werden. Beim Klick auf ein Mitglied werden dessen Strafen angezeigt. Mit einem Plus soll eine neue Strafe für dieses Mitglied hinzugefügt werden können. Dies wird im AWS Backend gespeichert. Das Mitglied bekommt diese Strafe angezeigt und wird per Push darüber informiert.
