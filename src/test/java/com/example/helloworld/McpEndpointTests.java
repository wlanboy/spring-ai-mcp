package com.example.helloworld;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class McpEndpointTests {

	@LocalServerPort
	int port;

	private String post(String body) throws Exception {
		HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/mcp"))
			.header("Content-Type", "application/json")
			.header("Accept", "application/json, text/event-stream")
			.POST(HttpRequest.BodyPublishers.ofString(body))
			.build();
		return HttpClient.newHttpClient().send(request, HttpResponse.BodyHandlers.ofString()).body();
	}

	@Test
	void toolsListContainsBothTools() throws Exception {
		String body = post("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}");
		assertThat(body).contains("\"greet\"").contains("\"serverTime\"");
	}

	@Test
	void greetToolCall() throws Exception {
		String body = post("""
				{"jsonrpc":"2.0","id":2,"method":"tools/call",
				 "params":{"name":"greet","arguments":{"name":"Ada"}}}""");
		assertThat(body).contains("Hello, Ada!");
	}

	@Test
	void greetToolCallWithBlankNameFails() throws Exception {
		String body = post("""
				{"jsonrpc":"2.0","id":3,"method":"tools/call",
				 "params":{"name":"greet","arguments":{"name":""}}}""");
		assertThat(body).doesNotContain("Hello,");
	}

	@Test
	void serverTimeToolCall() throws Exception {
		String body = post("""
				{"jsonrpc":"2.0","id":4,"method":"tools/call",
				 "params":{"name":"serverTime","arguments":{}}}""");
		assertThat(body).containsPattern("\\d{4}-\\d{2}-\\d{2}T");
	}
}
