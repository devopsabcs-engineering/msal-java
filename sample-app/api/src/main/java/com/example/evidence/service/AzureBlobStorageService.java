package com.example.evidence.service;

import com.azure.storage.file.datalake.DataLakeFileClient;
import com.azure.storage.file.datalake.DataLakeFileSystemClient;
import com.azure.storage.file.datalake.DataLakeServiceClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Service;

import java.io.ByteArrayOutputStream;

/**
 * Production storage backend. Reads evidence files from ADLS Gen2 over a
 * Private Endpoint using a system-assigned Managed Identity. The file
 * system ("evidence") corresponds to the container created in Bicep on the
 * HNS-enabled storage account.
 */
@Service
@Profile("!dev")
public class AzureBlobStorageService implements StorageService {

    private final DataLakeServiceClient dataLakeServiceClient;
    private final CaseService caseService;

    @Value("${azure.storage.container-name:evidence}")
    private String fileSystemName;

    public AzureBlobStorageService(DataLakeServiceClient dataLakeServiceClient, CaseService caseService) {
        this.dataLakeServiceClient = dataLakeServiceClient;
        this.caseService = caseService;
    }

    @Override
    public Resource downloadEvidence(String fileId) {
        String filename = caseService.getFilenameForEvidenceId(fileId);
        if (filename == null) {
            throw new RuntimeException("Evidence file not found: " + fileId);
        }

        DataLakeFileSystemClient fileSystemClient =
            dataLakeServiceClient.getFileSystemClient(fileSystemName);
        DataLakeFileClient fileClient = fileSystemClient.getFileClient(filename);

        ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
        fileClient.read(outputStream);
        return new ByteArrayResource(outputStream.toByteArray());
    }

    @Override
    public String getContentType(String fileId) {
        return "application/pdf";
    }
}
