# Knobeln Game Backend

Ein vollständiges Backend-System für das mobile Knobeln-Spiel, implementiert mit AWS-Services und Terraform.

## 🎯 Überblick

Das Knobeln Backend bietet eine vollständig serverlose Architektur für ein Echtzeit-Multiplayer-Spiel:

- **AWS API Gateway** - HTTP REST API + WebSocket für Echtzeit-Kommunikation
- **AWS Lambda** - Serverlose Spiellogik
- **DynamoDB** - Spielstatus und Verbindungsverwaltung
- **EventBridge Scheduler** - Timer für Spielphasen
- **Terraform** - Infrastructure as Code

## 🏗️ Architektur

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Flutter App   │────│  API Gateway     │────│  Lambda         │
│   (Mobile)      │    │  (HTTP + WS)     │    │  Functions      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                  │                       │
                                  │                       │
                       ┌──────────▼──────────┐    ┌───────▼──────────┐
                       │   DynamoDB          │    │  EventBridge     │
                       │   (Game State)      │    │  (Timers)        │
                       └─────────────────────┘    └──────────────────┘
```

## 🚀 Quick Start

### Voraussetzungen

- [Terraform](https://terraform.io) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) konfiguriert
- [Node.js](https://nodejs.org) >= 18.x
- [zip](https://linux.die.net/man/1/zip) utility

### 1. Repository klonen

```bash
git clone <repository-url>
cd knobeln-backend
```

### 2. Deployment

```bash
chmod +x deploy.sh
./deploy.sh deploy
```

Das Script führt automatisch folgende Schritte aus:
- Prüft Voraussetzungen
- Erstellt Lambda-Pakete
- Deployed Infrastructure mit Terraform
- Aktualisiert Lambda-Code
- Testet Endpoints

### 3. API-Endpunkte verwenden

Nach dem Deployment erhalten Sie die URLs:

```bash
# Beispiel-URLs (werden nach Deployment angezeigt)
HTTP API: https://abc123.execute-api.eu-central-1.amazonaws.com/dev
WebSocket: wss://xyz789.execute-api.eu-central-1.amazonaws.com/dev
```

## 📋 API-Referenz

### HTTP REST API

#### Spiel erstellen
```bash
POST /games
Content-Type: application/json

{
  "playerId": "player1",
  "playerName": "Max Mustermann"
}
```

#### Spiel beitreten
```bash
POST /games/{gameId}/join
Content-Type: application/json

{
  "playerId": "player2", 
  "playerName": "Anna Schmidt"
}
```

#### Hölzer wählen
```bash
POST /games/{gameId}/pick
Content-Type: application/json

{
  "playerId": "player1",
  "sticksCount": 2
}
```

#### Schätzung abgeben
```bash
POST /games/{gameId}/guess
Content-Type: application/json

{
  "playerId": "player1",
  "guessCount": 5
}
```

#### Spiel-Status abrufen
```bash
GET /games/{gameId}
```

### WebSocket API

#### Verbindung herstellen
```javascript
const ws = new WebSocket('wss://xyz789.execute-api.eu-central-1.amazonaws.com/dev?gameId=GAME_ID');
```

#### Nachrichten-Typen
- `PLAYER_JOINED` - Neuer Spieler ist beigetreten
- `GAME_STARTED` - Spiel wurde gestartet
- `PHASE_CHANGED` - Spielphase hat gewechselt
- `PLAYER_PICKED` - Spieler hat Hölzer gewählt
- `PLAYER_GUESSED` - Spieler hat Schätzung abgegeben
- `ROUND_ENDED` - Runde ist beendet
- `GAME_FINISHED` - Spiel ist beendet
- `AUTO_PICK_EXECUTED` - Automatische Hölzerwahl ausgeführt

## 🎮 Spielablauf

### 1. Spiel-Erstellung und Beitritt
- Spieler erstellt Spiel → Status: `waiting`
- Andere Spieler können 60 Sekunden lang beitreten
- Automatischer Start nach 60 Sekunden

### 2. Hölzer-Phase (`pick`)
- Jeder Spieler wählt 0-3 Hölzer
- Timeout nach 30 Sekunden → automatisch 3 Hölzer
- Wechsel zur Schätzphase wenn alle gewählt haben

### 3. Schätz-Phase (`guess`)
- Spieler raten reihum die Gesamtzahl der Hölzer
- Letzter Spieler darf nicht die gleiche Zahl wie alle anderen wählen
- Richtige Schätzer scheiden aus (Gewinner)

### 4. Runden-Ende
- Bei einem verbleibenden Spieler: Spiel beendet (Verlierer)
- Sonst: Nächste Runde mit nächstem Startspieler

## 🗃️ Datenbank-Schema

### KnobelnGames Tabelle
```javascript
{
  gameId: "uuid",
  status: "waiting|running|finished",
  createdAt: "2024-01-01T12:00:00.000Z",
  gameStartTime: "2024-01-01T12:01:00.000Z",
  finishedAt?: "2024-01-01T12:05:00.000Z",
  
  players: [{
    playerId: "string",
    playerName: "string", 
    joinedAt: "2024-01-01T12:00:30.000Z",
    pickedSticks: null|0|1|2|3,
    guess: null|number,
    isEliminated: false|true
  }],
  
  currentPhase: null|"pick"|"guess",
  roundNumber: 0,
  turnPlayerIndex: 0,
  totalSticks: 0,
  
  guesses: [{
    playerId: "string",
    playerName: "string",
    guess: number,
    timestamp: "2024-01-01T12:00:45.000Z",
    isAutoGuess?: true
  }],
  
  loserId?: "string",
  scheduledEvents?: ["event-name-1", "event-name-2"],
  ttl: 1704110400
}
```

### WebSocketConnections Tabelle
```javascript
{
  connectionId: "connection-id",
  gameId: "game-uuid",
  connectedAt: "2024-01-01T12:00:00.000Z",
  ttl: 1704110400
}
```

## 🔧 Konfiguration

### Umgebungsvariablen
```bash
AWS_REGION=eu-central-1      # AWS Region
ENVIRONMENT=dev              # Environment (dev/staging/prod)
```

### Terraform-Variablen

Erstellen Sie eine `terraform.tfvars` Datei:
```hcl
aws_region = "eu-central-1"
environment = "production" 
project_name = "knobeln"
lambda_timeout = 30
log_retention_days = 30
enable_xray_tracing = true
cors_allowed_origins = ["https://myapp.com"]
```

## 🛠️ Entwicklung

### Lokale Lambda-Entwicklung

```bash
# Lambda-Code testen
cd lambda/game-handler
npm test

