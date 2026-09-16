package com.example.helloworld;

import org.springframework.ai.mcp.annotation.McpResource;
import org.springframework.ai.mcp.annotation.McpTool;
import org.springframework.ai.mcp.annotation.McpToolParam;
import org.springframework.stereotype.Service;

@Service
public class HelloWorldTools {

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
    public String greet(@McpToolParam(description = "Name of the person to greet", required = true) String name) {
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
