package com.example.evidence.service;

import org.springframework.context.annotation.Profile;
import org.springframework.core.io.ClassPathResource;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Service;

@Service
@Profile("dev")
public class LocalStorageService implements StorageService {

    private final CaseService caseService;

    public LocalStorageService(CaseService caseService) {
        this.caseService = caseService;
    }

    @Override
    public Resource downloadEvidence(String fileId) {
        String filename = caseService.getFilenameForEvidenceId(fileId);
        if (filename == null) {
            throw new RuntimeException("Evidence file not found: " + fileId);
        }
        Resource resource = new ClassPathResource("data/sample-evidence/" + filename);
        if (!resource.exists()) {
            throw new RuntimeException("File not found on classpath: " + filename);
        }
        return resource;
    }

    @Override
    public String getContentType(String fileId) {
        return "application/pdf";
    }
}