# Code nur aktualisieren (ohne Infrastructure)
./deploy.sh update
```

### Debugging

CloudWatch Logs sind verfügbar unter:
- `/aws/lambda/{project-name}-{env}-{suffix}-game-handler`
- `/aws/lambda/{project-name}-{env}-{suffix}-websocket-handler`  
- `/aws/lambda/{project-name}-{env}-{suffix}-game-timer`

### Monitoring

AWS-Services für Monitoring:
- **CloudWatch** - Logs und Metriken
- **X-Ray** - Request Tracing (optional)
- **DynamoDB Metrics** - Tabellen-Performance

## 🚨 Fehlerbehebung

### Häufige Probleme

#### 1. Lambda-Timeouts
```bash
# Timeout in Terraform erhöhen
variable "lambda_timeout" {
  default = 60  # Statt 30 Sekunden
}
```

#### 2. DynamoDB Throttling
```bash
# Auf Provisioned Mode wechseln
variable "dynamodb_billing_mode" {
  default = "PROVISIONED"
}
```

#### 3. WebSocket-Verbindungsfehler
```bash
# Logs prüfen
aws logs tail /aws/lambda/{function-name} --follow --region eu-central-1
```

#### 4. EventBridge Scheduler Permissions
```bash
# IAM-Rollen in Terraform prüfen
terraform plan
```

### Debug-Commands

```bash
# Terraform State prüfen
terraform show

# AWS Resources auflisten
aws apigatewayv2 get-apis --region eu-central-1
aws dynamodb list-tables --region eu-central-1
aws lambda list-functions --region eu-central-1

# DynamoDB-Daten einsehen
aws dynamodb scan --table-name {table-name} --region eu-central-1
```

## 🧹 Cleanup

### Einzelne Komponenten
```bash
# Nur Lambda-Code aktualisieren
./deploy.sh update

# API-Endpoints testen
./deploy.sh test
```

### Komplette Infrastruktur löschen
```bash
./deploy.sh destroy
```

⚠️ **Achtung**: Dies löscht alle Daten unwiderruflich!

## 🔒 Sicherheit

### Produktions-Deployment

1. **CORS konfigurieren**:
```hcl
cors_allowed_origins = ["https://yourdomain.com"]
```

2. **API-Authentication hinzufügen**:
```hcl
# Kann in zukünftigen Versionen mit Cognito/JWT erweitert werden
```

3. **DynamoDB Encryption**:
```hcl
resource "aws_dynamodb_table" "knobeln_games" {
  server_side_encryption {
    enabled = true
  }
}
```

4. **VPC-Konfiguration** (optional für erhöhte Sicherheit)

## 📈 Skalierung

### Performance-Optimierungen

- **DynamoDB**: Provisioned Capacity für vorhersagbare Workloads
- **Lambda**: Reserved Concurrency für kritische Funktionen
- **API Gateway**: Caching für GET-Requests
- **CloudFront**: CDN für statische Assets (wenn vorhanden)

### Kostenoptimierung

- TTL für DynamoDB-Einträge (automatische Bereinigung)
- Lambda-Timeouts reduzieren
- CloudWatch Log-Retention begrenzen

## 🤝 Contributing

1. Fork des Repositories
2. Feature-Branch erstellen (`git checkout -b feature/amazing-feature`)
3. Changes committen (`git commit -m 'Add amazing feature'`)
4. Branch pushen (`git push origin feature/amazing-feature`)
5. Pull Request erstellen

## 📄 Lizenz

Dieses Projekt ist unter der MIT Lizenz verfügbar. Siehe `LICENSE` Datei für Details.

## 🆘 Support

Bei Fragen oder Problemen:

1. GitHub Issues verwenden
2. [AWS Documentation](https://docs.aws.amazon.com) konsultieren
3. [Terraform Documentation](https://terraform.io/docs) lesen

---

**Happy Gaming! 🎲**