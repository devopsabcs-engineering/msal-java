package com.example.evidence.controller;

import com.example.evidence.model.Case;
import com.example.evidence.model.CreateCaseRequest;
import com.example.evidence.service.CaseService;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/cases")
public class CaseController {

    private final CaseService caseService;

    public CaseController(CaseService caseService) {
        this.caseService = caseService;
    }

    @GetMapping
    @PreAuthorize("hasAuthority('SCOPE_Evidence.Read')")
    public ResponseEntity<List<Case>> listCases() {
        return ResponseEntity.ok(caseService.findAll());
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('SCOPE_Evidence.Read')")
    public ResponseEntity<Case> getCase(@PathVariable String id) {
        return caseService.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    // Exercise 3 Solution: Role-protected POST endpoint
    @PostMapping
    @PreAuthorize("hasAuthority('ROLE_CaseAdmin')")
    public ResponseEntity<Case> createCase(
            @RequestBody CreateCaseRequest request,
            @AuthenticationPrincipal Jwt jwt) {

        String createdBy = jwt.getClaimAsString("preferred_username");
        Case newCase = caseService.create(request, createdBy);
        return ResponseEntity.status(HttpStatus.CREATED).body(newCase);
    }
}
