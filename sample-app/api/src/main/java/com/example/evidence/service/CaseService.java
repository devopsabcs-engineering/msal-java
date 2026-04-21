package com.example.evidence.service;

import com.example.evidence.model.Case;
import com.example.evidence.model.EvidenceFile;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Service
public class CaseService {

    private final List<Case> cases = new ArrayList<>();
    private final ObjectMapper objectMapper;

    public CaseService(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @PostConstruct
    public void init() throws IOException {
        InputStream inputStream = new ClassPathResource("data/sample-cases.json").getInputStream();
        List<Case> loaded = objectMapper.readValue(inputStream, new TypeReference<List<Case>>() {});
        cases.addAll(loaded);
    }

    public List<Case> getAllCases() {
        return List.copyOf(cases);
    }

    public Optional<Case> getCaseById(String id) {
        return cases.stream()
            .filter(c -> c.getId().equals(id))
            .findFirst();
    }

    public Case createCase(Case newCase) {
        newCase.setId("CASE-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase());
        cases.add(newCase);
        return newCase;
    }

    public String getFilenameForEvidenceId(String fileId) {
        return cases.stream()
            .flatMap(c -> c.getEvidenceFiles().stream())
            .filter(ef -> ef.getId().equals(fileId))
            .map(EvidenceFile::getFilename)
            .findFirst()
            .orElse(null);
    }
}
