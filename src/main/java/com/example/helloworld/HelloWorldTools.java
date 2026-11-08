package com.example.helloworld;

import org.springframework.ai.mcp.annotation.McpResource;
import org.springframework.ai.mcp.annotation.McpTool;
import org.springframework.ai.mcp.annotation.McpToolParam;
import org.springframework.stereotype.Service;

@Service
public class HelloWorldTools {

    static final int MAX_NAME_LENGTH = 100;

    @McpTool(
        name = "greet",
        title = "Greet",
        description = "Returns a greeting message for the given name",
        annotations = @McpTool.McpAnnotations(
            title = "Greet",
            readOnlyHint = true,
            destructiveHint = false,
            idempotentHint = true,
            openWorldHint = false
        )
    )
    public String greet(@McpToolParam(description = "Name of the person to greet (max. 100 characters)", required = true) String name) {
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("name must not be blank");
        }
        if (name.length() > MAX_NAME_LENGTH) {
            throw new IllegalArgumentException("name must not be longer than %d characters".formatted(MAX_NAME_LENGTH));
        }
        return "Hello, %s! Welcome to the MCP Hello World Server.".formatted(name);
    }

    @McpTool(
        name = "serverTime",
        title = "Server Time",
        description = "Returns the current server time as ISO-8601 string",
        annotations = @McpTool.McpAnnotations(
            title = "Server Time",
            readOnlyHint = true,
            destructiveHint = false,
            idempotentHint = false,
            openWorldHint = false
        )
    )
    @McpResource(
        uri = "time://server",
        name = "server-time",
        title = "Server Time",
        description = "Current server time as ISO-8601 string"
    )
    public String serverTime() {
        return java.time.Instant.now().toString();
    }
}
