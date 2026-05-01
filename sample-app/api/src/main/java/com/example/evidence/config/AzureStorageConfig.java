package com.example.evidence.config;

import com.azure.core.credential.TokenCredential;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.identity.ManagedIdentityCredentialBuilder;
import com.azure.storage.file.datalake.DataLakeServiceClient;
import com.azure.storage.file.datalake.DataLakeServiceClientBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

/**
 * Builds a DataLakeServiceClient for ADLS Gen2 using a Managed Identity
 * (or Azure CLI / dev credential). Shared keys are disabled on the target
 * storage account; all auth flows through Entra ID + Storage Blob Data
 * Contributor RBAC.
 *
 * The endpoint targets *.dfs.core.windows.net which, from inside the VNet,
 * resolves to the Private Endpoint NIC IP via the privatelink.dfs.* DNS
 * zone. From outside the VNet (e.g. local dev), the public DFS endpoint is
 * used and access is gated by the storage networkAcls.
 *
 * When running in App Service we pin to ManagedIdentityCredential to
 * avoid the DefaultAzureCredential chain falling back to a stale or wrong
 * principal (the chain has logged "EnvironmentCredential unavailable"
 * before failing over). The presence of the IDENTITY_ENDPOINT environment
 * variable is the standard signal that an MI endpoint is available.
 */
@Configuration
@Profile("!dev")
public class AzureStorageConfig {

    @Value("${azure.storage.account-name}")
    private String accountName;

    @Bean
    public DataLakeServiceClient dataLakeServiceClient() {
        return new DataLakeServiceClientBuilder()
            .endpoint("https://" + accountName + ".dfs.core.windows.net")
            .credential(buildCredential())
            .buildClient();
    }

    private TokenCredential buildCredential() {
        if (System.getenv("IDENTITY_ENDPOINT") != null) {
            return new ManagedIdentityCredentialBuilder().build();
        }
        return new DefaultAzureCredentialBuilder().build();
    }
}
