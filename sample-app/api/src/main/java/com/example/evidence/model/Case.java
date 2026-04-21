package com.example.evidence.model;

import java.util.ArrayList;
import java.util.List;

public class Case {

    private String id;
    private String title;
    private String status;
    private String assignedTo;
    private String description;
    private List<EvidenceFile> evidenceFiles = new ArrayList<>();

    public Case() {
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getTitle() {
        return title;
    }

    public void setTitle(String title) {
        this.title = title;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public String getAssignedTo() {
        return assignedTo;
    }

    public void setAssignedTo(String assignedTo) {
        this.assignedTo = assignedTo;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public List<EvidenceFile> getEvidenceFiles() {
        return evidenceFiles;
    }

    public void setEvidenceFiles(List<EvidenceFile> evidenceFiles) {
        this.evidenceFiles = evidenceFiles;
    }
}
