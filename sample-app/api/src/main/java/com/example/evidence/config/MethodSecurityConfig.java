package com.example.evidence.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;

/**
 * Enables @PreAuthorize method-level security only for non-dev profiles.
 * In dev profile, all endpoints are open for exploration before Entra ID setup.
 */
@Configuration
@Profile("!dev")
@EnableMethodSecurity
public class MethodSecurityConfig {
}
