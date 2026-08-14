# ============================
# 1. Build Stage (Java 25)
# ============================
FROM registry.access.redhat.com/ubi10/openjdk-25:latest AS build

WORKDIR /app

COPY pom.xml .
# → Nur die pom.xml wird kopiert, damit Maven bereits alle Dependencies auflösen kann,
#   ohne dass sich der Sourcecode ändert. Das verbessert das Layer-Caching.

RUN --mount=type=cache,target=/root/.m2 mvn -q -DskipTests dependency:go-offline
# → Lädt alle Maven-Dependencies vorab herunter.
# → --mount=type=cache sorgt dafür, dass das lokale Maven-Repository zwischen Builds gecached wird.

COPY src ./src
# → Jetzt erst der Sourcecode, damit Änderungen am Code nicht das Dependency-Layer invalidieren.

RUN --mount=type=cache,target=/root/.m2 mvn -q -DskipTests compile spring-boot:process-aot package
# → Baut das eigentliche JAR mit AOT (Ahead-of-Time) Processing.
# → compile: Kompiliert die Klassen (notwendig für process-aot).
# → spring-boot:process-aot: Generiert AOT-Metadaten basierend auf den kompilierten Klassen.
# → package: Baut das finale JAR inkl. AOT-Klassen.

RUN JAR=$(ls target/*.jar | grep -v original) && \
    cp "$JAR" app.jar && \
    java -Djarmode=tools -jar app.jar extract --layers --launcher --destination extracted
# → Spring Boot 4.x Layertools: --launcher ist erforderlich um den Loader zu extrahieren.
# → Ohne eigene layers.xml nutzt Boot die Standard-Layer:
#     - dependencies            (Spring, Spring AI, Reactor …)
#     - spring-boot-loader      (org/springframework/boot/loader/*)
#     - snapshot-dependencies
#     - application             (BOOT-INF/classes + AOT-Metadaten)
# → Vorteil: Docker kann diese Layer getrennt cachen → schnellere Deployments.

RUN java -XX:ArchiveClassesAtExit=app.jsa \
         -Dspring.context.exit=onRefresh \
         -Dspring.aot.enabled=true \
         -XX:+UseSerialGC \
         -cp "extracted/dependencies/*:extracted/snapshot-dependencies/*:extracted/spring-boot-loader/*:extracted/application/" \
         org.springframework.boot.loader.launch.JarLauncher || [ -f app.jsa ]
# → Erzeugt ein Class Data Sharing (CDS) Archiv beim Build, um den Start in der Runtime-Stage zu beschleunigen.
# → -XX:+UseSerialGC muss zum GC der Runtime-Stage passen: dynamische CDS-Archive (ab JDK 19) können
#   "archived heap objects" enthalten, die an den GC zur Dump-Zeit gekoppelt sind. Bei einem Mismatch
#   startet die App zwar trotzdem, die JVM verwirft aber den heap-object-Teil des Archivs (Warnung im
#   Log) und der Startup-Vorteil geht teilweise verloren.

# ============================
# 2. Runtime Stage (Java 25)
# ============================
FROM registry.access.redhat.com/ubi10/openjdk-25-runtime:latest

# OCI-konforme Labels
LABEL org.opencontainers.image.title="spring-ai-mcp" \
      org.opencontainers.image.description="Spring AI based MCP Hello World Server" \
      org.opencontainers.image.version="0.0.1-SNAPSHOT" \
      org.opencontainers.image.vendor="wlanboy" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.base.name="openjdk-25:latest"

WORKDIR /app

USER 185

COPY --from=build --chown=185:185 /app/extracted/dependencies/ ./
# → Stabile Release-Bibliotheken (Spring, Spring AI, Reactor …). Ändern sich selten.

COPY --from=build --chown=185:185 /app/extracted/spring-boot-loader/ ./
# → Spring Boot Launcher. Ändert sich nur bei Spring-Boot-Version-Upgrade.

COPY --from=build --chown=185:185 /app/extracted/snapshot-dependencies/ ./
# → Snapshot-Dependencies, ändern sich häufiger.

COPY --from=build --chown=185:185 /app/extracted/application/ ./
# → Kompilierter App-Code + AOT-Metadaten. Ändert sich am häufigsten.

COPY --from=build --chown=185:185 /app/app.jsa /app/app.jsa

EXPOSE 8080
# → Dokumentiert den Port, den die App verwendet (Spring Boot Default, siehe application.properties).

# Wir nutzen exec (als JSON-Array-ENTRYPOINT), damit Java die PID 1 übernimmt.
# Dies ist wichtig für das Signal-Handling (z.B. in Kubernetes).
#
# JVM-Optionen (abgestimmt auf Kubernetes-Limit: 512Mi Memory / 1 CPU-Core):
# -XX:SharedArchiveFile: Nutzt das beim Build erzeugte CDS-Archiv für schnelleren Start
# -Dspring.aot.enabled=true: Aktiviert die AOT-Metadaten zur Laufzeit
# -Djava.security.egd: Beschleunigt kryptografische Initialisierung
# -XX:+ExitOnOutOfMemoryError: Prozess beendet sich sofort bei Heap-OOM statt in kaputtem Zustand
#   weiterzulaufen; Kubernetes startet den Pod neu
# -XX:MaxRAMPercentage=70.0: maximale Heap-Groesse als Anteil des Container-Memory-Limits
#   (~358Mi von 512Mi)
# -XX:InitialRAMPercentage=70.0: initiale Heap-Groesse identisch zum Max, kein Nachvergroessern
#   zur Laufzeit noetig
# -XX:MaxMetaspaceSize=96m: deckelt Klassenmetadaten-Speicher (sonst unbegrenzt -> Risiko fuer
#   natives OOM ausserhalb des Heaps)
# -XX:MaxDirectMemorySize=32m: deckelt NIO-Direct-Buffers (von Tomcat genutzt), verhindert
#   unbemerktes Off-Heap-Wachstum
# -XX:-UsePerfData: kein Schreiben von /tmp/hsperfdata_*; passt zu readOnlyRootFilesystem und
#   spart I/O
# -XX:+UseSerialGC: Single-Threaded GC passend zu 1 CPU-Core, kein Overhead durch Parallel-/G1-GC-Threads
# -XX:ActiveProcessorCount=1: JVM sieht nur 1 Core; muss zum CPU-Limit unten passen, sonst
#   ueberschaetzte Thread-Pools/GC-Threads
ENTRYPOINT ["java", \
  "-XX:SharedArchiveFile=/app/app.jsa", \
  "-Dspring.aot.enabled=true", \
  "-Djava.security.egd=file:/dev/./urandom", \
  "-XX:+ExitOnOutOfMemoryError", \
  "-XX:MaxRAMPercentage=70.0", \
  "-XX:InitialRAMPercentage=70.0", \
  "-XX:MaxMetaspaceSize=96m", \
  "-XX:MaxDirectMemorySize=32m", \
  "-XX:-UsePerfData", \
  "-XX:+UseSerialGC", \
  "-XX:ActiveProcessorCount=1", \
  "org.springframework.boot.loader.launch.JarLauncher"]
