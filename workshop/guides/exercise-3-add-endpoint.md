---
title: "Exercise 3: Add a Role-Protected Endpoint"
description: "Step-by-step guide for experiencing the full RBAC cycle from 403 Forbidden to 201 Created through Entra ID role assignment"
ms.date: 2026-04-20
ms.topic: tutorial
estimated_reading_time: 5
---

## Objective

Experience the full role-based access control (RBAC) cycle: attempt a protected operation (403 Forbidden), assign the required app role, re-authenticate, and successfully complete the operation (201 Created). This exercise demonstrates how Entra ID app roles propagate through JWT tokens and enforce authorization in the API.

**Duration:** 20 minutes

**Prerequisite:** Exercise 2 completed (both applications running locally with a valid sign-in session).

## Steps

### Step 0: Enable JWT Validation and Method Security

The `dev` profile permits all requests and disables `@PreAuthorize` to allow exploration. To experience the RBAC cycle, you must switch to a profile with real JWT validation.

1. Stop the API if it is running (Ctrl+C).
2. Set your Entra ID configuration as environment variables:

```bash
export JWT_ISSUER_URI=https://login.microsoftonline.com/<TENANT-ID>/v2.0
export JWT_AUDIENCE=api://<API-CLIENT-ID>
export SPRING_PROFILES_ACTIVE=prod
```

3. Restart the API:

```bash
cd sample-app/api
mvn spring-boot:run
```

> **Why?** Method security annotations (`@PreAuthorize`) are only enforced in non-dev profiles. The `MethodSecurityConfig` class enables `@EnableMethodSecurity` only for the `!dev` profile.

### Step 1: Examine the POST Endpoint

Open `sample-app/api/src/main/java/com/example/evidence/controller/CaseController.java` and locate the `POST /api/cases` method. Notice the `@PreAuthorize("hasAuthority('ROLE_CaseAdmin')")` annotation. This annotation restricts the endpoint to users whose JWT contains `CaseAdmin` in the `roles` claim.

```java
@PostMapping
@PreAuthorize("hasAuthority('ROLE_CaseAdmin')")
public ResponseEntity<Case> createCase(@RequestBody CreateCaseRequest request) {
    // ...
}
```

### Step 2: Attempt to Create a Case (Expect 403)

With your current sign-in session (which has no `CaseAdmin` role assigned), attempt to create a case.

Option A: Use the SPA form (if you add the component from the solution files) and observe the 403 error response.

Option B: Use curl with your current Bearer token:

```bash
TOKEN=$(cat <<'EOF'
<paste-your-access-token-from-browser-dev-tools>
EOF
)

curl -X POST http://localhost:8080/api/cases \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title": "Test Case", "description": "Testing role-based access"}' \
  -w "\nHTTP Status: %{http_code}\n"
```

Expected result: **403 Forbidden**. Your token does not contain the `CaseAdmin` role.

### Step 3: Inspect Your Current JWT

Decode your access token at [https://jwt.ms](https://jwt.ms) and look for the `roles` claim. It is either absent or contains only `CaseReader`. The `CaseAdmin` value is not present because you have not been assigned that role yet.

### Step 4: Assign the CaseAdmin Role

1. Open [https://entra.microsoft.com](https://entra.microsoft.com).
2. Navigate to **Identity > Applications > Enterprise applications**.
3. Find the **Evidence API** application (search by name).
4. Go to **Users and groups** and select **Add user/group**.
5. Select your user account and assign the **Case Admin** role.
6. Select **Assign**.

### Step 5: Sign Out and Sign Back In

Return to the SPA and sign out. Then sign in again. This is the critical step: the previous access token is cached and still lacks the `CaseAdmin` role. A fresh sign-in forces Entra ID to issue a new token that includes the newly assigned role.

> **Key learning:** Tokens are cached by MSAL. Role changes in Entra ID do not take effect until the user obtains a new token. In production, token lifetimes (typically 60-90 minutes) determine how long stale role assignments persist.

### Step 6: Attempt to Create a Case Again (Expect 201)

Repeat the case creation request from Step 2 (using the new token from your fresh sign-in).

Expected result: **201 Created**. The response body contains the newly created case with a generated case ID.

### Step 7: Verify the New Case Appears

Navigate to `/cases` in the SPA and confirm the new case appears in the case list with the title and description you provided.

### Step 8: Inspect the Updated JWT

Decode your new access token at [https://jwt.ms](https://jwt.ms). Verify the `roles` claim now includes `CaseAdmin`:

```json
{
  "roles": ["CaseAdmin"],
  "scp": "Evidence.Read",
  "aud": "api://<api-client-id>"
}
```

### Step 9: Understand the Authorization Chain

Review the complete authorization path:

1. Entra ID issues a JWT with `roles: ["CaseAdmin"]` after role assignment and re-authentication.
2. The SPA attaches the token as a Bearer header via `MsalInterceptor`.
3. Spring Security's JWT decoder validates the token signature and audience.
4. Spring Security maps the `roles` claim values to `ROLE_`-prefixed authorities.
5. `@PreAuthorize("hasAuthority('ROLE_CaseAdmin')")` checks for the authority and allows the request.

### Step 10: Bonus, Add a CaseAdmin-Only UI Element

If time permits, add a conditional element in the Angular SPA that only appears for users with the `CaseAdmin` role. Check the `roles` claim in the ID token or access token claims to conditionally render a "Create Case" button.

## Key Takeaways

- App roles are defined in the API app registration and assigned through Enterprise applications.
- Role claims appear in the JWT only after assignment **and** re-authentication.
- `@PreAuthorize` annotations enforce role requirements at the method level.
- Spring Security automatically prefixes role claim values with `ROLE_` when mapping to authorities.

## Solution Files

If you need to check your work or catch up, solution files are available:

- `workshop/solutions/exercise-3-solution/CaseController.java` contains the complete POST endpoint.
- `workshop/solutions/exercise-3-solution/case-create.component.ts` contains the Angular form component.

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Still getting 403 after role assignment | Did not sign out and sign back in | Sign out of the SPA, then sign in again to get a fresh token with the updated roles claim |
| Role not visible in Enterprise applications | Looking at the App registration instead of Enterprise application | App roles are assigned under **Enterprise applications**, not App registrations |
| `roles` claim missing from JWT | Role assignment did not propagate | Wait 1-2 minutes, sign out, sign back in, and check the token again |
| 500 error on POST instead of 201 | Request body missing required fields | Ensure the JSON body includes `title` and `description` fields |
| `@PreAuthorize` not enforced (any user can POST) | Running with the `dev` profile which disables method security | Restart the API with a non-dev profile: set `SPRING_PROFILES_ACTIVE=prod` and provide `JWT_ISSUER_URI` and `JWT_AUDIENCE` environment variables |
