package com.example.evidence.controller;

import com.example.evidence.service.CaseService;
import com.example.evidence.service.StorageService;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/evidence")
public class EvidenceController {

    private final StorageService storageService;
    private final CaseService caseService;

    public EvidenceController(StorageService storageService, CaseService caseService) {
        this.storageService = storageService;
        this.caseService = caseService;
    }

    @GetMapping("/{id}/download")
    @PreAuthorize("hasAuthority('SCOPE_Evidence.Read')")
    public ResponseEntity<Resource> downloadEvidence(@PathVariable String id) {
        String filename = caseService.getFilenameForEvidenceId(id);
        if (filename == null) {
            return ResponseEntity.notFound().build();
        }

        Resource resource = storageService.downloadEvidence(id);
        String contentType = storageService.getContentType(id);

        return ResponseEntity.ok()
            .contentType(MediaType.parseMediaType(contentType))
            .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + filename + "\"")
            .body(resource);
    }
}
