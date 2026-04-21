package com.example.evidence.service;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobServiceClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Service;

import java.io.ByteArrayOutputStream;

@Service
@Profile("!dev")
public class AzureBlobStorageService implements StorageService {

    private final BlobServiceClient blobServiceClient;
    private final CaseService caseService;

    @Value("${azure.storage.container-name:evidence}")
    private String containerName;

    public AzureBlobStorageService(BlobServiceClient blobServiceClient, CaseService caseService) {
        this.blobServiceClient = blobServiceClient;
        this.caseService = caseService;
    }

    @Override
    public Resource downloadEvidence(String fileId) {
        String filename = caseService.getFilenameForEvidenceId(fileId);
        if (filename == null) {
            throw new RuntimeException("Evidence file not found: " + fileId);
        }

        BlobClient blobClient = blobServiceClient
            .getBlobContainerClient(containerName)
            .getBlobClient(filename);

        ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
        blobClient.downloadStream(outputStream);
        return new ByteArrayResource(outputStream.toByteArray());
    }

    @Override
    public String getContentType(String fileId) {
        return "application/pdf";
    }
}
