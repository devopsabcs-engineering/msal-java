package com.example.evidence.service;

import org.springframework.core.io.Resource;

public interface StorageService {

    Resource downloadEvidence(String fileId);

    String getContentType(String fileId);
}
