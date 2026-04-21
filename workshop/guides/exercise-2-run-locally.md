---
title: "Exercise 2: Run SPA + API Locally"
description: "Step-by-step guide for building and running both applications locally and verifying the authentication flow end-to-end"
ms.date: 2026-04-20
ms.topic: tutorial
estimated_reading_time: 5
---

## Objective

Build and run both the Spring Boot API and Angular SPA locally, then verify the complete authentication and authorization flow end-to-end. By the end of this exercise, you can sign in, browse cases, download evidence files, and sign out.

**Duration:** 30 minutes

**Prerequisite:** Exercise 1 completed (app registrations configured with real values in `environment.ts` and `application-dev.properties`).

## Steps

### Step 1: Start the API

Open a terminal, navigate to the API project, and start it with the `dev` profile:

```bash
cd sample-app/api
mvn spring-boot:run -Dspring-boot.run.profiles=dev
```

Wait for the log line `Started EvidenceApiApplication` before proceeding. The API runs on `http://localhost:8080`.

### Step 2: Verify the API Requires Authentication

In a second terminal, send an unauthenticated request:

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/me
```

Expected result: `401`. This confirms the API rejects requests without a valid Bearer token.

### Step 3: Install SPA Dependencies and Start the SPA

Open a third terminal:

```bash
cd sample-app/spa
npm install
ng serve
```

Wait for the `Compiled successfully` message. The SPA runs on `http://localhost:4200`.

### Step 4: Open the SPA in Your Browser

Navigate to [http://localhost:4200](http://localhost:4200). The landing page displays with a **Sign In** button.

### Step 5: Sign In with Entra ID

1. Select **Sign In**.
2. The browser redirects to the Microsoft login page.
3. Enter your workshop credentials and complete any MFA prompts.
4. After successful authentication, you are redirected back to the SPA.

Verify your display name appears in the navigation bar, confirming the ID token was received.

### Step 6: Browse Cases

Navigate to `/cases` (or select **Cases** in the navigation). The case list table loads with sample data including case IDs, titles, statuses, and assigned investigators.

If the table is empty or you see an error, check the browser developer tools Network tab for failed API requests.

### Step 7: View Case Details

Select any case from the list to open its detail view. Verify:

- Case metadata (ID, title, status, investigator) displays correctly
- Evidence files are listed with filenames and classifications

### Step 8: Download an Evidence File

Select the download link on any evidence file (for example, `witness-statement.pdf`). The file downloads and opens as a PDF. In the dev profile, evidence files are served from the local filesystem rather than Azure Blob Storage.

### Step 9: Inspect the JWT in Browser Developer Tools

1. Open browser developer tools (F12).
2. Go to the **Network** tab and find any request to `/api/`.
3. Examine the `Authorization` header: it contains `Bearer <token>`.
4. Copy the token value and decode it at [https://jwt.ms](https://jwt.ms).
5. Verify these claims:
   - `aud` matches your API's Application ID URI (`api://<api-client-id>`)
   - `scp` contains `Evidence.Read`
   - `preferred_username` matches your sign-in email
   - `tid` matches your tenant ID

### Step 10: Sign Out

Select **Sign Out** in the navigation bar. Verify:

- The browser redirects to the landing page
- The Sign In button reappears
- Navigating to `/cases` redirects back to the sign-in prompt (MsalGuard enforcement)

## Verification

Confirm each of these items works correctly:

- [ ] API starts and returns 401 for unauthenticated requests
- [ ] SPA compiles and loads at `http://localhost:4200`
- [ ] Sign-in redirects to Entra ID and returns an authenticated session
- [ ] Case list loads with sample data
- [ ] Case detail page shows metadata and evidence files
- [ ] Evidence file downloads as a valid PDF
- [ ] JWT contains correct `aud`, `scp`, and identity claims
- [ ] Sign-out clears the session and redirects to the landing page

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| CORS error in browser console | The API does not allow requests from `http://localhost:4200` | Verify the CORS configuration in `SecurityConfig.java` includes `http://localhost:4200` as an allowed origin |
| "redirect_uri mismatch" from Entra ID | The SPA app registration redirect URI does not match the actual URL | Go to the SPA app registration in Entra Admin Center, check the SPA platform redirect URI is exactly `http://localhost:4200` (no trailing slash) |
| "invalid audience" from the API (401) | The JWT's `aud` claim does not match the API's expected audience | Verify `spring.security.oauth2.resourceserver.jwt.audiences` in `application-dev.properties` matches the API's Application ID URI |
| `npm install` fails | Node.js version mismatch or network issue | Confirm `node --version` returns 20.x or later; delete `node_modules` and `package-lock.json`, then retry |
| `mvn spring-boot:run` fails with "no compiler" | `JAVA_HOME` not set or pointing to a JRE instead of JDK | Set `JAVA_HOME` to the JDK 17 installation directory and add `$JAVA_HOME/bin` to PATH |
| Case list is empty but no errors | API started without the `dev` profile | Restart the API with `-Dspring-boot.run.profiles=dev` to load sample data |
| Sign-in loop (keeps redirecting to login) | Third-party cookies blocked by browser | Use Chrome or Edge with default cookie settings, or try an incognito/private window |
