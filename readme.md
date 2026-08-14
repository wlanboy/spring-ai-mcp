# Spring AI based MCP Hello World Server

Ein minimaler MCP-Server (Model Context Protocol) auf Basis von Spring Boot 4 und Spring AI 2.0.

Das **Model Context Protocol** ist ein offener Standard, mit dem KI-Modelle (z. B. Claude, GPT)
strukturiert auf externe Tools und Dienste zugreifen können.

Dieses Projekt zeigt den kleinstmöglichen Aufbau:

| Schicht | Technologie |
|---|---|
| HTTP-Transport | Spring WebMVC oder WebFlux (SSE) |
| MCP-Protokollstack | `spring-ai-starter-mcp-server-webmvc` / `-webflux` |
| Tool-Definition | `@Tool`-Annotation auf einfachen Spring-Beans |
| Build | Standard-Maven-Build (`spring-boot-maven-plugin`) |

Die enthaltenen Beispiel-Tools (`greet`, `serverTime`) demonstrieren das Grundprinzip
und lassen sich als Vorlage für eigene Integrationen verwenden.

## Voraussetzungen

- Java 25
- Maven 3.9+

## Arbeitsschritte

### 1. Projektgerüst mit Spring Initializr erzeugen

```bash
curl -s -o spring-init.zip "https://start.spring.io/starter.zip?\
type=maven-project&language=java&bootVersion=4.1.0\
&groupId=com.example&artifactId=helloworld\
&packageName=com.example.helloworld&javaVersion=25\
&dependencies=configuration-processor,spring-ai-mcp-server"
unzip spring-init.zip
```

Spring Initializr liefert ein fertiges Maven-Projekt mit `mvnw`, `.gitignore` und
einer leeren `HelloworldApplication.java`.

> **Hinweis:** `spring-ai-mcp-server` erzeugt den Servlet-Starter
> `spring-ai-starter-mcp-server`. In Schritt 2 wird das Artifact auf die
> WebFlux-Variante `spring-ai-starter-mcp-server-webflux` geändert.

---

### 2. pom.xml anpassen

Eine Anpassung gegenüber dem generierten Stand:

**Generierten MCP-Starter auf WebMVC oder WebFlux-Variante umstellen:**

Der Initializr erzeugt den Servlet-basierten Starter. Den `artifactId` auf die
reaktive Variante ändern:

```xml
<!-- generiert (ersetzen): -->
<artifactId>spring-ai-starter-mcp-server</artifactId>

<!-- ersetzen durch: -->
<artifactId>spring-ai-starter-mcp-server-webmvc</artifactId>

<!-- ersetzen durch: -->
<artifactId>spring-ai-starter-mcp-server-webflux</artifactId>
```

Der Starter zieht WebFlux, Reactor und den MCP-Protokollstack selbst mit —
`spring-boot-starter-webflux` muss nicht separat eingetragen werden.

---

### 3. Tool-Klasse erstellen (`HelloWorldTools.java`)

MCP-Tools sind einfache Spring-Beans, deren Methoden mit `@Tool` annotiert
werden. Die `description` erscheint im MCP-Toolkatalog und wird vom
KI-Modell für die Tool-Auswahl genutzt.

```java
@Service
public class HelloWorldTools {

    @Tool(description = "Returns a greeting message for the given name")
    public String greet(String name) {
        return "Hello, %s! Welcome to the MCP Hello World Server.".formatted(name);
    }

    @Tool(description = "Returns the current server time as ISO-8601 string")
    public String serverTime() {
        return java.time.Instant.now().toString();
    }
}
```

---

### 4. Tools als Bean registrieren (`HelloworldApplication.java`)

Spring AI benötigt einen `ToolCallbackProvider`-Bean, der dem MCP-Server
mitteilt, welche Tools exportiert werden sollen:

```java
@Bean
public ToolCallbackProvider helloWorldToolProvider(HelloWorldTools helloWorldTools) {
    return MethodToolCallbackProvider.builder()
        .toolObjects(helloWorldTools)
        .build();
}
```

---

### 5. application.properties konfigurieren

```properties
spring.application.name=helloworld

spring.ai.mcp.server.name=hello-world-mcp
spring.ai.mcp.server.version=1.0.0
spring.ai.mcp.server.type=ASYNC        <-- nur für Webflux
spring.ai.mcp.server.protocol=STATELESS  <-- siehe Abschnitt 5a

server.port=8080
```

- `type=ASYNC` aktiviert den reaktiven SSE-Transport (passend zu WebFlux).
- `name` und `version` erscheinen im MCP-Handshake.
- `protocol` bestimmt den Transport-Modus (`SSE`, `STREAMABLE`, `STATELESS`) —
  siehe Abschnitt 5a für Details und Konsequenzen. Aktuell in diesem
  Projekt: `STATELESS`.

---

### 5a. Protokoll-Variante wählen (`spring.ai.mcp.server.protocol`)

