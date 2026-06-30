# Spring AI based MCP Hello World Server

Ein minimaler MCP-Server (Model Context Protocol) auf Basis von Spring Boot 4 und Spring AI 2.0.

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
> `spring-ai-starter-mcp-server`. In Schritt 2b wird das Artifact auf die
> WebFlux-Variante `spring-ai-starter-mcp-server-web` geändert.

---

### 2. pom.xml anpassen

Drei Anpassungen gegenüber dem generierten Stand:

**a) `start-class` in `<properties>` eintragen** (für AOT-fähiges Packaging):

```xml
<properties>
    <java.version>25</java.version>
    <start-class>com.example.helloworld.HelloworldApplication</start-class>
</properties>
```

**b) Generierten MCP-Starter auf WebMVC oder WebFlux-Variante umstellen:**

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
spring.ai.mcp.server.type=ASYNC  <-- nur für Webflux

server.port=8080
```

- `type=ASYNC` aktiviert den reaktiven SSE-Transport (passend zu WebFlux).
- `name` und `version` erscheinen im MCP-Handshake.

---

### 6. Server starten

```bash
./mvnw spring-boot:run
```

Der Server lauscht auf `http://localhost:8080`.

---

## LLM Studio

```json
{
  "mcpServers": {
    "hello-world-mcp": {
      "type": "sse",
      "url": "http://localhost:8080/sse"
    }
  }
}

``` 