import { Injectable } from '@angular/core';
import { MsalService } from '@azure/msal-angular';
import {
  AccountInfo,
  AuthenticationResult,
  SilentRequest,
} from '@azure/msal-browser';
import { from, Observable, of } from 'rxjs';
import { catchError, map, shareReplay } from 'rxjs/operators';
import { loginRequest } from '../auth-config';

/**
 * Application roles defined in the Microsoft Entra ID app registration
 * (App roles → "value" field). Surfaced to the SPA via the `roles`
 * claim on the ID token.
 */
export const ROLE_CASE_READER = 'CaseReader';
export const ROLE_CASE_ADMIN = 'CaseAdmin';

/**
 * Lightweight wrapper around MsalService that exposes the role and
 * token helpers the UI needs without forcing components to know about
 * MSAL internals.
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  constructor(private msalService: MsalService) {}

  /** Currently signed-in account, or null when no one is signed in. */
  getActiveAccount(): AccountInfo | null {
    const active = this.msalService.instance.getActiveAccount();
    if (active) {
      return active;
    }
    const accounts = this.msalService.instance.getAllAccounts();
    return accounts.length > 0 ? accounts[0] : null;
  }

  /** App roles from the ID token `roles` claim. */
  getRoles(): string[] {
    const account = this.getActiveAccount();
    if (!account) {
      return [];
    }
    const claims = account.idTokenClaims as
      | Record<string, unknown>
      | undefined;
    const roles = claims?.['roles'];
    return Array.isArray(roles) ? roles.map((r) => String(r)) : [];
  }

  /**
   * Effective app roles for the user. Entra ID emits the `roles` claim
   * on the API access token by default, and only on the ID token when
   * the app registration explicitly opts in via optional claims. We
   * therefore prefer the access token as the source of truth and fall
   * back to the ID token claims when the access token is unavailable.
   */
  getEffectiveRoles$(): Observable<string[]> {
    return this.getAccessToken().pipe(
      map((token) => {
        if (token) {
          const claims = decodeJwtPayload(token);
          const roles = claims?.['roles'];
          if (Array.isArray(roles)) {
            return roles.map((r) => String(r));
          }
        }
        return this.getRoles();
      }),
      shareReplay({ bufferSize: 1, refCount: true }),
    );
  }

  hasAnyRole(...roles: string[]): boolean {
    if (roles.length === 0) {
      return false;
    }
    const userRoles = this.getRoles();
    return roles.some((r) => userRoles.includes(r));
  }

  /** True when the signed-in user can download evidence files. */
  canDownloadEvidence(): boolean {
    return this.hasAnyRole(ROLE_CASE_READER, ROLE_CASE_ADMIN);
  }

  /**
   * Async variant of {@link canDownloadEvidence} that consults the
   * access token roles. Use this in components — the synchronous
   * helper only sees the ID token claims, which Entra often omits.
   */
  canDownloadEvidence$(): Observable<boolean> {
    return this.getEffectiveRoles$().pipe(
      map(
        (roles) =>
          roles.includes(ROLE_CASE_READER) || roles.includes(ROLE_CASE_ADMIN),
      ),
    );
  }

  /**
   * Acquire the current API access token silently from the MSAL cache,
   * refreshing via the hidden iframe / refresh token when needed.
   *
   * @param forceRefresh When true, bypass the MSAL token cache and
   *   request a freshly minted access token from Entra ID.
   */
  getAccessToken(forceRefresh = false): Observable<string | null> {
    const account = this.getActiveAccount();
    if (!account) {
      return of(null);
    }
    const request: SilentRequest = {
      scopes: loginRequest.scopes,
      account,
      forceRefresh,
    };
    return from(this.msalService.instance.acquireTokenSilent(request)).pipe(
      map((res: AuthenticationResult) => res.accessToken),
      catchError((err) => {
        console.warn('acquireTokenSilent failed', err);
        return of(null);
      }),
    );
  }

  /** ID token cached after the most recent sign-in. */
  getIdToken(): string | null {
    return this.getActiveAccount()?.idToken ?? null;
  }

  /**
   * Copy the supplied text to the clipboard. Returns true on success.
   * Falls back to a hidden textarea when the async clipboard API is
   * unavailable (e.g. older browsers / non-secure contexts).
   */
  async copyToClipboard(text: string): Promise<boolean> {
    if (!text) {
      return false;
    }
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(text);
        return true;
      }
    } catch (err) {
      console.warn('navigator.clipboard.writeText failed', err);
    }
    try {
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.setAttribute('readonly', '');
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      const ok = document.execCommand('copy');
      document.body.removeChild(textarea);
      return ok;
    } catch (err) {
      console.warn('Fallback clipboard copy failed', err);
      return false;
    }
  }
}

/**
 * Decode the payload of a JWT (header.payload.signature) without
 * verifying the signature. Used purely for reading non-sensitive
 * claims (e.g. `roles`) on the client. The signature is validated
 * server-side by the API.
 */
function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const parts = token.split('.');
  if (parts.length < 2) {
    return null;
  }
  try {
    const base64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const padded = base64.padEnd(
      base64.length + ((4 - (base64.length % 4)) % 4),
      '=',
    );
    const json = decodeURIComponent(
      atob(padded)
        .split('')
        .map((c) => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2))
        .join(''),
    );
    return JSON.parse(json) as Record<string, unknown>;
  } catch (err) {
    console.warn('Failed to decode JWT payload', err);
    return null;
  }
}