Sowohl der WebMVC- als auch der WebFlux-Starter registrieren je nach Wert
dieser Property eine von drei unterschiedlichen Transport-Implementierungen
(`McpServerSseWebMvcAutoConfiguration`, `McpServerStreamableHttpWebMvcAutoConfiguration`,
`McpServerStatelessWebMvcAutoConfiguration` — bzw. die WebFlux-Pendants). Es
handelt sich also nicht nur um ein Flag, sondern um drei komplett
unterschiedliche Server-Implementierungen mit eigenem Endpoint-Verhalten.

```properties
spring.ai.mcp.server.protocol=SSE | STREAMABLE | STATELESS
```

#### `SSE` (deprecated, Legacy-Protokoll)

- Zwei getrennte Endpoints: `GET /sse` (öffnet eine dauerhafte
  SSE-Verbindung, liefert eine `sessionId`) und `POST /mcp/message`
  (Client schickt JSON-RPC-Requests, verknüpft über die `sessionId` aus
  dem SSE-Handshake).
- Die zugehörigen Properties (`sse-endpoint`, `sse-message-endpoint`,
  `base-url`, `keep-alive-interval`) sind in der aktuellen Version bereits
  als `@deprecated` markiert — nur für ältere MCP-Clients gedacht, die das
  neue Streamable-HTTP-Protokoll noch nicht unterstützen.
- **Konsequenz:** voll zustandsbehaftet. Die offene SSE-Verbindung lebt auf
  genau einer Server-Instanz; horizontale Skalierung erfordert Sticky
  Sessions oder gemeinsam genutzten Session-Speicher. Fällt die Instanz
  aus, bricht die Verbindung ab und der Client muss neu verbinden.

#### `STREAMABLE` (Standardwert)

- Ein einzelner Endpoint (`spring.ai.mcp.server.streamable-http.mcp-endpoint`,
  Default `/mcp`) für alle Requests. Der Server kann pro Response
  entweder direkt JSON zurückgeben oder auf eine SSE-Stream-Antwort
  „hochstufen“ (nötig für Server-Push wie Sampling-Requests oder
  Change-Notifications).
- Beim `initialize`-Call vergibt der Server eine Session, die der Client
  über den Header `Mcp-Session-Id` bei allen Folgerequests mitschicken
  muss. Zusätzliche Optionen: `keep-alive-interval` (Ping-Intervall für
  offene Streams), `disallow-delete` (verbietet `DELETE /mcp`, also das
  aktive Beenden der Session durch den Client).
- **Konsequenz:** zustandsbehaftet, aber flexibler als `SSE`. Unterstützt
  Resumability (Wiederaufnahme unterbrochener Streams über
  `Last-Event-ID`) und bidirektionale Server→Client-Kommunikation. Für
  horizontale Skalierung wird trotzdem entweder Sticky Routing (Session-ID
  → gleiche Instanz) oder ein geteilter Session-Store benötigt.

#### `STATELESS`

- Derselbe `POST /mcp`-Endpoint wie bei `STREAMABLE`, aber **ohne**
  Session-Konzept: kein `Mcp-Session-Id`-Header, keine offene
  SSE-Verbindung, kein `DELETE /mcp`. Jeder Request (`initialize`,
  `tools/list`, `tools/call`, …) wird unabhängig und vollständig
  in sich abgeschlossen verarbeitet.
- Verifiziert durch direkten Test gegen diesen Server: `tools/list`
  funktioniert als eigenständiger `curl`-Aufruf ganz ohne vorheriges
  `initialize` in derselben Verbindung und ohne jeglichen Session-Header.
- **Konsequenz:**
  - ✅ Beliebig horizontal skalierbar hinter einem einfachen Load Balancer
    ohne Sticky Sessions. Jede Instanz kann jeden Request beantworten.
  - ✅ Passt gut zu Serverless/Container-Umgebungen mit kurzlebigen
    Instanzen.
  - ❌ Kein Server-initiierter Push: Sampling-Requests, `listChanged`-
    Notifications für Tools/Resources/Prompts kommen beim Client nicht an,
    da kein offener Stream existiert, über den der Server sie schicken
    könnte.
  - ❌ Keine Resumability. Ein abgebrochener Request muss vom Client
    komplett wiederholt werden, es gibt nichts, an das angeknüpft werden
    könnte.
  - Sinnvoll, wenn die Tools selbst zustandslos sind (wie `greet` und
    `serverTime` in diesem Projekt) und keine der Push-Fähigkeiten
    benötigt werden.

Aktuell nutzt dieses Projekt (`application.properties`) den Modus
`STATELESS`.

---

### 6. Server starten

```bash
./mvnw spring-boot:run
```

Der Server lauscht auf `http://localhost:8080`.

---

## LM Studio

Passend zum aktuell konfigurierten `protocol=STATELESS` (bzw. `STREAMABLE`)
wird der Streamable-HTTP-Endpoint `/mcp` verwendet, **nicht** `/sse`:

```json
{
  "mcpServers": {
    "hello-world-mcp": {
      "type": "streamable-http",
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

> **Achtung:** `/sse` existiert nur, wenn `spring.ai.mcp.server.protocol=SSE`
> gesetzt ist (siehe Abschnitt 5a). Mit dem aktuellen `STATELESS`-Modus ist
> dieser Endpoint nicht registriert — ein Client, der auf `type: sse` /
> `/sse` konfiguriert ist, kann sich nicht verbinden.
