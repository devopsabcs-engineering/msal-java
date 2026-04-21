package com.example.evidence.controller;

import com.example.evidence.dto.CaseDetailResponse;
import com.example.evidence.dto.CaseListResponse;
import com.example.evidence.model.Case;
import com.example.evidence.service.CaseService;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api")
public class CaseController {

    private final CaseService caseService;

    public CaseController(CaseService caseService) {
        this.caseService = caseService;
    }

    @GetMapping("/cases")
    @PreAuthorize("hasAuthority('SCOPE_Evidence.Read')")
    public List<CaseListResponse> getAllCases() {
        return caseService.getAllCases().stream()
            .map(c -> new CaseListResponse(c.getId(), c.getTitle(), c.getStatus(), c.getAssignedTo()))
            .collect(Collectors.toList());
    }

    @GetMapping("/cases/{id}")
    @PreAuthorize("hasAuthority('SCOPE_Evidence.Read')")
    public ResponseEntity<CaseDetailResponse> getCaseById(@PathVariable String id) {
        return caseService.getCaseById(id)
            .map(c -> {
                CaseDetailResponse response = new CaseDetailResponse();
                response.setId(c.getId());
                response.setTitle(c.getTitle());
                response.setStatus(c.getStatus());
                response.setAssignedTo(c.getAssignedTo());
                response.setDescription(c.getDescription());
                response.setEvidenceFiles(c.getEvidenceFiles());
                return ResponseEntity.ok(response);
            })
            .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping("/cases")
    @PreAuthorize("hasAuthority('ROLE_CaseAdmin')")
    public ResponseEntity<CaseDetailResponse> createCase(@RequestBody Case newCase) {
        Case created = caseService.createCase(newCase);
        CaseDetailResponse response = new CaseDetailResponse();
        response.setId(created.getId());
        response.setTitle(created.getTitle());
        response.setStatus(created.getStatus());
        response.setAssignedTo(created.getAssignedTo());
        response.setDescription(created.getDescription());
        response.setEvidenceFiles(created.getEvidenceFiles());
        return ResponseEntity.ok(response);
    }

    @GetMapping("/me")
    public Map<String, Object> getCurrentUser(JwtAuthenticationToken authentication) {
        Map<String, Object> userInfo = new HashMap<>();
        userInfo.put("name", authentication.getToken().getClaimAsString("name"));
        userInfo.put("preferred_username", authentication.getToken().getClaimAsString("preferred_username"));
        userInfo.put("roles", authentication.getToken().getClaimAsStringList("roles"));
        userInfo.put("scp", authentication.getToken().getClaimAsString("scp"));
        return userInfo;
    }
}
