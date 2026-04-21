package com.example.evidence.dto;

public class CaseListResponse {

    private String id;
    private String title;
    private String status;
    private String assignedTo;

    public CaseListResponse() {
    }

    public CaseListResponse(String id, String title, String status, String assignedTo) {
        this.id = id;
        this.title = title;
        this.status = status;
        this.assignedTo = assignedTo;
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
}
