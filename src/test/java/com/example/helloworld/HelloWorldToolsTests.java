package com.example.helloworld;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Instant;

import org.junit.jupiter.api.Test;

class HelloWorldToolsTests {

	private final HelloWorldTools tools = new HelloWorldTools();

	@Test
	void greetReturnsGreeting() {
		assertThat(tools.greet("Ada")).isEqualTo("Hello, Ada! Welcome to the MCP Hello World Server.");
	}

	@Test
	void greetAcceptsMaxLength() {
		String name = "a".repeat(HelloWorldTools.MAX_NAME_LENGTH);
		assertThat(tools.greet(name)).contains(name);
	}

	@Test
	void greetRejectsNullAndBlank() {
		assertThatThrownBy(() -> tools.greet(null)).isInstanceOf(IllegalArgumentException.class);
		assertThatThrownBy(() -> tools.greet("  ")).isInstanceOf(IllegalArgumentException.class);
	}

	@Test
	void greetRejectsTooLongName() {
		String name = "a".repeat(HelloWorldTools.MAX_NAME_LENGTH + 1);
		assertThatThrownBy(() -> tools.greet(name)).isInstanceOf(IllegalArgumentException.class);
	}

	@Test
	void serverTimeReturnsCurrentIsoInstant() {
		Instant before = Instant.now();
		Instant time = Instant.parse(tools.serverTime());
		assertThat(time).isBetween(before, Instant.now());
	}
}
