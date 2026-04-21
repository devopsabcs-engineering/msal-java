package com.example.evidence.model;

public class EvidenceFile {

    private String id;
    private String filename;
    private String classification;
    private String uploadedAt;
    private long sizeBytes;

    public EvidenceFile() {
    }

    public EvidenceFile(String id, String filename, String classification, String uploadedAt, long sizeBytes) {
        this.id = id;
        this.filename = filename;
        this.classification = classification;
        this.uploadedAt = uploadedAt;
        this.sizeBytes = sizeBytes;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getFilename() {
        return filename;
    }

    public void setFilename(String filename) {
        this.filename = filename;
    }

    public String getClassification() {
        return classification;
    }

    public void setClassification(String classification) {
        this.classification = classification;
    }

    public String getUploadedAt() {
        return uploadedAt;
    }

    public void setUploadedAt(String uploadedAt) {
        this.uploadedAt = uploadedAt;
    }

    public long getSizeBytes() {
        return sizeBytes;
    }

    public void setSizeBytes(long sizeBytes) {
        this.sizeBytes = sizeBytes;
    }
}
