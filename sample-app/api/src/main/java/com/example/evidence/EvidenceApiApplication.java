package com.example.evidence;

import com.microsoft.applicationinsights.attach.ApplicationInsights;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class EvidenceApiApplication {

    public static void main(String[] args) {
        ApplicationInsights.attach();
        SpringApplication.run(EvidenceApiApplication.class, args);
    }
}
