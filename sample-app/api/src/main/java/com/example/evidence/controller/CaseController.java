package com.example.evidence.controller;

import com.example.evidence.dto.CaseDetailResponse;
import com.example.evidence.dto.CaseListResponse;
import com.example.evidence.model.Case;
import com.example.evidence.service.CaseService;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Arrays;
import java.util.Collections;
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
    public Map<String, Object> getCurrentUser(Authentication authentication) {
        Map<String, Object> userInfo = new HashMap<>();
        if (authentication instanceof JwtAuthenticationToken jwtAuth) {
            String preferredUsername = jwtAuth.getToken().getClaimAsString("preferred_username");
            String scp = jwtAuth.getToken().getClaimAsString("scp");
            List<String> scopes = scp == null || scp.isBlank()
                    ? Collections.emptyList()
                    : Arrays.asList(scp.trim().split("\\s+"));
            List<String> roles = jwtAuth.getToken().getClaimAsStringList("roles");
            userInfo.put("name", jwtAuth.getToken().getClaimAsString("name"));
            userInfo.put("email", preferredUsername);
            userInfo.put("preferred_username", preferredUsername);
            userInfo.put("roles", roles == null ? Collections.emptyList() : roles);
            userInfo.put("scopes", scopes);
            userInfo.put("scp", scp);
        } else {
            userInfo.put("name", "Dev User (no JWT)");
            userInfo.put("email", "dev@localhost");
            userInfo.put("preferred_username", "dev@localhost");
            userInfo.put("roles", Collections.emptyList());
            userInfo.put("scopes", Collections.singletonList("Evidence.Read"));
            userInfo.put("scp", "Evidence.Read");
        }
        return userInfo;
    }
}
