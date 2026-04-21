---
title: "Exercise 1: Configure App Registrations"
description: "Step-by-step guide for creating and configuring two Entra ID app registrations for the SPA and API"
ms.date: 2026-04-20
ms.topic: tutorial
estimated_reading_time: 5
---

## Objective

Create and configure two Entra ID app registrations: one for the Spring Boot API and one for the Angular SPA. By the end of this exercise, both applications have the configuration values needed to authenticate users and authorize API calls.

**Duration:** 30 minutes

## Steps

### Step 1: Open the Entra Admin Center

Navigate to [https://entra.microsoft.com](https://entra.microsoft.com) and sign in with your workshop account. Go to **Identity > Applications > App registrations**.

### Step 2: Create the API App Registration

1. Select **New registration**.
2. Set the name to `Evidence API - <your-initials>` (for example, `Evidence API - JD`).
3. Under **Supported account types**, select **Accounts in this organizational directory only (Single tenant)**.
4. Leave **Redirect URI** blank (the API does not need one).
5. Select **Register**.
6. Record the **Application (client) ID** and **Directory (tenant) ID** from the Overview page.

### Step 3: Expose the API and Add a Scope

1. In the API registration, go to **Manage > Expose an API**.
2. Select **Add** next to **Application ID URI**. Accept the default value (`api://<client-id>`) and select **Save**.
3. Select **Add a scope** with these values:

   | Field | Value |
   |-------|-------|
   | Scope name | `Evidence.Read` |
   | Who can consent | Admins and users |
   | Admin consent display name | Read evidence data |
   | Admin consent description | Allows the app to read evidence cases and files on behalf of the signed-in user |
   | State | Enabled |

4. Select **Add scope**.

### Step 4: Create App Roles

1. In the API registration, go to **Manage > App roles**.
2. Select **Create app role** and create two roles:

   | Display Name | Value | Allowed Member Types | Description |
   |-------------|-------|---------------------|-------------|
   | Case Reader | `CaseReader` | Users/Groups | Can view cases and download evidence |
   | Case Admin | `CaseAdmin` | Users/Groups | Can create and manage cases |

3. Verify both roles show **Enabled** status.

### Step 5: Create the SPA App Registration

1. Return to **App registrations** and select **New registration**.
2. Set the name to `Evidence SPA - <your-initials>`.
3. Under **Supported account types**, select **Accounts in this organizational directory only (Single tenant)**.
4. Under **Redirect URI**, select platform **Single-page application (SPA)** and enter `http://localhost:4200`.
5. Select **Register**.
6. Record the **Application (client) ID** from the Overview page.

### Step 6: Configure API Permissions on the SPA

1. In the SPA registration, go to **Manage > API permissions**.
2. Select **Add a permission > My APIs** and find the `Evidence API` registration.
3. Select **Delegated permissions**, check `Evidence.Read`, and select **Add permissions**.
4. If available, select **Grant admin consent** for the directory.

### Step 7: Pre-Authorize the SPA on the API

1. Return to the **API registration** and go to **Manage > Expose an API**.
2. Under **Authorized client applications**, select **Add a client application**.
3. Enter the SPA's **Application (client) ID**.
4. Check the `Evidence.Read` scope.
5. Select **Add application**.

### Step 8: Record Configuration Values

Collect these values from the Azure portal. You need them for the next two steps.

| Value | Where to Find It |
|-------|------------------|
| Tenant ID | API registration > Overview > Directory (tenant) ID |
| API Client ID | API registration > Overview > Application (client) ID |
| API Scope URI | API registration > Expose an API > `api://<api-client-id>/Evidence.Read` |
| SPA Client ID | SPA registration > Overview > Application (client) ID |

### Step 9: Update the SPA Configuration

Open `sample-app/spa/src/environments/environment.ts` and replace the placeholder values:

```typescript
export const environment = {
  production: false,
  msalConfig: {
    auth: {
      clientId: '<SPA-CLIENT-ID>',
      authority: 'https://login.microsoftonline.com/<TENANT-ID>',
      redirectUri: 'http://localhost:4200',
    },
  },
  apiConfig: {
    uri: 'http://localhost:8080/api',
    scopes: ['api://<API-CLIENT-ID>/Evidence.Read'],
  },
};
```

### Step 10: Update the API Configuration

Open `sample-app/api/src/main/resources/application-dev.properties` and replace the placeholder values:

```properties
spring.cloud.azure.active-directory.credential.client-id=<API-CLIENT-ID>
spring.cloud.azure.active-directory.profile.tenant-id=<TENANT-ID>
spring.security.oauth2.resourceserver.jwt.audiences=api://<API-CLIENT-ID>
spring.security.oauth2.resourceserver.jwt.issuer-uri=https://login.microsoftonline.com/<TENANT-ID>/v2.0
```

## Scripted Alternative

If you prefer an automated approach or are running short on time, run the setup script:

```bash
cd scripts
chmod +x setup-entra-apps.sh
./setup-entra-apps.sh
```

The script creates both registrations, configures scopes and roles, and writes the configuration values to the appropriate files. Review the output to confirm all values were set correctly.

## Verification

Confirm your setup by checking these items:

- [ ] API app registration exists with `Evidence.Read` scope exposed
- [ ] `CaseReader` and `CaseAdmin` app roles are created and enabled
- [ ] SPA app registration exists with `http://localhost:4200` as the redirect URI
- [ ] SPA has `Evidence.Read` delegated permission granted
- [ ] SPA is pre-authorized on the API
- [ ] `environment.ts` contains real Client ID, Tenant ID, and scope URI
- [ ] `application-dev.properties` contains real Client ID, Tenant ID, and audience

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| "Insufficient privileges" when creating registrations | Your account lacks the Application Developer role | Ask the workshop instructor to assign the role or create the registration for you |
| Scope not visible under "My APIs" | The API registration does not have an Application ID URI set | Go to Expose an API and add the Application ID URI first |
| "AADSTS650053" error on sign-in | Admin consent not granted for the delegated permission | Grant admin consent in the SPA's API permissions page |
| Wrong account type selected | Chose "Personal Microsoft accounts" instead of single tenant | Delete the registration and recreate with the correct account type |
